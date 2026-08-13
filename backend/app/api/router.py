from fastapi import APIRouter

from app.api.routes import championnats, health, pronostics, scraper

# Routeur racine : chaque nouveau domaine (résultats, classements) ajoute ici son
# propre routeur.
api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(championnats.router)
# `scraper` porte `GET /grands-prix/{id}/cotes`, publique depuis l'étape 4 ;
# `pronostics` porte les favoris et les pronostics du même GP, tous protégés.
# Les chemins ne se recouvrent pas — deux handlers sur un même chemin et c'est
# le premier monté qui gagne, sans le moindre avertissement.
api_router.include_router(scraper.router)
api_router.include_router(pronostics.router)
