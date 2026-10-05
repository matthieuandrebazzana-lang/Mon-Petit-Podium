"""Révocation Sign in with Apple — App Store, règle 5.1.1(v).

Une app qui propose Sign in with Apple doit, à la suppression d'un compte,
révoquer le jeton que l'utilisateur lui a accordé. Aucune API côté appareil ne
le fait : Apple n'expose que `POST /auth/revoke`, qui exige un `client_secret`
signé par la clé privée du compte développeur — elle ne quitte donc jamais
Railway.

L'app iOS ne possède pas de jeton de rafraîchissement Apple (Supabase consomme
le jeton d'identité sans le garder). Elle redemande donc une autorisation au
moment de la suppression et transmet le **code d'autorisation** frais, que ce
module échange contre un jeton de rafraîchissement avant de le révoquer.
"""

from __future__ import annotations

import time

import httpx
import jwt

from app.config import get_settings

URL_APPLE = "https://appleid.apple.com"
DELAI = httpx.Timeout(15.0, connect=10.0)


class ErreurApple(Exception):
    """Échec de l'échange ou de la révocation — message technique, jamais affiché."""


def _client_secret() -> str:
    """JWT ES256 de cinq minutes, le `client_secret` qu'exigent `/auth/token` et `/auth/revoke`."""
    reglages = get_settings()
    maintenant = int(time.time())
    return jwt.encode(
        {
            "iss": reglages.apple_team_id.strip(),
            "iat": maintenant,
            "exp": maintenant + 300,
            "aud": URL_APPLE,
            "sub": reglages.apple_client_id.strip(),
        },
        reglages.apple_private_key.strip().replace("\\n", "\n"),
        algorithm="ES256",
        headers={"kid": reglages.apple_key_id.strip()},
    )


async def revoquer(code_autorisation: str) -> None:
    """Échange le code contre un jeton de rafraîchissement, puis le révoque.

    Lève ``ErreurApple`` si la configuration manque ou si Apple refuse.
    """
    reglages = get_settings()
    if not reglages.apple_configure:
        raise ErreurApple("Clé Apple non configurée (APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY).")

    secret = _client_secret()
    client_id = reglages.apple_client_id.strip()

    async with httpx.AsyncClient(timeout=DELAI) as client:
        echange = await client.post(
            f"{URL_APPLE}/auth/token",
            data={
                "client_id": client_id,
                "client_secret": secret,
                "code": code_autorisation,
                "grant_type": "authorization_code",
            },
        )
        if echange.status_code != 200:
            raise ErreurApple(f"/auth/token {echange.status_code} : {echange.text[:200]}")

        corps = echange.json()
        # Le jeton de rafraîchissement d'abord : c'est lui qui porte le
        # consentement. Le jeton d'accès n'est qu'un repli.
        jeton, indice = corps.get("refresh_token"), "refresh_token"
        if not jeton:
            jeton, indice = corps.get("access_token"), "access_token"
        if not jeton:
            raise ErreurApple("/auth/token n'a rendu aucun jeton.")

        revocation = await client.post(
            f"{URL_APPLE}/auth/revoke",
            data={
                "client_id": client_id,
                "client_secret": secret,
                "token": jeton,
                "token_type_hint": indice,
            },
        )
        if revocation.status_code != 200:
            raise ErreurApple(f"/auth/revoke {revocation.status_code} : {revocation.text[:200]}")
