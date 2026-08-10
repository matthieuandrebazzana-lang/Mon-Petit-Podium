"""Dépendances communes aux routes protégées."""

from fastapi import Depends, Header, HTTPException, status

from app.config import get_settings
from app.supabase_client import ErreurSupabase, identifiant_du_jeton

SERVICE_INDISPONIBLE = (
    "Le serveur n'est pas relié à sa base de données. "
    "Les variables SUPABASE_URL, SUPABASE_ANON_KEY et "
    "SUPABASE_SERVICE_ROLE_KEY sont absentes."
)


def exiger_configuration() -> None:
    """Sans clés Supabase, mieux vaut un message explicite qu'une erreur 500."""
    if not get_settings().supabase_configure:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=SERVICE_INDISPONIBLE,
        )


async def utilisateur_courant(
    authorization: str | None = Header(default=None),
    _: None = Depends(exiger_configuration),
) -> str:
    """Identifiant Supabase de l'appelant, extrait de l'en-tête Authorization.

    Le jeton n'est jamais cru sur parole : il est présenté à Supabase, qui seul
    peut dire s'il est valide et à qui il appartient. Toute route qui dépend de
    cette fonction est donc fermée aux appels anonymes.
    """
    schema, _, jeton = (authorization or "").partition(" ")

    if schema.lower() != "bearer" or not jeton.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentification requise.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        identifiant = await identifiant_du_jeton(jeton.strip())
    except ErreurSupabase as erreur:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=erreur.message
        ) from erreur

    if not identifiant:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expirée. Reconnecte-toi.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return identifiant
