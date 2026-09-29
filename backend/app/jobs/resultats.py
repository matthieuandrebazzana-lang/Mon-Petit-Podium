"""Job de résultats — récupération OpenF1, calcul des points, clôture du GP.

Deux temps depuis la version `0.78.0` (`docs/audit-evaluation.md` §5.3) :

1. **Provisoire** — le job démarre **1h30 après le départ**, appelle OpenF1
   **toutes les cinq minutes** jusqu'à obtenir un classement, puis écrit les
   verdicts par `attribuer_points` (les `NULL` seuls) et passe le GP en
   `statut_resultats = provisoire`. Les points comptent aussitôt partout. Si
   rien n'est disponible **trois heures** après ce démarrage, il journalise une
   alerte et cesse d'essayer pour ce GP.
2. **Définitif** — **24 heures après `date_course`**, `consolider` relit OpenF1
   en entier (classement, tours, direction de course, qualifications) et
   `remplacer_verdicts` remplace, **dans une seule transaction**, `resultats_gp`
   et TOUS les verdicts du GP, y compris ceux déjà écrits. Le GP passe
   `definitif`. C'est ce qui rattrape les pénalités posées après l'arrivée :
   à Bakou 2026, Bortoleto 13ᵉ à l'arrivée, 15ᵉ au classement définitif.

Après le définitif, **plus aucun recalcul automatique**. Seule la route admin
`POST /jobs/resultats/{gp_id}/recalcul` rejuge un GP définitif, par la même
écriture transactionnelle. Elle remplace `?forcer=true`, dont la remise à
`NULL` puis la réécriture en deux appels pouvaient laisser tout un GP « en
attente » (risque R5).

L'idempotence du provisoire tient toujours à trois étages :

1. **La récupération** — `resultats_gp.gp_id` est `unique`. Si une ligne existe
   déjà, OpenF1 n'est pas rappelée : le calcul est rejoué sur le JSON conservé.
2. **L'attribution** — `public.attribuer_points` n'écrit que les pronostics dont
   `points_gagnes` est encore NULL.
3. **La surveillance** — un GP passé à `termine` sort du champ de la boucle.

Le définitif est idempotent autrement : c'est un calcul pur des données, des
cotes et des pronostics, et `remplacer_verdicts` écrit le même état à chaque
rejeu. Un GP `definitif` sort de sa boucle.

Le définitif n'a pas de fenêtre : il réessaie jusqu'au succès. Chaque échec est
compté en base (`noter_echec_definitif`, migration 26) ; à partir de
`SEUIL_ALERTE_DEFINITIF` échecs consécutifs, le GP apparaît dans le profil
admin avec le nombre de tentatives et la dernière erreur. Un succès efface
l'alerte.

Un seul processus doit porter ces schedulers. Sur le plan gratuit de Railway, le
service tourne en un exemplaire : c'est le cas aujourd'hui. **Le jour où le
service passe à plusieurs instances, deux schedulers tourneront en parallèle** —
la base empêcherait la double attribution (étage 2), mais pas les appels OpenF1
en double. Il faudra alors un verrou (`pg_try_advisory_lock`) ou un worker
dédié.
"""

import logging
from datetime import UTC, datetime, timedelta

from app.calcul import points as calcul
from app.scraper.openf1 import (
    ErreurOpenF1,
    ResultatsIndisponibles,
    completer_qualification,
    recuperer,
)
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    mettre_a_jour,
    selectionner,
    supprimer,
    upserter,
)

logger = logging.getLogger("uvicorn.error")

# Règle 4.3 : le job démarre 1h30 après le départ.
DELAI_APRES_DEPART = timedelta(hours=1, minutes=30)

# Puis toutes les cinq minutes jusqu'à obtenir des données.
INTERVALLE = timedelta(minutes=5)

# Au-delà de trois heures d'essais infructueux, on arrête et on alerte. Une
# course dure deux heures au maximum, réglementairement : 1h30 + 3h laisse une
# marge très large, y compris pour une course interrompue au drapeau rouge.
FENETRE_ESSAIS = timedelta(hours=3)

# Le calcul définitif part 24 heures après le départ : les commissaires ont
# statué, OpenF1 a publié le classement corrigé. Pas « le lundi » : Bakou 2026
# se court un samedi.
DELAI_DEFINITIF = timedelta(hours=24)

# Rythme de la boucle du définitif. Un quart d'heure suffit à une échéance
# d'une journée, et espace les nouvelles tentatives si OpenF1 est indisponible.
INTERVALLE_DEFINITIF = timedelta(minutes=15)

# Nombre d'échecs consécutifs du définitif à partir duquel le GP apparaît dans
# le profil admin (`roadmap.md` §3.17). La boucle, elle, réessaie sans fin :
# trois tours de quinze minutes suffisent à écarter un hoquet d'OpenF1.
SEUIL_ALERTE_DEFINITIF = 3

# `alertes_admin.type` (migration 26).
DEFINITIF_EN_ECHEC = "definitif_en_echec"

# `grands_prix.statut_resultats` (migration `20260926200000`).
PROVISOIRE = "provisoire"
DEFINITIF = "definitif"

# Statuts dont un GP peut encore sortir. `termine` en est absent : un GP terminé
# ne repasse jamais dans la boucle.
#
# `a_venir` y figure alors que la demande ne parlait que de `cotes_figees`, et
# c'est délibéré : **aujourd'hui, rien ne fait passer un GP en `cotes_figees`**
# (le CLAUDE.md le note en « Reste à faire »). Ne surveiller que ce statut
# rendrait le job inopérant en pratique. Une course dont l'heure de départ est
# passée de 1h30 est terminée, que ses cotes aient été figées ou non.
STATUTS_SURVEILLES = ("a_venir", "cotes_figees")

# GP pour lesquels l'alerte de fenêtre dépassée a déjà été émise. En mémoire :
# une alerte de plus après un redéploiement est sans gravité, alors qu'une
# colonne de plus en base pour cela ne se justifie pas. Sans ce garde-fou,
# l'alerte se répéterait toutes les cinq minutes indéfiniment.
_alertes_emises: set[str] = set()


def _en_datetime(brut: object) -> datetime | None:
    if not isinstance(brut, str) or not brut.strip():
        return None
    try:
        lue = datetime.fromisoformat(brut.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return lue.replace(tzinfo=UTC) if lue.tzinfo is None else lue.astimezone(UTC)


async def _resultats_en_base(gp_id: str) -> dict | None:
    """Le JSON OpenF1 déjà conservé pour ce GP, s'il existe."""
    lignes = await selectionner(
        "resultats_gp",
        {"gp_id": f"eq.{gp_id}", "select": "donnees_brutes", "limit": "1"},
    )
    return lignes[0]["donnees_brutes"] if lignes else None


async def _pronostics_a_noter(gp_id: str) -> list[dict]:
    """Les pronostics de ce GP qui n'ont pas encore de points.

    Le filtre `points_gagnes=is.null` fait le gros du travail d'idempotence
    **avant** l'appel à la base : un GP déjà entièrement noté ne remonte aucune
    ligne, et le calcul ne tourne même pas.
    """
    return await selectionner(
        "pronostics",
        {
            "gp_id": f"eq.{gp_id}",
            "points_gagnes": "is.null",
            "select": "id,profil_id,type,id_outcome_unibet,pronostic_podium(pilote_1,pilote_2)",
        },
    )


async def cotes_du_gp(gp_id: str) -> dict[str, dict]:
    """Les cotes figées du GP, indexées par identifiant d'issue.

    Ce sont elles qui portent les points : jamais une cote recalculée, toujours
    celle qui était affichée au joueur au moment de sa saisie (règle 4.3).

    Publique depuis la version `0.6.1` : le banc d'essai
    (`POST /jobs/resultats/{id}/test`) doit lire exactement les mêmes cotes que
    le job, sinon il validerait le calcul sur d'autres valeurs que celles qui
    serviront le jour de la course.
    """
    lignes = await selectionner(
        "cotes",
        {
            "gp_id": f"eq.{gp_id}",
            # `*` et non les colonnes nommées : `numero_pilote` et `ecurie_id`
            # (migration 26) manquent sur une base pas encore migrée.
            "select": "*",
        },
    )
    return {ligne["id_outcome_unibet"]: ligne for ligne in lignes}


class GrandPrixDefinitif(Exception):
    """Le GP est définitif : seul `recalculer` peut encore le rejuger."""


class GrandPrixNonDefinitif(Exception):
    """`recalculer` ne rejuge qu'un GP définitif : les autres ont leur boucle."""


async def _tous_les_pronostics(gp_id: str) -> list[dict]:
    """Tous les pronostics du GP, jugés ou non : le définitif les rejuge tous."""
    return await selectionner(
        "pronostics",
        {
            "gp_id": f"eq.{gp_id}",
            "select": "id,profil_id,type,id_outcome_unibet,pronostic_podium(pilote_1,pilote_2)",
        },
    )


def _verdicts(pronostics: list[dict], attributions: list, statut_manquant: str) -> list[dict]:
    """Les entrées de `attribuer_points` / `remplacer_verdicts`, une par pronostic.

    Les pronostics que le calcul n'a pas pu juger repartent `en_attente`
    explicitement : un pronostic `non_evaluable` dont l'évaluateur vient d'être
    livré, mais dont la donnée manque encore, doit quitter ce statut.
    """
    juges = {attribution.pronostic_id for attribution in attributions}
    return [
        {
            "pronostic_id": attribution.pronostic_id,
            "points": attribution.points,
            "statut": attribution.statut,
            # Les points de chaque pilote d'un podium (migration 27). Une base
            # non migrée ignore la clé.
            **(
                {"podium": list(attribution.podium)}
                if attribution.podium is not None
                else {}
            ),
        }
        for attribution in attributions
    ] + [
        {"pronostic_id": str(p["id"]), "points": None, "statut": statut_manquant}
        for p in pronostics
        if str(p["id"]) not in juges
    ]


async def traiter(gp: dict) -> dict:
    """Le calcul **provisoire** d'un GP : résultats, points, clôture.

    La fenêtre horaire de la règle 4.3 n'est **pas** appliquée ici mais par
    l'appelant : `surveiller` la respecte, `declencher_maintenant` l'ignore. Un
    déclenchement manuel peut ainsi anticiper sur un GP dont l'heure n'est pas
    venue, ou remplir les `NULL` d'un GP provisoire — sans jamais sauter le
    moindre contrôle d'idempotence.

    Un GP **définitif** est refusé (`GrandPrixDefinitif`) : ses verdicts ne se
    touchent plus que par `recalculer`, qui réécrit tout le GP d'un bloc.
    """
    gp_id = str(gp["id"])
    nom = str(gp.get("nom") or gp_id)
    depart = _en_datetime(gp.get("date_course"))

    if gp.get("statut_resultats") == DEFINITIF:
        raise GrandPrixDefinitif(
            f"{nom} est définitif. Pour le rejuger : POST /jobs/resultats/{gp_id}/recalcul"
        )

    rapport: dict = {
        "gp": nom,
        "gp_id": gp_id,
        "statut": gp.get("statut"),
        "statut_resultats": gp.get("statut_resultats"),
    }

    if depart is None:
        # Sans heure de départ, impossible de retrouver la course chez OpenF1 :
        # le rapprochement se fait sur la date (voir `openf1.session_de_course`).
        rapport["erreur"] = "Grand Prix sans date de course : rapprochement OpenF1 impossible."
        logger.error("[resultats] %s — %s", nom, rapport["erreur"])
        return rapport

    donnees = await _resultats_en_base(gp_id)
    rapport["deja_recupere"] = donnees is not None

    if donnees is None:
        # Seul appel réseau du provisoire, et il n'a lieu qu'une fois par GP.
        donnees = await recuperer(nom, depart)
        await upserter(
            "resultats_gp",
            [{"gp_id": gp_id, "donnees_brutes": donnees}],
            "gp_id",
        )
        logger.info("[resultats] %s : résultats OpenF1 (provisoires) enregistrés.", nom)
    elif await completer_qualification(nom, donnees):
        # Les qualifications, absentes des GP récupérés avant la 0.77.0. Le
        # reste de `donnees` est réécrit tel qu'il était.
        await upserter(
            "resultats_gp",
            [{"gp_id": gp_id, "donnees_brutes": donnees}],
            "gp_id",
        )

    pronostics = await _pronostics_a_noter(gp_id)
    rapport["pronostics_a_noter"] = len(pronostics)

    if pronostics:
        cotes = await cotes_du_gp(gp_id)
        attributions, en_attente = calcul.calculer(pronostics, cotes, donnees)

        ecrit = await appeler_fonction(
            "attribuer_points",
            {
                "p_gp": gp_id,
                "p_attributions": _verdicts(pronostics, attributions, calcul.EN_ATTENTE),
            },
        )
        rapport["attribues"] = (ecrit or {}).get("attribues", 0)
        rapport["restants"] = (ecrit or {}).get("restants", 0)
        rapport["en_attente"] = en_attente
        rapport["non_evaluables"] = [
            attribution.pronostic_id
            for attribution in attributions
            if attribution.statut == calcul.NON_EVALUABLE
        ]
    else:
        rapport["attribues"] = 0
        rapport["restants"] = 0
        rapport["en_attente"] = []
        rapport["non_evaluables"] = []

    # Le GP passe à `termine` et `provisoire` même s'il reste des pronostics
    # sans points : la course est courue, et laisser le GP dans la boucle ferait
    # rappeler OpenF1 toutes les cinq minutes pour rien. Le définitif, à J+1,
    # rejugera de toute façon chaque pronostic.
    if gp.get("statut") != "termine" or not gp.get("statut_resultats"):
        await mettre_a_jour(
            "grands_prix",
            {"id": f"eq.{gp_id}"},
            {"statut": "termine", "statut_resultats": PROVISOIRE},
        )
        rapport["statut"] = "termine"
        rapport["statut_resultats"] = PROVISOIRE
        logger.info(
            "[resultats] %s : statut passé à « termine », résultats provisoires. "
            "Calcul définitif prévu %s après le départ.",
            nom,
            DELAI_DEFINITIF,
        )

    if rapport["restants"]:
        logger.warning(
            "[resultats] %s : %d pronostic(s) restent sans points. Le calcul "
            "définitif les rejugera.",
            nom,
            rapport["restants"],
        )

    _alertes_emises.discard(gp_id)
    return rapport


async def consolider(gp: dict, relire: bool = True) -> dict:
    """Le calcul **définitif** : relecture d'OpenF1, puis réécriture de tout le GP.

    `relire=False` rejuge sur le `donnees_brutes` conservé, sans appel réseau :
    c'est le recalcul après la livraison d'un évaluateur corrigé. Dans les deux
    cas, **tous** les pronostics du GP sont rejugés, y compris ceux qui ont déjà
    un verdict, et `remplacer_verdicts` écrit résultats, verdicts, podiums et
    statut dans une seule transaction : un échec laisse le GP tel qu'il était,
    jamais à moitié réécrit.
    """
    gp_id = str(gp["id"])
    nom = str(gp.get("nom") or gp_id)
    depart = _en_datetime(gp.get("date_course"))

    rapport: dict = {"gp": nom, "gp_id": gp_id, "statut": gp.get("statut")}

    ancien = await _resultats_en_base(gp_id)

    if relire:
        if depart is None:
            rapport["erreur"] = "Grand Prix sans date de course : rapprochement OpenF1 impossible."
            logger.error("[resultats] %s — %s", nom, rapport["erreur"])
            return rapport
        donnees = await recuperer(nom, depart)
        # Les qualifications ne changent pas après la course : si OpenF1 ne les
        # rend pas cette fois-ci, celles déjà conservées font foi.
        if not donnees.get("qualification") and (ancien or {}).get("qualification"):
            donnees["qualification"] = ancien["qualification"]
    else:
        if ancien is None:
            raise ValueError(f"{nom} n'a aucun résultat en base à rejuger.")
        donnees = ancien

    rapport["deja_recupere"] = ancien is not None

    pronostics = await _tous_les_pronostics(gp_id)
    rapport["pronostics_a_noter"] = len(pronostics)

    cotes = await cotes_du_gp(gp_id) if pronostics else {}
    attributions, en_attente = calcul.calculer(pronostics, cotes, donnees)

    ecrit = await appeler_fonction(
        "remplacer_verdicts",
        {
            "p_gp": gp_id,
            "p_attributions": _verdicts(pronostics, attributions, calcul.EN_ATTENTE),
            # `None` : le JSON en base est gardé tel quel.
            "p_donnees": donnees if relire else None,
            "p_statut_resultats": DEFINITIF,
        },
    )

    await _effacer_alerte_definitif(gp_id, nom)

    rapport["statut"] = "termine"
    rapport["statut_resultats"] = DEFINITIF
    rapport["modifies"] = (ecrit or {}).get("modifies", 0)
    rapport["attribues"] = (ecrit or {}).get("attribues", 0)
    rapport["restants"] = (ecrit or {}).get("restants", 0)
    rapport["en_attente"] = en_attente
    rapport["non_evaluables"] = [
        attribution.pronostic_id
        for attribution in attributions
        if attribution.statut == calcul.NON_EVALUABLE
    ]

    logger.info(
        "[resultats] %s : résultats DÉFINITIFS%s — %d verdict(s) modifié(s) sur %d "
        "pronostic(s), %d en attente.",
        nom,
        " (OpenF1 relue)" if relire else " (données conservées)",
        rapport["modifies"],
        len(pronostics),
        rapport["restants"],
    )
    return rapport


async def _noter_echec_definitif(gp_id: str, nom: str, erreur: BaseException) -> None:
    """Compte un échec du définitif en base, et alerte au seuil.

    **Le compteur vit en base, pas en mémoire** : c'est lui que le profil admin
    lit, et un redéploiement de Railway ne doit pas le remettre à zéro. Son
    écriture est best effort — sans la migration 26, seul le journal en garde
    trace, et la boucle continue.
    """
    message = str(erreur) or type(erreur).__name__
    try:
        tentatives = await appeler_fonction(
            "noter_echec_definitif", {"p_gp": gp_id, "p_erreur": message}
        )
    except ErreurSupabase:
        logger.exception("[resultats] %s : échec du définitif non compté.", nom)
        return
    if isinstance(tentatives, int) and tentatives >= SEUIL_ALERTE_DEFINITIF:
        logger.error(
            "[resultats] ALERTE — %s : calcul définitif en échec %d fois de suite "
            "(dernière erreur : %s). Il continue de réessayer toutes les %s.",
            nom,
            tentatives,
            message,
            INTERVALLE_DEFINITIF,
        )


async def _effacer_alerte_definitif(gp_id: str, nom: str) -> None:
    """Un définitif réussi remet le compteur d'échecs à zéro."""
    try:
        await supprimer(
            "alertes_admin",
            {"gp_id": f"eq.{gp_id}", "type": f"eq.{DEFINITIF_EN_ECHEC}"},
        )
    except ErreurSupabase:
        logger.exception("[resultats] %s : alerte du définitif non effacée.", nom)


async def _candidats() -> list[dict]:
    """Les GP susceptibles d'être notés, les plus anciens d'abord."""
    return await selectionner(
        "grands_prix",
        {
            "statut": f"in.({','.join(STATUTS_SURVEILLES)})",
            "date_course": "not.is.null",
            "select": "id,nom,date_course,statut,statut_resultats",
            "order": "date_course.asc",
        },
    )


async def surveiller() -> None:
    """Un tour de boucle : appelée toutes les cinq minutes par le scheduler.

    La fenêtre d'essais est calculée à partir de `date_course`, sans état
    conservé nulle part : un GP est à traiter entre `départ + 1h30` et
    `départ + 1h30 + 3h`. Un compteur de tentatives en base dirait la même chose
    au prix d'une colonne et d'une écriture par essai, et se désynchroniserait
    au premier redéploiement.

    Rien ne s'échappe d'ici : la boucle du scheduler doit survivre à l'échec
    d'un GP, comme le scraper de l'étape 4 survit à l'échec de l'un des siens.
    """
    try:
        candidats = await _candidats()
    except ErreurSupabase:
        logger.exception("[resultats] Lecture des Grands Prix impossible.")
        return

    maintenant = datetime.now(UTC)

    for gp in candidats:
        gp_id = str(gp["id"])
        nom = str(gp.get("nom") or gp_id)
        depart = _en_datetime(gp.get("date_course"))
        if depart is None:
            continue

        debut = depart + DELAI_APRES_DEPART
        if maintenant < debut:
            continue  # La course n'est pas finie, ou pas depuis assez longtemps.

        if maintenant > debut + FENETRE_ESSAIS:
            if gp_id not in _alertes_emises:
                _alertes_emises.add(gp_id)
                logger.error(
                    "[resultats] ALERTE — %s : aucun résultat OpenF1 %s après le "
                    "départ prévu (%s). Les essais sont abandonnés pour ce Grand "
                    "Prix. Vérifier qu'il a bien eu lieu, puis rejouer à la main : "
                    "POST /jobs/resultats/%s",
                    nom,
                    FENETRE_ESSAIS + DELAI_APRES_DEPART,
                    depart.isoformat(),
                    gp_id,
                )
            continue

        try:
            await traiter(gp)
        except ResultatsIndisponibles as erreur:
            # État normal tant que la course n'est pas consolidée : on réessaie
            # au tour suivant, sans bruit inutile dans les logs.
            logger.info("[resultats] %s : %s Nouvel essai dans %s.", nom, erreur, INTERVALLE)
        except (ErreurOpenF1, ErreurSupabase):
            logger.exception("[resultats] %s : échec du traitement.", nom)
        except Exception:  # noqa: BLE001 — la boucle doit survivre à tout
            logger.exception("[resultats] %s : échec inattendu du traitement.", nom)


async def consolider_echus() -> None:
    """Un tour de la boucle du définitif : chaque GP provisoire dont le départ
    date de plus de 24 heures reçoit son calcul définitif.

    **C'est aussi le rattrapage au démarrage** : le premier tour part quelques
    secondes après le lancement du backend (`demarrer`). Un GP resté provisoire
    pendant une veille ou un redéploiement de Railway est donc consolidé dès le
    retour du service, sans attendre.

    Un échec (OpenF1 indisponible, classement encore vide) laisse le GP
    provisoire : ses points restent comptés, et le tour suivant réessaie.
    """
    try:
        provisoires = await selectionner(
            "grands_prix",
            {
                "statut_resultats": f"eq.{PROVISOIRE}",
                "date_course": "not.is.null",
                "select": "id,nom,date_course,statut,statut_resultats",
                "order": "date_course.asc",
            },
        )
    except ErreurSupabase:
        logger.exception("[resultats] Lecture des Grands Prix provisoires impossible.")
        return

    maintenant = datetime.now(UTC)

    for gp in provisoires:
        nom = str(gp.get("nom") or gp.get("id"))
        depart = _en_datetime(gp.get("date_course"))
        if depart is None or maintenant < depart + DELAI_DEFINITIF:
            continue

        # À J+1, un classement encore indisponible n'est plus l'état normal :
        # il compte comme un échec, au même titre qu'une panne.
        try:
            await consolider(gp)
        except ResultatsIndisponibles as erreur:
            logger.warning(
                "[resultats] %s : définitif reporté (%s). Nouvel essai dans %s.",
                nom,
                erreur,
                INTERVALLE_DEFINITIF,
            )
            await _noter_echec_definitif(str(gp["id"]), nom, erreur)
        except (ErreurOpenF1, ErreurSupabase) as erreur:
            logger.exception(
                "[resultats] %s : échec du calcul définitif. Le GP reste provisoire, "
                "nouvel essai dans %s.",
                nom,
                INTERVALLE_DEFINITIF,
            )
            await _noter_echec_definitif(str(gp["id"]), nom, erreur)
        except Exception as erreur:  # noqa: BLE001 — la boucle doit survivre à tout
            logger.exception("[resultats] %s : échec inattendu du calcul définitif.", nom)
            await _noter_echec_definitif(str(gp["id"]), nom, erreur)


async def dernier_statut_des_resultats() -> str | None:
    """Le `statut_resultats` du dernier GP couru, pour la mention « Provisoire »
    du classement d'un championnat.

    `select=*` et non la colonne nommée : sur une base pas encore migrée, la
    colonne manque, et la réponse du classement ne doit pas en échouer.
    """
    try:
        lignes = await selectionner(
            "grands_prix",
            {
                "statut": "eq.termine",
                "date_course": "not.is.null",
                "select": "*",
                "order": "date_course.desc",
                "limit": "1",
            },
        )
    except ErreurSupabase:
        logger.exception("[resultats] Lecture du dernier Grand Prix couru impossible.")
        return None
    return lignes[0].get("statut_resultats") if lignes else None


async def statuts_des_resultats() -> dict[str, str]:
    """`{gp_id: statut_resultats}` des GP qui en ont un. Même prudence que
    `dernier_statut_des_resultats` sur une base non migrée."""
    try:
        lignes = await selectionner("grands_prix", {"statut": "eq.termine", "select": "*"})
    except ErreurSupabase:
        logger.exception("[resultats] Lecture des statuts de résultats impossible.")
        return {}
    return {
        str(ligne["id"]): ligne["statut_resultats"]
        for ligne in lignes
        if ligne.get("statut_resultats")
    }


# --------------------------------------------------------------------------- #
#  Scheduler
# --------------------------------------------------------------------------- #

_scheduler = None


def demarrer() -> None:
    """Démarre la surveillance, appelée au démarrage de l'application.

    APScheduler est importé **ici** et non en tête de module : le backend doit
    continuer à démarrer si la dépendance manque, `/health` restant la seule
    chose à laquelle se raccrocher pour diagnostiquer un déploiement raté.

    Trois réglages ne sont pas des détails :

    - `max_instances=1` — un tour de boucle peut dépasser cinq minutes (appels
      OpenF1 sur plusieurs GP). Sans lui, APScheduler en lancerait un second par
      dessus, et deux tours simultanés appelleraient OpenF1 deux fois.
    - `coalesce=True` — après une veille de Railway, APScheduler voudrait
      rattraper tous les tours manqués d'un coup. Un seul suffit : l'état est
      lu en base à chaque fois, pas accumulé.
    - `misfire_grace_time` généreux — un cold start Railway (section 9) fait
      arriver un tour en retard ; le sauter n'aurait pas de sens.
    """
    global _scheduler

    if _scheduler is not None:
        return

    try:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler
    except ImportError:
        logger.error(
            "[resultats] APScheduler n'est pas installé : le job de résultats ne "
            "tournera pas automatiquement. Le déclenchement manuel "
            "(POST /jobs/resultats/{gp_id}) reste disponible."
        )
        return

    _scheduler = AsyncIOScheduler(timezone="UTC")
    _scheduler.add_job(
        surveiller,
        "interval",
        seconds=int(INTERVALLE.total_seconds()),
        id="resultats",
        max_instances=1,
        coalesce=True,
        misfire_grace_time=int(INTERVALLE.total_seconds() * 3),
        # Premier tour peu après le démarrage, pas immédiatement : le client
        # HTTP partagé vient d'être créé, et un redéploiement ne doit pas
        # déclencher une rafale d'appels OpenF1 avant même de servir sa première
        # requête.
        next_run_time=datetime.now(UTC) + timedelta(seconds=30),
    )
    # Le définitif, et son rattrapage : premier tour quelques secondes après le
    # démarrage, pour qu'un GP provisoire échu pendant une veille de Railway
    # soit consolidé aussitôt.
    _scheduler.add_job(
        consolider_echus,
        "interval",
        seconds=int(INTERVALLE_DEFINITIF.total_seconds()),
        id="resultats-definitifs",
        max_instances=1,
        coalesce=True,
        misfire_grace_time=int(INTERVALLE_DEFINITIF.total_seconds() * 2),
        next_run_time=datetime.now(UTC) + timedelta(seconds=15),
    )
    _scheduler.start()
    logger.info(
        "[resultats] Surveillance démarrée : un tour toutes les %s, statuts %s ; "
        "résultats définitifs %s après le départ, vérifiés toutes les %s.",
        INTERVALLE,
        ", ".join(STATUTS_SURVEILLES),
        DELAI_DEFINITIF,
        INTERVALLE_DEFINITIF,
    )


def arreter() -> None:
    """Arrête proprement le scheduler, pour ne rien laisser en suspens."""
    global _scheduler
    if _scheduler is None:
        return
    try:
        _scheduler.shutdown(wait=False)
    finally:
        _scheduler = None
        logger.info("[resultats] Surveillance arrêtée.")


async def _grand_prix(gp_id: str) -> dict:
    """Le GP relu en base plutôt que reçu de l'appelant : c'est la seule façon
    de garantir que ses statuts et son heure de départ sont bien ceux de la base
    au moment du traitement."""
    lignes = await selectionner(
        "grands_prix",
        {
            "id": f"eq.{gp_id}",
            "select": "id,nom,date_course,statut,statut_resultats",
            "limit": "1",
        },
    )
    if not lignes:
        raise ValueError("Ce Grand Prix n'existe pas.")
    return lignes[0]


async def declencher_maintenant(gp_id: str) -> dict:
    """Le calcul provisoire à la demande, quelle que soit l'heure. Utilisé par la
    route. Refuse un GP définitif (`GrandPrixDefinitif`)."""
    gp = await _grand_prix(gp_id)
    logger.info("[resultats] Déclenchement manuel pour %s.", gp.get("nom"))
    return await traiter(gp)


async def recalculer(gp_id: str, relire: bool = False) -> dict:
    """Recalcul **volontaire** d'un GP définitif — la route admin, rien d'autre.

    Même écriture transactionnelle que le définitif automatique. Par défaut sur
    les données conservées (évaluateur corrigé) ; `relire=True` rappelle OpenF1
    (décision tardive de la FIA). Un GP qui n'est pas encore définitif est
    refusé : sa boucle s'en charge, et le rendre définitif avant l'heure
    priverait le GP de la relecture de J+1.
    """
    gp = await _grand_prix(gp_id)
    if gp.get("statut_resultats") != DEFINITIF:
        raise GrandPrixNonDefinitif(
            f"{gp.get('nom')} n'est pas définitif (statut : "
            f"{gp.get('statut_resultats') or 'aucun résultat'}). Il le deviendra "
            f"{DELAI_DEFINITIF} après le départ."
        )
    logger.warning(
        "[resultats] RECALCUL VOLONTAIRE de %s%s : tous ses verdicts vont être réécrits.",
        gp.get("nom"),
        " avec relecture d'OpenF1" if relire else "",
    )
    return await consolider(gp, relire=relire)
