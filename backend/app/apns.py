"""Envoi des notifications push iOS par APNs (`docs/decisions.md` §25).

Les notifications partent toutes d'ici : l'app iOS n'en programme aucune
localement, elle se contente d'enregistrer son jeton d'appareil
(`POST /push/token`). Deux contraintes d'Apple façonnent ce module :

- **HTTP/2 uniquement.** APNs refuse le HTTP/1.1 ; le client httpx est donc
  ouvert avec `http2=True`, ce qui exige le paquet `h2` (`httpx[http2]`).
- **Un jeton de fournisseur (JWT ES256) réutilisé.** Apple le veut renouvelé
  entre 20 et 60 minutes : plus souvent, il répond `TooManyProviderTokenUpdates`
  ; moins souvent, `ExpiredProviderToken`. Il est donc gardé 50 minutes.

- **Rien n'attend sans borne** (`0.85.2`). Les délais d'httpx ne couvrent que
  la connexion, la lecture et l'écriture ; en HTTP/2, httpcore attend aussi un
  flux libre (`_max_streams_semaphore`) **sans aucun délai**. APNs n'autorise
  qu'un flux sur une connexion neuve tant que le jeton n'est pas validé : vingt
  envois parallèles s'y sont bloqués, et `POST /push/test/tous` n'a plus
  répondu. Chaque envoi est donc enrobé dans `asyncio.wait_for(DELAI_ENVOI)`,
  et un client qui a laissé expirer un envoi est jeté (`abandonner_client`) :
  sa connexion peut rester coincée pour tous les appels suivants.

Un jeton d'appareil refusé pour de bon (`410 Unregistered`, `BadDeviceToken`,
`DeviceTokenNotForTopic`) est rendu à l'appelant comme **invalide**, qui le
supprime de `push_tokens`. Toute autre erreur est passagère : le jeton reste.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass

import httpx
import jwt

from app.config import get_settings

logger = logging.getLogger("uvicorn.error")

PASSERELLES = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}

# Connexion, lecture, écriture et attente du pool : 10 s chacune.
DELAI = httpx.Timeout(10.0)

# Durée totale d'un envoi, attente d'un flux HTTP/2 comprise — celle-là, httpx
# ne la borne pas.
DELAI_ENVOI = 10.0

# Fermeture d'un client coincé : elle peut se bloquer comme lui.
DELAI_FERMETURE = 2.0

# Entre les 20 et 60 minutes qu'impose Apple.
DUREE_JETON_FOURNISSEUR = 50 * 60

# Raisons d'un `400` qui condamnent le jeton d'appareil, pas la requête.
RAISONS_JETON_INVALIDE = frozenset({"BadDeviceToken", "DeviceTokenNotForTopic"})


class ErreurAPNs(Exception):
    """Configuration absente ou inutilisable — message technique, sans secret."""


@dataclass(frozen=True)
class Issue:
    """Ce qu'APNs a répondu pour un jeton."""

    token: str
    envoyee: bool
    invalide: bool = False
    # Délai dépassé : le client qui l'a laissé faire est à jeter.
    expiree: bool = False
    raison: str = ""


_client: httpx.AsyncClient | None = None
_jeton_fournisseur: tuple[str, float] | None = None


def _client_http2() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(http2=True, timeout=DELAI)
    return _client


async def fermer_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


async def abandonner_client() -> None:
    """Jette le client après un envoi expiré : le suivant rouvrira une connexion."""
    global _client
    client, _client = _client, None
    if client is None:
        return
    logger.warning("[apns] Client HTTP/2 abandonné après un envoi expiré.")
    try:
        await asyncio.wait_for(client.aclose(), DELAI_FERMETURE)
    except Exception:  # noqa: BLE001 — l'ancien client ne doit rien bloquer
        logger.warning("[apns] Fermeture de l'ancien client incomplète.")


def passerelle() -> str:
    """URL d'APNs selon `APNS_ENV` — une valeur inconnue est une erreur, pas `sandbox`."""
    env = get_settings().apns_env.strip().lower()
    if env not in PASSERELLES:
        raise ErreurAPNs(f"APNS_ENV={env!r} inconnu : 'sandbox' ou 'production' attendu.")
    return PASSERELLES[env]


def verifier_configuration() -> None:
    """Lève `ErreurAPNs` si un envoi ne peut pas partir : clés, passerelle, topic, JWT.

    Appelé AVANT tout envoi, pour qu'une configuration cassée donne une erreur
    explicite au lieu d'un envoi en échec par jeton.
    """
    reglages = get_settings()
    if not reglages.apns_configure:
        raise ErreurAPNs("APNs non configuré (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY, APNS_BUNDLE_ID).")
    passerelle()
    try:
        _jeton()
    except Exception as erreur:  # noqa: BLE001 — clé .p8 illisible, quelle qu'en soit la forme
        # Le nom de l'exception seulement : son message pourrait citer la clé.
        raise ErreurAPNs(
            f"Jeton JWT APNs impossible à signer avec APNS_KEY ({type(erreur).__name__})."
        ) from None


def _jeton() -> str:
    """JWT ES256 signé par la clé `.p8`, réutilisé 50 minutes."""
    global _jeton_fournisseur
    maintenant = time.time()
    if _jeton_fournisseur and _jeton_fournisseur[1] > maintenant:
        return _jeton_fournisseur[0]

    reglages = get_settings()
    jeton = jwt.encode(
        {"iss": reglages.apns_team_id.strip(), "iat": int(maintenant)},
        reglages.apns_key.strip().replace("\\n", "\n"),
        algorithm="ES256",
        headers={"kid": reglages.apns_key_id.strip()},
    )
    _jeton_fournisseur = (jeton, maintenant + DUREE_JETON_FOURNISSEUR)
    return jeton


def charge_utile(corps: str, titre: str | None = None) -> dict:
    alerte: dict = {"body": corps}
    if titre:
        alerte["title"] = titre
    return {"aps": {"alert": alerte, "sound": "default"}}


def jeton_invalide(statut: int, raison: str) -> bool:
    """Vrai si APNs dit que ce jeton d'appareil ne servira plus jamais."""
    return statut == 410 or (statut == 400 and raison in RAISONS_JETON_INVALIDE)


async def envoyer(token: str, corps: str, titre: str | None = None) -> Issue:
    """Envoie une notification à un appareil, en `DELAI_ENVOI` au plus.

    Ne lève jamais pour une réponse d'APNs ni pour un délai dépassé : l'échec
    revient dans l'`Issue`, avec son motif.
    """
    global _jeton_fournisseur
    reglages = get_settings()
    if not reglages.apns_configure:
        raise ErreurAPNs("APNs non configuré (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY).")

    base = passerelle()
    court = token[-8:]
    debut = time.monotonic()
    logger.info("[apns] Envoi à …%s : début.", court)
    try:
        reponse = await asyncio.wait_for(
            _client_http2().post(
                f"{base}/3/device/{token}",
                headers={
                    "authorization": f"bearer {_jeton()}",
                    "apns-topic": reglages.apns_bundle_id.strip(),
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                },
                content=json.dumps(charge_utile(corps, titre), ensure_ascii=False).encode(),
            ),
            DELAI_ENVOI,
        )
    except TimeoutError:
        issue = Issue(token, envoyee=False, expiree=True, raison=f"Délai dépassé ({DELAI_ENVOI:g} s)")
        logger.warning("[apns] Envoi à …%s : %s.", court, issue.raison)
        return issue
    except httpx.HTTPError as erreur:
        issue = Issue(token, envoyee=False, raison=f"{type(erreur).__name__}: {erreur}")
        logger.warning("[apns] Envoi à …%s : %s (%.1f s).", court, issue.raison, time.monotonic() - debut)
        return issue

    duree = time.monotonic() - debut
    if reponse.status_code == 200:
        logger.info("[apns] Envoi à …%s : 200 (%.1f s).", court, duree)
        return Issue(token, envoyee=True)

    try:
        raison = str(reponse.json().get("reason") or "")
    except ValueError:
        raison = ""
    logger.warning("[apns] Envoi à …%s : %s %s (%.1f s).", court, reponse.status_code, raison, duree)
    if raison in ("ExpiredProviderToken", "InvalidProviderToken"):
        # Le prochain envoi signera un jeton neuf.
        _jeton_fournisseur = None
    return Issue(
        token,
        envoyee=False,
        invalide=jeton_invalide(reponse.status_code, raison),
        raison=f"{reponse.status_code} {raison}".strip(),
    )
