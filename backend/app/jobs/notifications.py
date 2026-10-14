"""Job de notifications push — quatre événements par Grand Prix (`decisions.md` §25).

| Événement | Échéance | Texte (fr) |
|---|---|---|
| `ouverture_24h` | `date_qualifications` − 25 h | Les pronos pour [GP] ouvrent dans 24h |
| `ouverture` | `date_qualifications` − 1 h | Les pronos pour [GP] sont ouverts |
| `derniere_chance` | `date_course` − 1 h | Dernière chance de faire tes pronos pour [GP] |
| `resultats` | `statut` passé à `termine` | Les résultats du [GP] sont disponibles |

Le job tourne **toutes les cinq minutes**, et un événement daté part s'il tombe
dans les **quinze minutes** qui suivent son échéance : trois tours pour
l'attraper, de quoi couvrir un redéploiement ou une sortie de veille Railway.
Au-delà, il est perdu — une « dernière chance » reçue après le départ serait
pire que pas de notification du tout.

**Jamais deux fois.** La ligne `(gp_id, evenement)` de `notifications_envoyees`
est réservée AVANT l'envoi (`inserer_sans_doublon`) ; seul le tour qui l'a
obtenue envoie. La contrepartie est assumée : une panne d'APNs pendant ce tour
perd la notification plutôt que de risquer un doublon au tour suivant.

**La langue est celle du jeton**, enregistrée par l'app avec lui
(`push_tokens.langue`), jamais devinée ici.

Même précaution que les deux autres jobs : un seul processus doit porter ce
scheduler. À plusieurs instances, la clé primaire empêcherait quand même le
doublon — c'est elle qui tranche, pas la mémoire du processus.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from app import apns
from app.config import get_settings
from app.scraper.unibet import slug
from app.supabase_client import ErreurSupabase, inserer_sans_doublon, selectionner, supprimer

logger = logging.getLogger("uvicorn.error")

INTERVALLE = timedelta(minutes=5)

# Durée pendant laquelle un événement daté reste envoyable après son échéance.
FENETRE = timedelta(minutes=15)

# `notifications_envoyees.evenement` (migration 30), et leur décalage.
OUVERTURE_24H = "ouverture_24h"
OUVERTURE = "ouverture"
DERNIERE_CHANCE = "derniere_chance"
RESULTATS = "resultats"

EVENEMENTS_DATES = (
    (OUVERTURE_24H, "date_qualifications", timedelta(hours=25)),
    (OUVERTURE, "date_qualifications", timedelta(hours=1)),
    (DERNIERE_CHANCE, "date_course", timedelta(hours=1)),
)

# Champ des GP relus à chaque tour, autour de leur date de course : 25 h avant
# les qualifications tombe à moins de trois jours du départ, et un GP passe
# `termine` dans les heures qui suivent l'arrivée.
AVANT_COURSE = timedelta(days=3)
APRES_COURSE = timedelta(days=7)

TEXTES = {
    "fr": {
        OUVERTURE_24H: "Les pronos pour {gp} ouvrent dans 24h",
        OUVERTURE: "Les pronos pour {gp} sont ouverts",
        DERNIERE_CHANCE: "Dernière chance de faire tes pronos pour {gp}",
        RESULTATS: "Les résultats du {gp} sont disponibles",
    },
    "en": {
        OUVERTURE_24H: "Predictions for the {gp} open in 24h",
        OUVERTURE: "Predictions for the {gp} are open",
        DERNIERE_CHANCE: "Last chance to make your predictions for the {gp}",
        RESULTATS: "The {gp} results are available",
    },
}

# `POST /push/test` et `POST /push/test/tous`, dans la langue du jeton.
MESSAGES_TEST = {
    "fr": "🏎️ Test Greed F1 — les notifications fonctionnent !",
    "en": "🏎️ Greed F1 test — notifications are working!",
}


def message_test(langue: str) -> str:
    return MESSAGES_TEST.get(langue, MESSAGES_TEST["fr"])

# Nom anglais d'un GP, par le slug de son nom en base. Le français est le nom de
# la base lui-même. Un nom absent d'ici retombe sur « GP X » → « X GP ».
NOMS_ANGLAIS = {
    "pays-bas": "Dutch GP",
    "italie": "Italian GP",
    "espagne": "Spanish GP",
    "azerbaidjan": "Azerbaijan GP",
    "malaisie": "Malaysian GP",
    "bahrein": "Bahrain GP",
    "singapour": "Singapore GP",
    "etats-unis": "United States GP",
    "mexique": "Mexican GP",
    "bresil": "Brazilian GP",
    "las-vegas": "Las Vegas GP",
    "qatar": "Qatar GP",
    "abu-dhabi": "Abu Dhabi GP",
}

# Envois APNs simultanés au plus.
PARALLELISME = 20


def _en_datetime(brut: object) -> datetime | None:
    if not isinstance(brut, str) or not brut.strip():
        return None
    try:
        lue = datetime.fromisoformat(brut.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return lue.replace(tzinfo=UTC) if lue.tzinfo is None else lue.astimezone(UTC)


def nom_du_gp(nom: str, langue: str) -> str:
    nom = (nom or "").strip() or "Grand Prix"
    if langue != "en":
        return nom
    cle = slug(nom).removeprefix("gp-")
    if cle in NOMS_ANGLAIS:
        return NOMS_ANGLAIS[cle]
    return f"{nom[3:].strip()} GP" if nom.upper().startswith("GP ") else nom


def texte(evenement: str, nom_gp: str, langue: str) -> str:
    langue = langue if langue in TEXTES else "fr"
    return TEXTES[langue][evenement].format(gp=nom_du_gp(nom_gp, langue))


def evenements_dus(gp: dict, maintenant: datetime, deja: set[str]) -> list[str]:
    """Les événements de ce GP à envoyer à cet instant, hors ceux déjà envoyés.

    Calcul pur — c'est lui que testent les fenêtres de déclenchement.
    """
    if gp.get("statut") == "termine":
        return [] if RESULTATS in deja else [RESULTATS]

    dus = []
    for evenement, champ, avance in EVENEMENTS_DATES:
        if evenement in deja:
            continue
        date = _en_datetime(gp.get(champ))
        if date is None:
            continue
        echeance = date - avance
        if echeance <= maintenant < echeance + FENETRE:
            dus.append(evenement)
    return dus


async def _candidats(maintenant: datetime) -> list[dict]:
    debut = (maintenant - APRES_COURSE).strftime("%Y-%m-%dT%H:%M:%SZ")
    fin = (maintenant + AVANT_COURSE).strftime("%Y-%m-%dT%H:%M:%SZ")
    return await selectionner(
        "grands_prix",
        {
            "select": "id,nom,statut,date_qualifications,date_course",
            "and": f"(date_course.gte.{debut},date_course.lte.{fin})",
        },
    )


async def _deja_envoyes(gp_ids: list[str]) -> dict[str, set[str]]:
    if not gp_ids:
        return {}
    lignes = await selectionner(
        "notifications_envoyees",
        {"select": "gp_id,evenement", "gp_id": f"in.({','.join(gp_ids)})"},
    )
    deja: dict[str, set[str]] = {}
    for ligne in lignes:
        deja.setdefault(str(ligne["gp_id"]), set()).add(str(ligne["evenement"]))
    return deja


async def supprimer_jetons_invalides(issues: list[apns.Issue]) -> int:
    invalides = sorted({issue.token for issue in issues if issue.invalide})
    if not invalides:
        return 0
    try:
        await supprimer("push_tokens", {"token": f"in.({','.join(invalides)})"})
    except ErreurSupabase:
        logger.exception("[notifications] Suppression de %d jeton(s) invalide(s) impossible.", len(invalides))
        return 0
    logger.info("[notifications] %d jeton(s) invalide(s) supprimé(s).", len(invalides))
    return len(invalides)


async def diffuser(jetons: list[dict], message_par_langue) -> dict:
    """Envoie à chaque jeton le message de sa langue, puis purge les jetons morts.

    `message_par_langue` est une fonction `langue -> texte`. Rend le décompte
    (`envoyees`, `echecs`, `supprimes`).
    """
    verrou = asyncio.Semaphore(PARALLELISME)

    async def un(ligne: dict) -> apns.Issue:
        async with verrou:
            return await apns.envoyer(str(ligne["token"]), message_par_langue(str(ligne.get("langue") or "fr")))

    issues = await asyncio.gather(*(un(ligne) for ligne in jetons))
    for issue in issues:
        if not issue.envoyee:
            logger.warning("[notifications] Refus APNs pour …%s : %s", issue.token[-8:], issue.raison)
    return {
        "envoyees": sum(1 for issue in issues if issue.envoyee),
        "echecs": sum(1 for issue in issues if not issue.envoyee),
        "supprimes": await supprimer_jetons_invalides(list(issues)),
    }


async def surveiller(maintenant: datetime | None = None) -> None:
    """Un tour de boucle. Rien ne s'en échappe : le scheduler doit survivre."""
    maintenant = maintenant or datetime.now(UTC)
    try:
        candidats = await _candidats(maintenant)
        deja = await _deja_envoyes([str(gp["id"]) for gp in candidats])

        a_envoyer = [
            (gp, evenement)
            for gp in candidats
            for evenement in evenements_dus(gp, maintenant, deja.get(str(gp["id"]), set()))
        ]
        if not a_envoyer:
            return

        jetons = await selectionner("push_tokens", {"select": "token,langue"})
        for gp, evenement in a_envoyer:
            # La réservation tranche : seul le tour qui crée la ligne envoie.
            if not await inserer_sans_doublon(
                "notifications_envoyees", {"gp_id": gp["id"], "evenement": evenement}
            ):
                continue
            nom = str(gp.get("nom") or "")
            bilan = await diffuser(jetons, lambda langue: texte(evenement, nom, langue))
            logger.info("[notifications] %s · %s : %s", nom, evenement, bilan)
    except Exception:  # noqa: BLE001 — la boucle doit survivre à tout
        logger.exception("[notifications] Tour de surveillance en échec.")


# --------------------------------------------------------------------------- #
#  Scheduler
# --------------------------------------------------------------------------- #

_scheduler = None


def demarrer() -> None:
    """Mêmes réglages que les deux autres jobs (`jobs/scraper.py`).

    Ne démarre pas sans clé APNs : chaque tour réserverait ses événements sans
    pouvoir les envoyer, et les perdrait pour de bon.
    """
    global _scheduler
    if _scheduler is not None:
        return
    if not get_settings().apns_configure:
        logger.warning(
            "[notifications] Surveillance non démarrée : APNS_KEY_ID, APNS_TEAM_ID "
            "et APNS_KEY sont attendues."
        )
        return
    try:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler
    except ImportError:
        logger.error("[notifications] APScheduler n'est pas installé : aucune notification ne partira.")
        return

    _scheduler = AsyncIOScheduler(timezone="UTC")
    _scheduler.add_job(
        surveiller,
        "interval",
        seconds=int(INTERVALLE.total_seconds()),
        id="notifications",
        max_instances=1,
        coalesce=True,
        misfire_grace_time=int(INTERVALLE.total_seconds() * 3),
        # Entre le job de résultats (30 s) et le scraper (2 min).
        next_run_time=datetime.now(UTC) + timedelta(seconds=75),
    )
    _scheduler.start()
    logger.info(
        "[notifications] Surveillance démarrée : un tour toutes les %s, fenêtre de %s (%s).",
        INTERVALLE,
        FENETRE,
        get_settings().apns_env,
    )


def arreter() -> None:
    global _scheduler
    if _scheduler is None:
        return
    try:
        _scheduler.shutdown(wait=False)
    finally:
        _scheduler = None
        logger.info("[notifications] Surveillance arrêtée.")
