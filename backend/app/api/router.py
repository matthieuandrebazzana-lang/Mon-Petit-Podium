from fastapi import APIRouter

from app.api.routes import championnats, health, pronostics, resultats, scraper

# Routeur racine : chaque nouveau domaine (classements, profils) ajoute ici son
# propre routeur.
api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(championnats.router)
# Trois routeurs se partagent le préfixe `/grands-prix/{id}` : `scraper` porte
# `/cotes` (publique, étape 4), `pronostics` porte `/favoris` et `/pronostics`
# (protégées, étape 5), `resultats` porte `/resultats` (mixte, étape 6). Les
# chemins ne se recouvrent pas — deux handlers sur un même chemin et c'est le
# premier monté qui gagne, sans le moindre avertissement.
api_router.include_router(scraper.router)
api_router.include_router(pronostics.router)
api_router.include_router(resultats.router)
