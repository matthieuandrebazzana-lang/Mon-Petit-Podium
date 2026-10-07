from fastapi import APIRouter
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

from app.config import VERSION, get_settings

router = APIRouter(tags=["système"])


class Sante(BaseModel):
    status: str
    version: str
    environment: str


@router.get("/health", response_model=Sante)
def health() -> Sante:
    """Health check. Sert aussi de ping de réveil après une mise en veille Railway."""
    settings = get_settings()
    return Sante(
        status="ok",
        version=VERSION,
        environment=settings.environment,
    )


@router.api_route("/ping", methods=["GET", "HEAD"], response_class=PlainTextResponse)
def ping() -> str:
    """Garde le service éveillé — appelé toutes les 5 minutes par une horloge externe.

    Plus léger que `/health` : ni réglages lus, ni JSON. `HEAD` est accepté parce
    que les moniteurs de disponibilité l'emploient par défaut. Voir
    `docs/architecture.md` §9.
    """
    return "pong"
