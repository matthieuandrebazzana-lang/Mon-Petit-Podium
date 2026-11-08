"""Job de notifications push — quatre événements par Grand Prix (`decisions.md` §25).

| Événement | Déclencheur | Texte (fr) |
|---|---|---|
| `ouverture_24h` | `date_qualifications` − 22 h, GP encore `a_venir` | Les pronos pour le [GP] ouvrent dans 24h |
| `ouverture` | `statut` passé à `cotes_figees`, cotes en base, avant le départ | Les pronos pour le [GP] sont ouverts |
| `derniere_chance` | `date_course` − 1 h, GP `cotes_figees` | Dernière chance de faire tes pronos pour le [GP] |
| `resultats` | `statut` passé à `termine` | Les résultats du [GP] sont disponibles |

**L'ouverture suit les cotes, jamais l'horloge** (backend `0.88.2`). Elle partait
à `date_qualifications` − 1 h, soit trois heures AVANT le scraping de qualifs
+ 2 h : au GP du Brésil 2026, « les pronos sont ouverts » est arrivé sur des
pronostics fermés, sans une cote en base. Elle attend désormais le statut
`cotes_figees` — que `jobs/scraper.py` ne pose qu'après au moins une cote
écrite — et revérifie qu'une cote existe avant de réserver.

Le job tourne **toutes les cinq minutes**, et un événement daté part s'il tombe
dans les **quinze minutes** qui suivent son échéance : trois tours pour
l'attraper, de quoi couvrir un redéploiement ou une sortie de veille Railway.
Au-delà, il est perdu — une « dernière chance » reçue après le départ serait
pire que pas de notification du tout. L'ouverture n'a pas de fenêtre : elle part
au premier tour qui voit les cotes, tant que la course n'est pas partie.

**Jamais deux fois.** La ligne `(gp_id, evenement)` de `notifications_envoyees`
est réservée AVANT l'envoi (`inserer_sans_doublon`) ; seul le tour qui l'a
obtenue envoie. La contrepartie est assumée : une panne d'APNs pendant ce tour
perd la notification plutôt que de risquer un doublon au tour suivant.

**La langue est celle du jeton**, enregistrée par l'app avec lui
(`push_tokens.langue`), jamais devinée ici. **Le nom du GP vient de son slug**
(`app/noms_gp.py`), tiré de sa date de course puis de son libellé, jamais du
libellé français de la base.

Même précaution que les deux autres jobs : un seul processus doit porter ce
scheduler. À plusieurs instances, la clé primaire empêcherait quand même le
doublon — c'est elle qui tranche, pas la mémoire du processus.
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import UTC, datetime, timedelta

from app import apns
from app.config import get_settings
from app.noms_gp import nom_du_gp
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

# Statuts de `grands_prix` (migration 3), et ceux de `jobs/scraper.py`.
A_VENIR = "a_venir"
COTES_FIGEES = "cotes_figees"

# (événement, champ daté, avance, statut exigé). L'ouverture prévue est qualifs
# + 2 h (`jobs/scraper.DELAI_APRES_QUALIFS`) : « dans 24h » tombe donc à
# qualifs − 22 h. Une « dernière chance » n'a de sens que sur des pronostics
# ouverts — si les cotes manquent encore à H−1, elle se tait.
EVENEMENTS_DATES = (
    (OUVERTURE_24H, "date_qualifications", timedelta(hours=22), A_VENIR),
    (DERNIERE_CHANCE, "date_course", timedelta(hours=1), COTES_FIGEES),
)

# Champ des GP relus à chaque tour, autour de leur date de course : 25 h avant
# les qualifications tombe à moins de trois jours du départ, et un GP passe
# `termine` dans les heures qui suivent l'arrivée.
AVANT_COURSE = timedelta(days=3)
APRES_COURSE = timedelta(days=7)

TEXTES = {
    "fr": {
        OUVERTURE_24H: "Les pronos pour le {gp} ouvrent dans 24h",
        OUVERTURE: "Les pronos pour le {gp} sont ouverts",
        DERNIERE_CHANCE: "Dernière chance de faire tes pronos pour le {gp}",
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

# Durée maximale d'une diffusion entière, chaque envoi étant lui-même borné à
# `apns.DELAI_ENVOI` (deux fois, avec la reprise). Les routes de test ont la leur.
DELAI_DIFFUSION = 120.0

# Motif des jetons auxquels le délai global n'a pas laissé leur tour.
NON_TRAITE = "Non traité (délai global)"

# Purge des jetons morts : un appel Supabase, borné à part.
DELAI_PURGE = 3.0


def _en_datetime(brut: object) -> datetime | None:
    if not isinstance(brut, str) or not brut.strip():
        return None
    try:
        lue = datetime.fromisoformat(brut.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return lue.replace(tzinfo=UTC) if lue.tzinfo is None else lue.astimezone(UTC)


def texte(evenement: str, nom_gp: str, langue: str, date_course: object = None) -> str:
    langue = langue if langue in TEXTES else "fr"
    return TEXTES[langue][evenement].format(gp=nom_du_gp(nom_gp, langue, date_course))


def textes(evenement: str, nom_gp: str, date_course: object = None) -> dict[str, str]:
    """Le message de cet événement dans chaque langue, calculé une fois par diffusion.

    Un GP absent de la table n'est ainsi journalisé qu'une fois par langue, et
    non une fois par jeton.
    """
    return {langue: texte(evenement, nom_gp, langue, date_course) for langue in TEXTES}


def evenements_dus(gp: dict, maintenant: datetime, deja: set[str]) -> list[str]:
    """Les événements de ce GP à envoyer à cet instant, hors ceux déjà envoyés.

    Calcul pur — c'est lui que testent les fenêtres de déclenchement.
    """
    statut = gp.get("statut")
    if statut == "termine":
        return [] if RESULTATS in deja else [RESULTATS]

    dus = []
    if statut == COTES_FIGEES and OUVERTURE not in deja:
        # Pas de fenêtre : les cotes peuvent arriver des heures après l'heure
        # prévue (`jobs/scraper.py` réessaie jusqu'au départ). Seul le départ
        # la périme — « les pronos sont ouverts » sur des pronostics fermés.
        depart = _en_datetime(gp.get("date_course"))
        if depart is None or maintenant < depart:
            dus.append(OUVERTURE)

    for evenement, champ, avance, statut_exige in EVENEMENTS_DATES:
        if evenement in deja or statut != statut_exige:
            continue
        date = _en_datetime(gp.get(champ))
        if date is None:
            continue
        echeance = date - avance
        if echeance <= maintenant < echeance + FENETRE:
            dus.append(evenement)
    return dus


async def cotes_en_base(gp_id: str) -> bool:
    """Vrai si au moins une cote de ce GP est écrite.

    Le statut `cotes_figees` le garantit déjà quand il vient du scraper ; cette
    lecture couvre un statut posé à la main dans le SQL Editor. Une seule ligne
    lue, et seulement quand une ouverture est due.
    """
    lignes = await selectionner(
        "cotes", {"gp_id": f"eq.{gp_id}", "select": "id", "limit": "1"}
    )
    return bool(lignes)


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
        await asyncio.wait_for(
            supprimer("push_tokens", {"token": f"in.({','.join(invalides)})"}), DELAI_PURGE
        )
    except (ErreurSupabase, TimeoutError):
        logger.exception("[notifications] Suppression de %d jeton(s) invalide(s) impossible.", len(invalides))
        return 0
    logger.info("[notifications] %d jeton(s) invalide(s) supprimé(s).", len(invalides))
    return len(invalides)


async def _envoyer_dans(token: str, corps: str, reste: float) -> apns.Issue:
    """Un envoi avec sa reprise, coupé s'il dépasse ce qui reste du délai global."""
    try:
        return await asyncio.wait_for(apns.envoyer_avec_reprise(token, corps), reste)
    except TimeoutError:
        # Coupé en plein vol : sa connexion n'est plus sûre.
        await apns.abandonner_client()
        return apns.Issue(token, envoyee=False, expiree=True, raison="Délai global dépassé")
    except Exception as erreur:  # noqa: BLE001 — un jeton ne doit pas arrêter les suivants
        return apns.Issue(token, envoyee=False, raison=f"{type(erreur).__name__}: {erreur}")


async def diffuser(jetons: list[dict], message_par_langue, delai: float = DELAI_DIFFUSION) -> dict:
    """Envoie à chaque jeton le message de sa langue, puis purge les jetons morts.

    `message_par_langue` est une fonction `langue -> texte`. Rend le décompte
    (`envoyees`, `echecs`, `supprimes`) et, pour chaque échec, son motif
    (`erreurs`). **Ne dure jamais plus de `delai`** (plus la purge).

    Les envois partent **un par un**, sur la connexion HTTP/2 ouverte par le
    premier (`0.85.3`) : en parallèle, APNs laissait tous les flux sauf le
    premier sans réponse. Un envoi expiré est rejoué une fois sur une connexion
    neuve. À l'échéance, l'envoi en cours est coupé et les jetons restants sont
    comptés `NON_TRAITE`.
    """
    debut = time.monotonic()
    echeance = debut + delai
    logger.info("[notifications] Diffusion à %d jeton(s), en série, %.1f s au plus.", len(jetons), delai)

    issues: list[apns.Issue] = []
    for rang, ligne in enumerate(jetons):
        reste = echeance - time.monotonic()
        if reste <= 0:
            issues += [apns.Issue(str(restant["token"]), envoyee=False, raison=NON_TRAITE) for restant in jetons[rang:]]
            break
        corps = message_par_langue(str(ligne.get("langue") or "fr"))
        issues.append(await _envoyer_dans(str(ligne["token"]), corps, reste))

    for issue in issues:
        if not issue.envoyee:
            logger.warning("[notifications] Échec pour …%s : %s", issue.token[-8:], issue.raison)
    bilan = {
        "envoyees": sum(1 for issue in issues if issue.envoyee),
        "echecs": sum(1 for issue in issues if not issue.envoyee),
        "supprimes": await supprimer_jetons_invalides(issues),
        "erreurs": [
            {"jeton": f"…{issue.token[-8:]}", "motif": issue.raison} for issue in issues if not issue.envoyee
        ],
    }
    logger.info(
        "[notifications] Diffusion terminée en %.1f s : %d envoyée(s), %d échec(s), %d supprimé(s).",
        time.monotonic() - debut,
        bilan["envoyees"],
        bilan["echecs"],
        bilan["supprimes"],
    )
    return bilan


async def notifier_admins(messages: dict[str, str]) -> dict | None:
    """Envoie une alerte aux seuls appareils des administrateurs (`profils.is_admin`).

    `messages` donne le texte par langue. Rend le bilan de `diffuser`, ou `None`
    quand rien n'a pu partir — APNs non configuré, aucun administrateur, aucun
    jeton, base illisible. **Ne lève jamais** : l'appelant est une boucle de job,
    et l'alerte en base est déjà écrite.
    """
    try:
        apns.verifier_configuration()
        admins = await selectionner("profils", {"select": "id", "is_admin": "eq.true"})
        ids = [str(ligne["id"]) for ligne in admins]
        if not ids:
            logger.warning("[notifications] Alerte admin : aucun profil administrateur.")
            return None
        jetons = await selectionner(
            "push_tokens", {"select": "token,langue", "user_id": f"in.({','.join(ids)})"}
        )
        if not jetons:
            logger.warning("[notifications] Alerte admin : aucun appareil administrateur enregistré.")
            return None
        return await diffuser(jetons, lambda langue: messages.get(langue, messages["fr"]))
    except Exception:  # noqa: BLE001 — une alerte ratée ne casse pas le job appelant
        logger.exception("[notifications] Alerte admin non envoyée.")
        return None


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

        # Avant toute réservation : une configuration cassée ne doit pas
        # consommer les événements qu'elle empêche d'envoyer.
        apns.verifier_configuration()
        jetons = await selectionner("push_tokens", {"select": "token,langue"})
        for gp, evenement in a_envoyer:
            if evenement == OUVERTURE and not await cotes_en_base(str(gp["id"])):
                logger.warning(
                    "[notifications] %s : statut « %s » mais aucune cote en base — "
                    "ouverture retenue.",
                    gp.get("nom"),
                    COTES_FIGEES,
                )
                continue
            # La réservation tranche : seul le tour qui crée la ligne envoie.
            if not await inserer_sans_doublon(
                "notifications_envoyees", {"gp_id": gp["id"], "evenement": evenement}
            ):
                continue
            nom = str(gp.get("nom") or "")
            messages = textes(evenement, nom, gp.get("date_course"))
            bilan = await diffuser(jetons, lambda langue: messages.get(langue, messages["fr"]))
            logger.info(
                "[notifications] %s · %s : %d envoyée(s), %d échec(s).",
                nom,
                evenement,
                bilan["envoyees"],
                bilan["echecs"],
            )
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
