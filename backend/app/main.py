import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import apns
from app.api.router import api_router
from app.config import VERSION, get_settings
from app.jobs import notifications as job_notifications
from app.jobs import resultats as job_resultats
from app.jobs import scraper as job_scraper
from app.supabase_client import client as client_supabase
from app.supabase_client import fermer_client

# Logger d'uvicorn : c'est le seul qui dispose d'un handler configuré sous
# Railway. Un logger maison sans handler serait silencieusement ignoré.
logger = logging.getLogger("uvicorn.error")

settings = get_settings()


@asynccontextmanager
async def cycle_de_vie(_: FastAPI):
    """Le client HTTP vers Supabase vit aussi longtemps que l'application.

    Le rouvrir à chaque requête coûterait une poignée de main TLS par appel.
    Il est créé ici, et non à la première requête : un client httpx s'attache à
    la boucle d'événements qui l'a vu naître, celle de l'application est la
    seule qui vive aussi longtemps que lui. Il est refermé proprement à l'arrêt
    pour ne pas laisser de connexion en suspens lors d'un redéploiement Railway.

    Les deux schedulers — résultats (étape 6) et scraper (étape 11) — sont
    démarrés ici pour la même raison : APScheduler en mode asyncio s'attache lui
    aussi à la boucle courante. Ils ne sont **pas** démarrés sans configuration
    Supabase — ils ne pourraient rien lire, et journaliseraient une panne à
    chaque tour en noyant les logs Railway là où un unique avertissement au
    démarrage dit déjà tout.
    """
    client_supabase()

    if settings.supabase_configure:
        job_resultats.demarrer()
        job_scraper.demarrer()
        # Ne démarre que si la clé APNs est là — il le journalise sinon.
        job_notifications.demarrer()
    else:
        logger.warning(
            "[resultats] Surveillance non démarrée : Supabase n'est pas configuré."
        )
        logger.warning(
            "[scraper-job] Surveillance non démarrée : Supabase n'est pas configuré."
        )

    yield

    job_resultats.arreter()
    job_scraper.arreter()
    job_notifications.arreter()
    await apns.fermer_client()
    await fermer_client()


app = FastAPI(
    title="Mon Petit Podium — API",
    description="Pronostics Formule 1 entre amis.",
    version=VERSION,
    lifespan=cycle_de_vie,
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

if not settings.supabase_configure:
    # Le service démarre quand même — /health doit rester joignable — mais les
    # routes métier répondront 503. Sans cette ligne, le diagnostic se ferait à
    # l'aveugle depuis le frontend.
    logger.warning(
        "Supabase n'est pas configuré : SUPABASE_URL, SUPABASE_ANON_KEY et "
        "SUPABASE_SERVICE_ROLE_KEY sont attendues. Les routes /championnats "
        "répondront 503."
    )


app.include_router(api_router)
