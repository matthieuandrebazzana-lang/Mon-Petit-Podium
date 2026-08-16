"""Job de scraping — déclenchement automatique 2h après les qualifications.

La règle 4.3 fixe le calendrier : **samedi, deux heures après les
qualifications**, les cotes sont scrapées puis **figées**. Les pénalités sont
alors confirmées et la grille est définitive, ce qui garantit que tout le monde
pronostique sur exactement les mêmes cotes.

Jusqu'à l'étape 11, ce déclenchement était manuel et *rien* ne faisait passer un
Grand Prix en `cotes_figees` : le statut existait, la protection qu'il commande
était en place et testée, mais aucun code ne l'appliquait. C'est ce module qui
referme le point.

Le mécanisme, et pourquoi il est fait ainsi :

- **Une vérification par heure**, pas toutes les cinq minutes. Le job de
  résultats court après une donnée qui paraît d'un instant à l'autre ; celui-ci
  attend une heure connue à l'avance et écrite en base. Une rafale n'apporterait
  rien et solliciterait Unibet pour rien.

- **Une fenêtre de quatre heures** après l'instant théorique, et non un
  déclenchement à l'heure pile. Sur le plan gratuit de Railway le service se met
  en veille (section 9) : s'il dort à l'instant exact, un déclenchement ponctuel
  serait manqué **définitivement**, et le Grand Prix n'aurait jamais de cotes. La
  fenêtre laisse quatre tours de boucle pour rattraper.

- **Le figeage ne suit qu'un scraping réussi.** Un échec est journalisé et le GP
  reste en `a_venir` : il sera retenté au tour suivant, tant que la fenêtre n'est
  pas passée. Figer après un échec arrêterait les cotes sur ce que la base
  contenait avant — au pire, sur rien du tout.

Comme le job de résultats, ce module suppose **un seul processus**. Sur le plan
gratuit de Railway, le service tourne en un exemplaire. Le jour où il passe à
plusieurs instances, deux schedulers scraperaient en parallèle : la base ne
protège de rien ici, l'upsert des cotes étant idempotent mais les appels à
Unibet ne l'étant pas. Il faudra alors un `pg_try_advisory_lock` ou un worker
dédié — exactement la même note qu'en tête de `app/jobs/resultats.py`.
"""

import logging
from datetime import UTC, datetime, timedelta

from app.scraper.unibet import ErreurScraper, scraper
from app.supabase_client import ErreurSupabase, mettre_a_jour, selectionner

logger = logging.getLogger("uvicorn.error")

# Règle 4.3 : le scraping a lieu deux heures après les qualifications.
DELAI_APRES_QUALIFS = timedelta(hours=2)

# Vérification horaire.
INTERVALLE = timedelta(hours=1)

# Durée pendant laquelle un Grand Prix reste éligible au déclenchement, à
# compter de l'instant théorique. Couvre une veille de Railway, un
# redéploiement, et jusqu'à trois échecs de scraping successifs.
FENETRE = timedelta(hours=4)

# Seul statut qui déclenche. Un GP déjà `cotes_figees` a eu son scraping ; un GP
# `termine` est couru. Ni l'un ni l'autre ne doit repasser ici.
STATUT_DECLENCHEUR = "a_venir"

# Statut posé après un scraping réussi. Le scraper lui-même le lit avant
# d'écrire et refuse alors d'y toucher (`unibet._enregistrer`).
STATUT_FIGE = "cotes_figees"


def _en_datetime(brut: object) -> datetime | None:
    """Lit un horodatage PostgREST et le ramène en UTC.

    Même fonction que dans `app/jobs/resultats.py`, et volontairement recopiée :
    les deux modules n'ont rien d'autre en commun, et un module utilitaire créé
    pour six lignes coûterait plus cher à suivre qu'il ne rapporte.
    """
    if not isinstance(brut, str) or not brut.strip():
        return None
    try:
        lue = datetime.fromisoformat(brut.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return lue.replace(tzinfo=UTC) if lue.tzinfo is None else lue.astimezone(UTC)


async def _candidats() -> list[dict]:
    """Les Grands Prix encore ouverts dont les qualifications sont annoncées.

    Le filtre de statut et celui de date sont posés en base — c'est l'index
    partiel `grands_prix_qualifs_a_venir_idx` de la migration 11 qui les sert.
    La fenêtre horaire, elle, est calculée en Python : elle dépend de l'instant
    présent, et la faire évaluer par PostgREST reviendrait à confier à la base
    une notion de « maintenant » dont le fuseau ne dépend pas de nous.
    """
    return await selectionner(
        "grands_prix",
        {
            "statut": f"eq.{STATUT_DECLENCHEUR}",
            "date_qualifications": "not.is.null",
            "select": "id,nom,date_qualifications,date_course,statut",
            "order": "date_qualifications.asc",
        },
    )


async def figer(gp_id: str, nom: str) -> bool:
    """Passe un Grand Prix en `cotes_figees`. À n'appeler qu'après un succès.

    Renvoie `False` si aucune ligne n'a été touchée — ce qui veut dire que le GP
    a changé de statut entre-temps (le job de résultats l'a passé à `termine`,
    ou un déclenchement manuel l'a figé une seconde plus tôt). Ce n'est pas une
    panne : c'est l'état voulu, atteint par quelqu'un d'autre.

    Le filtre porte sur le **statut autant que sur l'identifiant** : sans lui, un
    scraping tardif ramènerait un GP déjà `termine` à l'état figé, et le job de
    résultats le remettrait dans sa boucle de surveillance.
    """
    touchees = await mettre_a_jour(
        "grands_prix",
        {"id": f"eq.{gp_id}", "statut": f"eq.{STATUT_DECLENCHEUR}"},
        {"statut": STATUT_FIGE},
    )

    if not touchees:
        logger.info(
            "[scraper-job] %s : statut inchangé, le Grand Prix n'était plus « %s ».",
            nom,
            STATUT_DECLENCHEUR,
        )
        return False

    logger.info(
        "[scraper-job] %s : cotes figées (statut « %s »). "
        "Plus aucun scraping ne les modifiera (règle 4.3).",
        nom,
        STATUT_FIGE,
    )
    return True


def _resultat_du_gp(rapport: dict, gp_id: str) -> dict | None:
    """Retrouve, dans le compte rendu d'un scraping, la ligne d'un GP précis.

    Le rapprochement se fait sur `gp_id`, l'identifiant interne, jamais sur le
    nom : Unibet en change l'orthographe d'une semaine à l'autre, et c'est déjà
    la raison pour laquelle la base se rapproche sur `id_unibet`.
    """
    for ligne in rapport.get("grands_prix") or []:
        if str(ligne.get("gp_id") or "") == str(gp_id):
            return ligne
    return None


async def scraper_et_figer(gp_id: str, nom: str) -> dict:
    """Scrape, puis fige le Grand Prix visé si et seulement si ça a marché.

    Le scraping n'est pas ciblé, et il ne peut pas l'être : Unibet n'expose que
    le Grand Prix suivant et ne se laisse pas interroger par identifiant
    (section 3.1). On scrape donc ce qui est disponible, et on **fige seulement
    celui qu'on visait** — les autres Grands Prix éventuellement rencontrés
    gardent leur statut, leurs propres qualifications n'ayant pas eu lieu.
    """
    rapport = await scraper()
    resultat = _resultat_du_gp(rapport, gp_id)

    if resultat is None:
        # Le GP visé n'a pas été rencontré : Unibet est déjà passé au suivant,
        # ou la page de celui-ci a échoué. Rien n'est figé, et le tour suivant
        # réessaiera tant que la fenêtre est ouverte.
        logger.error(
            "[scraper-job] %s : le Grand Prix n'a pas été scrapé (absent du "
            "compte rendu Unibet). Statut laissé à « %s », nouvel essai dans %s. "
            "Échecs du scraping : %s",
            nom,
            STATUT_DECLENCHEUR,
            INTERVALLE,
            " ; ".join(rapport.get("echecs") or []) or "aucun",
        )
        return {"gp": nom, "gp_id": gp_id, "fige": False, "rapport": rapport}

    if not resultat.get("cotes"):
        logger.error(
            "[scraper-job] %s : scrapé mais aucune cote enregistrée. Statut laissé "
            "à « %s », nouvel essai dans %s.",
            nom,
            STATUT_DECLENCHEUR,
            INTERVALLE,
        )
        return {"gp": nom, "gp_id": gp_id, "fige": False, "rapport": rapport}

    fige = await figer(gp_id, nom)
    return {
        "gp": nom,
        "gp_id": gp_id,
        "cotes": resultat["cotes"],
        "fige": fige,
        "rapport": rapport,
    }


async def surveiller() -> None:
    """Un tour de boucle : appelé toutes les heures par le scheduler.

    Rien ne s'en échappe. La boucle du scheduler doit survivre à l'échec d'un
    Grand Prix, exactement comme celle du job de résultats.
    """
    try:
        candidats = await _candidats()
    except ErreurSupabase:
        logger.exception("[scraper-job] Lecture des Grands Prix impossible.")
        return

    maintenant = datetime.now(UTC)

    for gp in candidats:
        gp_id = str(gp["id"])
        nom = str(gp.get("nom") or gp_id)
        qualifs = _en_datetime(gp.get("date_qualifications"))
        if qualifs is None:
            continue

        debut = qualifs + DELAI_APRES_QUALIFS
        if maintenant < debut:
            continue  # Les qualifications n'ont pas eu lieu, ou pas depuis 2h.

        if maintenant > debut + FENETRE:
            # Passé la fenêtre, on n'insiste plus : la course est peut-être déjà
            # courue, et scraper des cotes périmées vaut moins que ne rien faire.
            # Aucune alerte répétée ici — le Grand Prix restera dans cette liste
            # jusqu'à ce que le job de résultats le passe à `termine`, et une
            # erreur par heure jusque-là noierait les logs. Le silence est
            # rattrapable : `POST /scraper/declencher` reste disponible.
            continue

        logger.info(
            "[scraper-job] Déclenchement automatique pour %s — qualifications à "
            "%s, soit il y a %s. Heure courante : %s.",
            nom,
            qualifs.isoformat(),
            maintenant - qualifs,
            maintenant.isoformat(),
        )

        try:
            await scraper_et_figer(gp_id, nom)
        except (ErreurScraper, ErreurSupabase):
            logger.exception(
                "[scraper-job] %s : scraping automatique en échec. Statut laissé "
                "à « %s », nouvel essai dans %s.",
                nom,
                STATUT_DECLENCHEUR,
                INTERVALLE,
            )
        except Exception:  # noqa: BLE001 — la boucle doit survivre à tout
            logger.exception(
                "[scraper-job] %s : échec inattendu du scraping automatique.", nom
            )


async def declencher_en_tache_de_fond(figer_apres: bool = True) -> None:
    """Point d'entrée du déclenchement manuel : ne laisse jamais rien fuir.

    La tâche tourne détachée de la requête qui l'a lancée. Une exception qui
    s'en échapperait ne serait signalée nulle part — asyncio la garderait pour
    la destruction de la tâche, souvent après le redéploiement suivant. Elle est
    donc attrapée et journalisée ici, avec sa trace.

    `figer_apres` reproduit le comportement du job automatique : après un
    scraping réussi, les Grands Prix effectivement scrapés passent en
    `cotes_figees`. C'est ce que demande la cohérence avec le job — un même
    scraping doit avoir le même effet, qu'il vienne d'une horloge ou d'un
    `curl`. Le passer à `false` permet de rescraper un Grand Prix **avant** ses
    qualifications sans arrêter ses cotes pour de bon : sans cette porte de
    sortie, le premier `curl` de la saison figerait des cotes de mardi, et il
    faudrait un `update` à la main dans le SQL Editor pour les débloquer.
    """
    try:
        rapport = await scraper()
    except Exception:  # noqa: BLE001 — dernier filet avant le silence complet
        logger.exception("[scraper-job] Échec complet du scraping.")
        return

    if not figer_apres:
        logger.info(
            "[scraper-job] Figeage non demandé (figer=false) : les cotes restent "
            "modifiables par un prochain scraping."
        )
        return

    for ligne in rapport.get("grands_prix") or []:
        if ligne.get("fige") or not ligne.get("cotes") or not ligne.get("gp_id"):
            # Déjà figé (le refus a été journalisé par le scraper), ou rien
            # d'écrit : dans les deux cas il n'y a pas de succès à entériner.
            continue
        try:
            await figer(str(ligne["gp_id"]), str(ligne.get("nom") or ligne["gp_id"]))
        except ErreurSupabase:
            logger.exception(
                "[scraper-job] %s : cotes enregistrées mais statut non figé.",
                ligne.get("nom"),
            )


# --------------------------------------------------------------------------- #
#  Scheduler
# --------------------------------------------------------------------------- #

_scheduler = None


def demarrer() -> None:
    """Démarre la surveillance horaire, au démarrage de l'application.

    Mêmes précautions que le scheduler de l'étape 6, et pour les mêmes raisons :

    - APScheduler est importé **ici** et non en tête de module, pour que le
      backend démarre quand même si la dépendance manque — `/health` reste alors
      la seule chose à laquelle se raccrocher pour diagnostiquer ;
    - `max_instances=1` — un scraping dure plusieurs secondes et peut, en cas de
      lenteur d'Unibet, déborder ; deux tours simultanés scraperaient deux fois ;
    - `coalesce=True` — après une veille de Railway, APScheduler voudrait
      rattraper d'un coup tous les tours manqués. Un seul suffit : l'état est lu
      en base à chaque fois, jamais accumulé ;
    - `misfire_grace_time` généreux — un cold start fait arriver un tour en
      retard, et le sauter n'aurait pas de sens.

    Le premier tour est décalé de deux minutes. Le job de résultats prend le sien
    à trente secondes : les espacer évite qu'un redéploiement ne lance de front
    un scraping Unibet et une rafale d'appels OpenF1.
    """
    global _scheduler

    if _scheduler is not None:
        return

    try:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler
    except ImportError:
        logger.error(
            "[scraper-job] APScheduler n'est pas installé : le scraping ne se "
            "déclenchera pas automatiquement. Le déclenchement manuel "
            "(POST /scraper/declencher) reste disponible."
        )
        return

    _scheduler = AsyncIOScheduler(timezone="UTC")
    _scheduler.add_job(
        surveiller,
        "interval",
        seconds=int(INTERVALLE.total_seconds()),
        id="scraper",
        max_instances=1,
        coalesce=True,
        misfire_grace_time=int(INTERVALLE.total_seconds() * 3),
        next_run_time=datetime.now(UTC) + timedelta(minutes=2),
    )
    _scheduler.start()
    logger.info(
        "[scraper-job] Surveillance démarrée : un tour toutes les %s, "
        "déclenchement %s après les qualifications, fenêtre de rattrapage de %s.",
        INTERVALLE,
        DELAI_APRES_QUALIFS,
        FENETRE,
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
        logger.info("[scraper-job] Surveillance arrêtée.")
