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

- **Une vérification par quart d'heure.** Avant l'heure prévue, un tour ne fait
  qu'une lecture en base ; Unibet n'est sollicité que pour un GP dû. Une fois en
  retard, chaque quart d'heure gagné est du temps de pronostic rendu aux joueurs.

- **Le rattrapage court jusqu'au départ de la course** (backend `0.88.2`), et non
  plus une fenêtre fixe de quatre heures. Tant que les cotes ne sont pas en base
  le GP reste `a_venir`, et chaque tour réessaie : une page Unibet publiée en
  retard, un rattachement refusé puis corrigé à la main, une veille de Railway
  sont tous rattrapés. Seul le départ arrête — après lui, des cotes n'ouvriraient
  plus rien. Départ inconnu : `RATTRAPAGE_SANS_DEPART` après l'heure prévue.

- **Une heure après l'heure prévue sans cotes : alerte admin
  `cotes_en_retard` et notification push aux administrateurs, une fois.** La
  fenêtre de quatre heures se taisait ensuite, et le GP du Brésil 2026 n'a eu ses
  cotes que par un déclenchement manuel découvert par hasard. L'alerte s'efface
  au figeage, d'où qu'il vienne.

- **Le figeage ne suit qu'un scraping réussi.** Un échec est journalisé et le GP
  reste en `a_venir` : il sera retenté au tour suivant. Figer après un échec
  arrêterait les cotes sur ce que la base contenait avant — au pire, sur rien
  du tout.

- **Le Grand Prix visé est celui que le scraper écrit, et ce n'est plus une
  supposition.** Ce module choisit un `gp_id` en base, puis retrouve ce même
  `gp_id` dans le compte rendu du scraping pour décider quoi figer. Tant que le
  scraper insérait une seconde ligne face à une ligne posée à la main
  (`manuel-<slug>-2026`, migration 19), il rendait un **autre** UUID que celui
  visé : le compte rendu ne contenait pas le Grand Prix attendu, rien n'était
  figé, et la fenêtre de rattrapage s'épuisait sur cette erreur, semaine après
  semaine. C'est `unibet._adopter` qui referme le point, en faisant porter le
  vrai `id_unibet` à la ligne existante **sans toucher à son UUID**. Les deux
  moitiés du mécanisme tiennent ensemble : sans l'adoption, le rapprochement par
  `gp_id` de `_resultat_du_gp` ne peut pas aboutir sur un Grand Prix jamais
  adopté à la main.

Comme le job de résultats, ce module suppose **un seul processus**. Sur le plan
gratuit de Railway, le service tourne en un exemplaire. Le jour où il passe à
plusieurs instances, deux schedulers scraperaient en parallèle : la base ne
protège de rien ici, l'upsert des cotes étant idempotent mais les appels à
Unibet ne l'étant pas. Il faudra alors un `pg_try_advisory_lock` ou un worker
dédié — exactement la même note qu'en tête de `app/jobs/resultats.py`.
"""

import logging
from datetime import UTC, datetime, timedelta

from app.jobs import notifications
from app.jobs.rattachement import rattacher_sans_echec
from app.noms_gp import nom_du_gp
from app.scraper.unibet import ErreurScraper, scraper
from app.supabase_client import (
    ErreurSupabase,
    inserer_sans_doublon,
    mettre_a_jour,
    selectionner,
    supprimer,
)

logger = logging.getLogger("uvicorn.error")

# Règle 4.3 : le scraping a lieu deux heures après les qualifications.
DELAI_APRES_QUALIFS = timedelta(hours=2)

# Un tour par quart d'heure.
INTERVALLE = timedelta(minutes=15)

# Retard, compté depuis l'heure prévue (qualifs + 2 h), à partir duquel un GP
# encore sans cotes devient une alerte admin et une notification push.
DELAI_ALERTE = timedelta(hours=1)

# Fin du rattrapage quand Unibet n'a pas donné de départ : une course se court
# le lendemain des qualifications, au plus tard (26 h à Las Vegas).
RATTRAPAGE_SANS_DEPART = timedelta(hours=30)

# `alertes_admin.type` (migration 37). `cle` vide : une alerte par GP.
COTES_EN_RETARD = "cotes_en_retard"

# GP déjà signalés par ce processus, quand l'alerte n'a pas pu s'écrire en base
# (migration 37 absente) : la notification ne repart pas à chaque tour.
_signales_en_memoire: set[str] = set()

ALERTE_ADMIN = {
    "fr": "⚠️ Cotes du {gp} toujours absentes — le scraping réessaie jusqu'au départ.",
    "en": "⚠️ {gp} odds still missing — scraping keeps retrying until the race start.",
}

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

    **Il ne peut aboutir que si le scraper a écrit sur la ligne visée**, pas sur
    un doublon de sa fabrication. C'est ce que garantit `unibet._adopter`, qui
    reconnaît une ligne manuelle à sa date de course (son nom en repli) et lui
    fait porter le vrai identifiant Unibet en lui laissant son UUID. Rendre `None` reste possible et
    légitime — Unibet est passé au Grand Prix suivant, ou sa page a échoué — et
    l'appelant le journalise en `error` avec les échecs du scraping.
    """
    for ligne in rapport.get("grands_prix") or []:
        if str(ligne.get("gp_id") or "") == str(gp_id):
            return ligne
    return None


def echeances(gp: dict) -> tuple[datetime, datetime, datetime] | None:
    """`(prévu, alerte, limite)` d'un GP, ou `None` sans heure de qualifications.

    - **prévu** : qualifs + 2 h, le premier tour qui scrape ;
    - **alerte** : prévu + `DELAI_ALERTE`, l'instant où un GP encore sans cotes
      devient une alerte ;
    - **limite** : le départ de la course — au-delà, des cotes n'ouvriraient plus
      rien. Départ inconnu : prévu + `RATTRAPAGE_SANS_DEPART`.

    Calcul pur, c'est lui que testent les fenêtres du job.
    """
    qualifs = _en_datetime(gp.get("date_qualifications"))
    if qualifs is None:
        return None
    prevu = qualifs + DELAI_APRES_QUALIFS
    depart = _en_datetime(gp.get("date_course"))
    limite = depart if depart is not None else prevu + RATTRAPAGE_SANS_DEPART
    return prevu, prevu + DELAI_ALERTE, limite


async def scraper_et_figer(gp_id: str, nom: str) -> dict:
    """Scrape, puis fige le Grand Prix visé si et seulement si ça a marché.

    Le scraping n'est pas ciblé, et il ne peut pas l'être : Unibet n'expose que
    le Grand Prix suivant et ne se laisse pas interroger par identifiant
    (section 3.1). On scrape donc ce qui est disponible, et on **fige seulement
    celui qu'on visait** — les autres Grands Prix éventuellement rencontrés
    gardent leur statut, leurs propres qualifications n'ayant pas eu lieu.

    Le compte rendu porte `echec` : la raison, en clair, pour laquelle les cotes
    du GP visé ne sont toujours pas en base — `None` s'il est figé, ou s'il l'a
    été par quelqu'un d'autre entre-temps.
    """
    rapport = await scraper()
    resultat = _resultat_du_gp(rapport, gp_id)

    if resultat is None:
        # Le GP visé n'a pas été rencontré : Unibet n'a pas encore publié sa page,
        # le rattachement a été refusé, ou la page a échoué. Rien n'est figé, et
        # le tour suivant réessaiera, jusqu'au départ.
        echecs = " ; ".join(rapport.get("echecs") or []) or "aucun"
        decouverts = ", ".join(
            str(ligne.get("nom")) for ligne in rapport.get("grands_prix") or []
        ) or "aucun"
        echec = (
            f"absent du compte rendu Unibet (GP traités : {decouverts} ; échecs : {echecs})"
        )
        logger.error(
            "[scraper-job] %s : le Grand Prix n'a pas été scrapé — %s. Statut laissé "
            "à « %s », nouvel essai dans %s.",
            nom,
            echec,
            STATUT_DECLENCHEUR,
            INTERVALLE,
        )
        return {"gp": nom, "gp_id": gp_id, "fige": False, "echec": echec, "rapport": rapport}

    if resultat.get("fige"):
        # Figé par quelqu'un d'autre entre la lecture des candidats et ce
        # scraping (un déclenchement manuel) : l'état voulu, pas un échec.
        logger.info("[scraper-job] %s : déjà figé, rien à faire.", nom)
        return {"gp": nom, "gp_id": gp_id, "fige": False, "echec": None, "rapport": rapport}

    if not resultat.get("cotes"):
        echec = resultat.get("refus") or "scrapé, mais aucune cote enregistrée"
        logger.error(
            "[scraper-job] %s : %s. Statut laissé à « %s », nouvel essai dans %s.",
            nom,
            echec,
            STATUT_DECLENCHEUR,
            INTERVALLE,
        )
        return {"gp": nom, "gp_id": gp_id, "fige": False, "echec": echec, "rapport": rapport}

    fige = await figer(gp_id, nom)
    if fige:
        await _apres_figeage(gp_id, nom)
    return {
        "gp": nom,
        "gp_id": gp_id,
        "cotes": resultat["cotes"],
        "fige": fige,
        "echec": None,
        "rapport": rapport,
    }


async def _apres_figeage(gp_id: str, nom: str) -> None:
    """Ce qui suit tout figeage réussi, job horaire ou déclenchement manuel.

    Le figeage ouvre les pronostics : c'est le moment de rattacher chaque issue
    à un engagé, et de signaler celles qui n'en désignent aucun. L'alerte de
    retard, s'il y en avait une, n'a plus d'objet.
    """
    await rattacher_sans_echec(gp_id, nom)
    _signales_en_memoire.discard(gp_id)
    try:
        await supprimer(
            "alertes_admin", {"gp_id": f"eq.{gp_id}", "type": f"eq.{COTES_EN_RETARD}"}
        )
    except ErreurSupabase:
        logger.exception("[scraper-job] %s : alerte de retard non effacée.", nom)


async def signaler_retard(gp: dict, raison: str, maintenant: datetime) -> None:
    """Alerte admin `cotes_en_retard` et notification push, **une fois par GP**.

    La ligne d'alerte tient lieu de réservation, comme `notifications_envoyees`
    pour les notifications : seul le tour qui la **crée** envoie la
    notification ; les suivants ne mettent à jour que la dernière erreur. Sans
    la migration 37, la base refuse le type : seul le journal garde l'alerte, et
    un ensemble en mémoire empêche la notification de repartir à chaque tour.

    Ne lève jamais : le scraping du tour suivant ne doit pas en dépendre.
    """
    gp_id = str(gp["id"])
    nom = str(gp.get("nom") or gp_id)
    prevu, _, limite = echeances(gp) or (maintenant, None, None)
    message = (
        f"Cotes absentes {_duree(maintenant - prevu)} après l'heure prévue "
        f"({prevu.strftime('%d/%m %H:%M')} UTC). Dernier échec : {raison}. Le job réessaie toutes les "
        f"{_duree(INTERVALLE)} jusqu'au départ"
        + (f" ({limite.strftime('%d/%m %H:%M')} UTC)" if limite else "")
        + ". Déclenchement manuel : POST /scraper/declencher."
    )[:1000]
    logger.error("[scraper-job] ALERTE — %s : %s", nom, message)

    try:
        cree = await inserer_sans_doublon(
            "alertes_admin",
            {
                "gp_id": gp_id,
                "type": COTES_EN_RETARD,
                "cle": "",
                "derniere_erreur": message,
                "modifie_le": maintenant.isoformat(),
            },
            sur_conflit="gp_id,type,cle",
        )
        if not cree:
            await mettre_a_jour(
                "alertes_admin",
                {"gp_id": f"eq.{gp_id}", "type": f"eq.{COTES_EN_RETARD}"},
                {"derniere_erreur": message, "modifie_le": maintenant.isoformat()},
            )
    except ErreurSupabase:
        logger.exception(
            "[scraper-job] %s : alerte admin non enregistrée (migration 37 appliquée ?).",
            nom,
        )
        cree = gp_id not in _signales_en_memoire

    if not cree:
        return
    _signales_en_memoire.add(gp_id)
    bilan = await notifications.notifier_admins(
        {
            langue: modele.format(gp=nom_du_gp(nom, langue, gp.get("date_course")))
            for langue, modele in ALERTE_ADMIN.items()
        }
    )
    logger.info(
        "[scraper-job] %s : notification admin %s.",
        nom,
        f"envoyée à {bilan['envoyees']} appareil(s)" if bilan else "non envoyée",
    )


def _duree(ecart: timedelta) -> str:
    minutes = max(0, int(ecart.total_seconds() // 60))
    heures, minutes = divmod(minutes, 60)
    return f"{heures} h {minutes:02d}" if heures else f"{minutes} min"


async def surveiller(maintenant: datetime | None = None) -> None:
    """Un tour de boucle : appelé tous les quarts d'heure par le scheduler.

    Rien ne s'en échappe. La boucle du scheduler doit survivre à l'échec d'un
    Grand Prix, exactement comme celle du job de résultats.
    """
    try:
        candidats = await _candidats()
    except ErreurSupabase:
        logger.exception("[scraper-job] Lecture des Grands Prix impossible.")
        return

    maintenant = maintenant or datetime.now(UTC)

    for gp in candidats:
        gp_id = str(gp["id"])
        nom = str(gp.get("nom") or gp_id)
        bornes = echeances(gp)
        if bornes is None:
            continue
        prevu, alerte, limite = bornes

        if maintenant < prevu:
            continue  # Les qualifications n'ont pas eu lieu, ou pas depuis 2h.

        if maintenant >= limite:
            # La course est partie sans cotes : plus rien à ouvrir. L'alerte,
            # écrite une heure après l'heure prévue, reste au profil admin.
            continue

        logger.info(
            "[scraper-job] Déclenchement automatique pour %s — prévu à %s, soit il y "
            "a %s ; rattrapage jusqu'à %s.",
            nom,
            prevu.isoformat(),
            _duree(maintenant - prevu),
            limite.isoformat(),
        )

        try:
            echec = (await scraper_et_figer(gp_id, nom)).get("echec")
        except (ErreurScraper, ErreurSupabase) as erreur:
            logger.exception(
                "[scraper-job] %s : scraping automatique en échec. Statut laissé "
                "à « %s », nouvel essai dans %s.",
                nom,
                STATUT_DECLENCHEUR,
                INTERVALLE,
            )
            echec = f"{type(erreur).__name__} : {erreur}"
        except Exception as erreur:  # noqa: BLE001 — la boucle doit survivre à tout
            logger.exception(
                "[scraper-job] %s : échec inattendu du scraping automatique.", nom
            )
            echec = f"{type(erreur).__name__} : {erreur}"

        if echec and maintenant >= alerte:
            await signaler_retard(gp, echec, maintenant)


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
        gp_id, nom = str(ligne["gp_id"]), str(ligne.get("nom") or ligne["gp_id"])
        try:
            if await figer(gp_id, nom):
                await _apres_figeage(gp_id, nom)
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
    """Démarre la surveillance (un tour par quart d'heure), au démarrage de l'application.

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
        "déclenchement %s après les qualifications, rattrapage jusqu'au départ, "
        "alerte admin %s après l'heure prévue.",
        INTERVALLE,
        DELAI_APRES_QUALIFS,
        DELAI_ALERTE,
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
