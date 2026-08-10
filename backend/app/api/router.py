from fastapi import APIRouter

from app.api.routes import championnats, health

# Routeur racine : chaque nouveau domaine (cotes, pronostics, résultats) ajoute
# ici son propre routeur.
api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(championnats.router)
