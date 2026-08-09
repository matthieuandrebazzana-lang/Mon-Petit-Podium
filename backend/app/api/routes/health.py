from fastapi import APIRouter
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
