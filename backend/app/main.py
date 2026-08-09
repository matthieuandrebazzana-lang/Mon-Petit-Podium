import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.config import VERSION, get_settings

# Logger d'uvicorn : c'est le seul qui dispose d'un handler configuré sous
# Railway. Un logger maison sans handler serait silencieusement ignoré.
logger = logging.getLogger("uvicorn.error")

settings = get_settings()

app = FastAPI(
    title="Mon Petit Podium — API",
    description="Pronostics Formule 1 entre amis.",
    version=VERSION,
    # La documentation interactive reste privée en production.
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None,
)

# Middleware applicatif : il s'applique à TOUTES les routes, présentes et à venir,
# y compris aux préflights OPTIONS. Ne jamais gérer le CORS route par route.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Journalisé au démarrage : en cas de nouvelle erreur CORS, les logs Railway
# disent immédiatement quelles origines le service a réellement chargées.
logger.info("Origines CORS autorisées : %s", ", ".join(settings.allowed_origins))


app.include_router(api_router)
