"""Job de résultats — récupération OpenF1, calcul des points, clôture du GP.

Le calendrier de la règle 4.3 : le job démarre **1h30 après le départ**, appelle
OpenF1 **toutes les cinq minutes** jusqu'à obtenir des données, puis calcule et
attribue les points. Si rien n'est disponible **trois heures** après ce
démarrage, il journalise une alerte et cesse d'essayer pour ce GP.

L'idempotence est exigée par la section 9, et elle est portée à trois étages —
chacun couvrant ce que les autres ne couvrent pas :

1. **La récupération** — `resultats_gp.gp_id` est `unique`. Si une ligne existe
   déjà, OpenF1 n'est pas rappelée : le calcul est rejoué sur le JSON conservé.
2. **L'attribution** — `public.attribuer_points` n'écrit que les pronostics dont
   `points_gagnes` est encore NULL. Même appelée dix fois avec les mêmes
   valeurs, elle n'attribue rien deux fois.
3. **La surveillance** — un GP passé à `termine` sort du champ de la boucle.

Un seul processus doit porter ce scheduler. Sur le plan gratuit de Railway, le
service tourne en un exemplaire : c'est le cas aujourd'hui. **Le jour où le
service passe à plusieurs instances, deux schedulers tourneront en parallèle** —
la base empêcherait la double attribution (étage 2), mais pas les appels OpenF1
en double. Il faudra alors un verrou (`pg_try_advisory_lock`) ou un worker
dédié.
"""

import logging
from datetime import UTC, datetime, timedelta

from app.calcul import points as calcul
from app.scraper.openf1 import ErreurOpenF1, ResultatsIndisponibles, recuperer
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    mettre_a_jour,
    selectionner,
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
            "select": "id_outcome_unibet,marche,libelle_marche,pilote,valeur",
        },
    )
    return {ligne["id_outcome_unibet"]: ligne for ligne in lignes}


async def reinitialiser_points(gp_id: str) -> int:
    """Rend à `NULL` les points de tous les pronostics d'un GP. Rend leur nombre.

    > ### On remet à `NULL`, jamais à `0` — et c'est toute la fonction
    >
    > `0` veut dire « raté » (règle 4.1), et `attribuer_points` n'écrit **que**
    > les `points_gagnes` encore `NULL` (`scraper.md` §11). Remettre `0` gèlerait
    > donc définitivement ce qu'on cherche justement à recalculer : le GP
    > ressortirait avec exactement les mêmes zéros, et plus rien ne pourrait les
    > corriger. `NULL` est le seul état depuis lequel le calcul peut reprendre.
    >
    > C'est la même asymétrie que partout ailleurs dans le module : attendre est
    > réversible, écrire ne l'est pas.

    **C'est la seule écriture du système qui défait un point acquis**, et elle
    n'existe que pour un cas : un validateur corrigé après coup, dont les
    verdicts d'avant sont faux. Elle n'est jamais appelée par le scheduler — le
    job automatique reste strictement idempotent — mais seulement par
    `POST /jobs/resultats/{gp_id}?forcer=true`, derrière le secret d'admin.

    `pronostic_podium.points_gagnes` est remis à `NULL` avec le parent. Il en
    DÉRIVE (migration `resultats_points` §5) et `attribuer_points` le resynchronise
    à la prochaine attribution — mais seulement pour les podiums qui en
    reçoivent une. Un podium qui resterait non jugé garderait sinon l'ancien
    total à côté d'un parent vide, et les deux colonnes divergeraient : ce que
    le trigger d'origine avait précisément pour but d'empêcher.
    """
    podiums = await selectionner(
        "pronostics",
        {"gp_id": f"eq.{gp_id}", "type": "eq.podium", "select": "id"},
    )
    if podiums:
        identifiants = ",".join(str(ligne["id"]) for ligne in podiums)
        await mettre_a_jour(
            "pronostic_podium",
            {"pronostic_id": f"in.({identifiants})"},
            {"points_gagnes": None},
        )

    remis = await mettre_a_jour(
        "pronostics",
        {"gp_id": f"eq.{gp_id}", "points_gagnes": "not.is.null"},
        {"points_gagnes": None},
    )
    logger.warning(
        "[resultats] RECALCUL FORCÉ : %d pronostic(s) du GP %s remis à NULL. "
        "Les points déjà acquis sont effacés et vont être recalculés.",
        len(remis),
        gp_id,
    )
    return len(remis)


async def traiter(gp: dict, forcer: bool = False) -> dict:
    """Traite un GP de bout en bout : résultats, points, clôture.

    La fenêtre horaire de la règle 4.3 n'est **pas** appliquée ici mais par
    l'appelant : `surveiller` la respecte, `declencher_maintenant` l'ignore. Un
    déclenchement manuel peut ainsi rejouer un GP ancien ou anticiper sur un GP
    dont l'heure n'est pas venue — sans jamais sauter le moindre contrôle
    d'idempotence, qui vit tout entier dans les trois étages décrits en tête de
    module.

    `forcer=True` est la **seule** exception, et elle ne vient jamais du
    scheduler : les points déjà attribués sont rendus à `NULL` avant le calcul,
    pour qu'un validateur corrigé puisse rejuger un GP que l'ancien avait mal
    jugé. OpenF1 n'est pas rappelée pour autant — `resultats_gp` est intact, et
    c'est exactement ce que `donnees_brutes` conserve pour.
    """
    gp_id = str(gp["id"])
    nom = str(gp.get("nom") or gp_id)
    depart = _en_datetime(gp.get("date_course"))

    rapport: dict = {"gp": nom, "gp_id": gp_id, "statut": gp.get("statut")}

    if depart is None:
        # Sans heure de départ, impossible de retrouver la course chez OpenF1 :
        # le rapprochement se fait sur la date (voir `openf1.session_de_course`).
        rapport["erreur"] = "Grand Prix sans date de course : rapprochement OpenF1 impossible."
        logger.error("[resultats] %s — %s", nom, rapport["erreur"])
        return rapport

    donnees = await _resultats_en_base(gp_id)
    rapport["deja_recupere"] = donnees is not None

    if donnees is None:
        # Seul appel réseau du job, et il n'a lieu qu'une fois par GP.
        donnees = await recuperer(nom, depart)
        await upserter(
            "resultats_gp",
            [{"gp_id": gp_id, "donnees_brutes": donnees}],
            "gp_id",
        )
        logger.info("[resultats] %s : résultats OpenF1 enregistrés.", nom)

    # Après la récupération, avant la lecture : les pronostics doivent être lus
    # une fois qu'ils sont revenus à NULL, sans quoi le filtre
    # `points_gagnes=is.null` de `_pronostics_a_noter` ne remonterait rien.
    rapport["reinitialises"] = await reinitialiser_points(gp_id) if forcer else 0

    pronostics = await _pronostics_a_noter(gp_id)
    rapport["pronostics_a_noter"] = len(pronostics)

    if pronostics:
        cotes = await cotes_du_gp(gp_id)
        attributions, en_attente = calcul.calculer(pronostics, cotes, donnees)

        ecrit = await appeler_fonction(
            "attribuer_points",
            {
                "p_gp": gp_id,
                "p_attributions": [
                    {"pronostic_id": attribution.pronostic_id, "points": attribution.points}
                    for attribution in attributions
                ],
            },
        )
        rapport["attribues"] = (ecrit or {}).get("attribues", 0)
        rapport["restants"] = (ecrit or {}).get("restants", 0)
        rapport["en_attente"] = en_attente
    else:
        rapport["attribues"] = 0
        rapport["restants"] = 0
        rapport["en_attente"] = []

    # Le GP passe à `termine` même s'il reste des pronostics sans points : la
    # course est courue, et laisser le GP dans la boucle ferait rappeler OpenF1
    # toutes les cinq minutes pour rien. Les pronostics restés à NULL sont
    # rattrapables par un déclenchement manuel, une fois le validateur manquant
    # écrit — c'est précisément à quoi sert `donnees_brutes`.
    if gp.get("statut") != "termine":
        await mettre_a_jour(
            "grands_prix", {"id": f"eq.{gp_id}"}, {"statut": "termine"}
        )
        rapport["statut"] = "termine"
        logger.info("[resultats] %s : statut passé à « termine ».", nom)

    if rapport["restants"]:
        logger.warning(
            "[resultats] %s : %d pronostic(s) restent sans points. "
            "Rejouer POST /jobs/resultats/%s une fois le validateur manquant écrit.",
            nom,
            rapport["restants"],
            gp_id,
        )

    _alertes_emises.discard(gp_id)
    return rapport


async def _candidats() -> list[dict]:
    """Les GP susceptibles d'être notés, les plus anciens d'abord."""
    return await selectionner(
        "grands_prix",
        {
            "statut": f"in.({','.join(STATUTS_SURVEILLES)})",
            "date_course": "not.is.null",
            "select": "id,nom,date_course,statut",
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
    _scheduler.start()
    logger.info(
        "[resultats] Surveillance démarrée : un tour toutes les %s, statuts %s.",
        INTERVALLE,
        ", ".join(STATUTS_SURVEILLES),
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


async def declencher_maintenant(gp_id: str, forcer: bool = False) -> dict:
    """Traite un GP à la demande, quelle que soit l'heure. Utilisé par la route.

    Le GP est relu en base plutôt que reçu de l'appelant : c'est la seule façon
    de garantir que le statut et l'heure de départ sont bien ceux de la base au
    moment du traitement.
    """
    lignes = await selectionner(
        "grands_prix",
        {"id": f"eq.{gp_id}", "select": "id,nom,date_course,statut", "limit": "1"},
    )
    if not lignes:
        raise ValueError("Ce Grand Prix n'existe pas.")

    logger.info(
        "[resultats] Déclenchement manuel pour %s%s.",
        lignes[0].get("nom"),
        " — RECALCUL FORCÉ" if forcer else "",
    )
    return await traiter(lignes[0], forcer=forcer)
