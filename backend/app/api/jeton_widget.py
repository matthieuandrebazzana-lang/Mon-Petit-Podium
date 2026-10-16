"""Le jeton du widget iOS « Classement » (`decisions.md` §28).

Le widget n'a **jamais** la session Supabase de l'app : les jetons de
rafraîchissement Supabase sont à usage unique, et un widget qui rafraîchirait de
son côté consommerait celui de l'app — l'utilisateur serait déconnecté au
premier double rafraîchissement. L'app échange donc sa session contre ce jeton-ci
(`POST /widget/token`), et le widget ne présente que lui.

Ce qu'il est, et ce qu'il ne doit jamais devenir :

- un JWT **HS256** signé par `WIDGET_TOKEN_SECRET`, qui ne quitte pas Railway ;
- porteur de l'identifiant du profil (`sub`), d'une expiration à 30 jours et
  d'une **portée en lecture seule** — aucune table, rien à révoquer en base : un
  secret changé les invalide tous d'un coup ;
- accepté par les **seules routes du widget** : `GET /widget/championnats/{id}/classement`
  et `GET /widget/pronos`.
  `utilisateur_courant` le refuse explicitement (`est_jeton_widget`) au lieu de
  compter sur Supabase pour le rejeter : un secret recopié par erreur depuis
  celui de Supabase le rendrait sinon valable partout.
"""

import logging
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import HTTPException, status

from app.config import get_settings

logger = logging.getLogger("uvicorn.error")

ALGORITHME = "HS256"
# L'audience distingue ce jeton de ceux de Supabase (`authenticated`) sans
# vérifier aucune signature — c'est ce que lit `est_jeton_widget`.
AUDIENCE = "greedf1-widget"
PORTEE = "widget:lecture"
DUREE = timedelta(days=30)

SECRET_ABSENT = (
    "Le widget n'est pas configuré sur le serveur (WIDGET_TOKEN_SECRET absente)."
)


def exiger_secret_widget() -> str:
    """Le secret de signature, ou un `503` explicite s'il n'est pas défini.

    Secret absent **ferme** les deux routes, il ne les ouvre jamais : signer avec
    une chaîne vide rendrait tout jeton forgeable.
    """
    secret = get_settings().widget_token_secret.strip()
    if not secret:
        logger.error("[widget] Appel refusé : %s", SECRET_ABSENT)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=SECRET_ABSENT
        )
    return secret


def emettre(profil_id: str, maintenant: datetime | None = None) -> tuple[str, datetime]:
    """Un jeton pour ce profil, et son expiration."""
    secret = exiger_secret_widget()
    emis = maintenant or datetime.now(UTC)
    expire = emis + DUREE
    jeton = jwt.encode(
        {
            "sub": profil_id,
            "aud": AUDIENCE,
            "scope": PORTEE,
            "iat": int(emis.timestamp()),
            "exp": int(expire.timestamp()),
        },
        secret,
        algorithm=ALGORITHME,
    )
    return jeton, expire


def _refus(message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=message,
        headers={"WWW-Authenticate": "Bearer"},
    )


def verifier(authorization: str | None) -> str:
    """L'identifiant du profil porté par un jeton widget valide, sinon `401`.

    La signature, l'audience, l'expiration et la portée sont toutes vérifiées ;
    l'algorithme est imposé (`HS256` seul) pour qu'un jeton `alg: none` ou signé
    autrement ne passe jamais.
    """
    secret = exiger_secret_widget()
    schema, _, jeton = (authorization or "").partition(" ")
    if schema.lower() != "bearer" or not jeton.strip():
        raise _refus("Jeton widget requis.")

    try:
        charge = jwt.decode(
            jeton.strip(),
            secret,
            algorithms=[ALGORITHME],
            audience=AUDIENCE,
            options={"require": ["sub", "exp", "aud", "scope"]},
        )
    except jwt.ExpiredSignatureError as erreur:
        raise _refus("Jeton widget expiré. Ouvre l'app pour le renouveler.") from erreur
    except jwt.InvalidTokenError as erreur:
        logger.warning("[widget] Jeton refusé : %s", erreur)
        raise _refus("Jeton widget invalide.") from erreur

    if charge.get("scope") != PORTEE or not str(charge.get("sub") or "").strip():
        raise _refus("Jeton widget invalide.")
    return str(charge["sub"])


def est_jeton_widget(jeton: str) -> bool:
    """Vrai si le jeton **se présente** comme un jeton widget, signature non lue.

    Sert à le refuser partout ailleurs : il n'a pas à être valide pour être
    refusé, il suffit qu'il dise être ce qu'il est.
    """
    try:
        charge = jwt.decode(jeton, options={"verify_signature": False})
    except jwt.InvalidTokenError:
        return False
    audience = charge.get("aud")
    audiences = audience if isinstance(audience, list) else [audience]
    return AUDIENCE in audiences or charge.get("scope") == PORTEE
