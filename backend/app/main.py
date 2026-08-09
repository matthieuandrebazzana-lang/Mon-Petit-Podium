from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.config import VERSION, get_settings

settings = get_settings()

app = FastAPI(
    title="Mon Petit Podium — API",
    description="Pronostics Formule 1 entre amis.",
    version=VERSION,
    # La documentation interactive reste privée en production.
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)
