from fastapi import APIRouter

from app.api.routes import (
    admin,
    calendrier,
    championnats,
    health,
    profils,
    pronostics,
    push,
    resultats,
    scraper,
    widget,
)

# Routeur racine : chaque nouveau domaine ajoute ici son propre routeur.
api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(championnats.router)
# Profils (étape 8) : voiture personnalisée et statistiques. Préfixe `/profils`,
# qui ne recoupe aucun autre domaine.
api_router.include_router(profils.router)
# Trois routeurs se partagent le préfixe `/grands-prix/{id}` : `scraper` porte
# `/cotes` (publique, étape 4), `pronostics` porte `/favoris` et `/pronostics`
# (protégées, étape 5), `resultats` porte `/resultats` (mixte, étape 6). Les
# chemins ne se recouvrent pas — deux handlers sur un même chemin et c'est le
# premier monté qui gagne, sans le moindre avertissement.
api_router.include_router(scraper.router)
api_router.include_router(pronostics.router)
api_router.include_router(resultats.router)
# Administration (version `0.64.0`) : une seule route, `POST /admin/action`,
# fermée par le jeton du membre et une relecture de `is_admin` en base. Montée
# en dernier parce qu'elle importe `scraper` et `resultats` — le préfixe
# `/admin` ne recoupe aucun autre domaine.
api_router.include_router(admin.router)
# Notifications push (version backend `0.84.0`) : jetons APNs et test.
api_router.include_router(push.router)
# Calendrier léger (version backend `0.85.0`) : `GET /calendrier`, les GP de la
# saison sans leurs cotes — ce que `/scraper/cotes` servait au prix de toutes.
api_router.include_router(calendrier.router)
# Widget iOS « Classement » (version backend `0.86.0`) : jeton dédié et
# classement en lecture seule — le jeton widget n'ouvre aucune autre route.
api_router.include_router(widget.router)
