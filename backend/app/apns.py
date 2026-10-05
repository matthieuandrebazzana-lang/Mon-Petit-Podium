"""Envoi des notifications push iOS par APNs (`docs/decisions.md` §25).

Les notifications partent toutes d'ici : l'app iOS n'en programme aucune
localement, elle se contente d'enregistrer son jeton d'appareil
(`POST /push/token`). Deux contraintes d'Apple façonnent ce module :

- **HTTP/2 uniquement.** APNs refuse le HTTP/1.1 ; le client httpx est donc
  ouvert avec `http2=True`, ce qui exige le paquet `h2` (`httpx[http2]`).
- **Un jeton de fournisseur (JWT ES256) réutilisé.** Apple le veut renouvelé
  entre 20 et 60 minutes : plus souvent, il répond `TooManyProviderTokenUpdates`
  ; moins souvent, `ExpiredProviderToken`. Il est donc gardé 50 minutes.

Un jeton d'appareil refusé pour de bon (`410 Unregistered`, `BadDeviceToken`,
`DeviceTokenNotForTopic`) est rendu à l'appelant comme **invalide**, qui le
supprime de `push_tokens`. Toute autre erreur est passagère : le jeton reste.
"""

from __future__ import annotations

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

DELAI = httpx.Timeout(15.0, connect=10.0)

# Entre les 20 et 60 minutes qu'impose Apple.
DUREE_JETON_FOURNISSEUR = 50 * 60

# Raisons d'un `400` qui condamnent le jeton d'appareil, pas la requête.
RAISONS_JETON_INVALIDE = frozenset({"BadDeviceToken", "DeviceTokenNotForTopic"})


class ErreurAPNs(Exception):
    """Configuration absente — message technique, jamais affiché."""


@dataclass(frozen=True)
class Issue:
    """Ce qu'APNs a répondu pour un jeton."""

    token: str
    envoyee: bool
    invalide: bool = False
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
    """Envoie une notification à un appareil. Ne lève jamais pour une réponse d'APNs."""
    global _jeton_fournisseur
    reglages = get_settings()
    if not reglages.apns_configure:
        raise ErreurAPNs("APNs non configuré (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY).")

    base = PASSERELLES.get(reglages.apns_env.strip().lower(), PASSERELLES["sandbox"])
    try:
        reponse = await _client_http2().post(
            f"{base}/3/device/{token}",
            headers={
                "authorization": f"bearer {_jeton()}",
                "apns-topic": reglages.apns_bundle_id.strip(),
                "apns-push-type": "alert",
                "apns-priority": "10",
            },
            content=json.dumps(charge_utile(corps, titre), ensure_ascii=False).encode(),
        )
    except httpx.HTTPError as erreur:
        return Issue(token, envoyee=False, raison=f"{type(erreur).__name__}: {erreur}")

    if reponse.status_code == 200:
        return Issue(token, envoyee=True)

    try:
        raison = str(reponse.json().get("reason") or "")
    except ValueError:
        raison = ""
    if raison in ("ExpiredProviderToken", "InvalidProviderToken"):
        # Le prochain envoi signera un jeton neuf.
        _jeton_fournisseur = None
    return Issue(
        token,
        envoyee=False,
        invalide=jeton_invalide(reponse.status_code, raison),
        raison=f"{reponse.status_code} {raison}".strip(),
    )
