from fastapi import APIRouter

from app.api.routes import championnats, health, scraper

# Routeur racine : chaque nouveau domaine (pronostics, résultats) ajoute ici son
# propre routeur.
api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(championnats.router)
api_router.include_router(scraper.router)
