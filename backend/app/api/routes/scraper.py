"""Scraper Unibet — déclenchement, et lecture des cotes enregistrées.

Trois routes, deux régimes d'accès très différents :

- `POST /scraper/declencher` écrit en base. Elle est fermée par un secret
  partagé, transmis dans l'en-tête `X-Admin-Secret`.
- `GET /scraper/cotes` et `GET /grands-prix/{id}/cotes` ne font que lire. Elles
  sont publiques, comme les politiques RLS de la migration : les cotes ne sont
  un secret pour personne, elles sont affichées telles quelles chez le
  bookmaker, et la landing doit pouvoir annoncer le prochain GP sans session.

Les valeurs servies sont toujours des **points** (règle 4.1). Aucune cote brute
ne sort d'ici : la conversion est faite au scraping, et la base ne stocke que
des entiers. Rien à l'étage du frontend n'a à diviser par 100.
"""

import asyncio
import logging
import secrets
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Header, HTTPException, status
from pydantic import BaseModel

from app.api import journal
from app.api.deps import exiger_configuration
from app.config import get_settings
from app.scraper.unibet import scraper_en_tache_de_fond
from app.supabase_client import appeler_fonction, selectionner

router = APIRouter(tags=["scraper"])

DOMAINE = "scraper-api"

# Comme ailleurs dans le backend : sous Railway, `uvicorn.error` est le seul
# logger doté d'un handler.
logger = logging.getLogger("uvicorn.error")

# Le compte rendu du scraping n'est pas renvoyé à l'appelant — la route rend la
# main tout de suite. Les tâches lancées sont gardées ici le temps qu'elles
# vivent : sans référence forte, asyncio est en droit de ramasser une tâche en
# cours d'exécution, et le scraping s'arrêterait au milieu sans un mot.
_taches: set[asyncio.Task] = set()


class Lancement(BaseModel):
    statut: str


class CoteServie(BaseModel):
    pilote: str
    # Jamais « cote » : ce qui sort d'ici est un nombre de points (règle 4.1).
    points: int
    id: str


class MarcheServi(BaseModel):
    marche: str
    libelle: str
    cotes: list[CoteServie]


class GrandPrixServi(BaseModel):
    id: UUID
    nom: str
    date_course: datetime | None
    statut: str
    marches: list[MarcheServi]


def journaliser_echecs(contexte: str):
    """Aucune panne ne sort d'ici sans laisser de trace dans les logs.

    Le décorateur est partagé depuis l'étape 5 : voir `app/api/journal.py` pour
    le mécanisme, le rôle de `functools.wraps` — sans lui,
    `POST /scraper/declencher` perdrait son en-tête `X-Admin-Secret` et
    s'ouvrirait à tous — et le choix du `422`.
    """
    return journal.journaliser_echecs(DOMAINE, contexte)


def exiger_secret(fourni: str | None) -> None:
    """Refuse l'appel si l'en-tête `X-Admin-Secret` ne correspond pas.

    La comparaison passe par `secrets.compare_digest`, à temps constant : un
    `==` sur des chaînes s'arrête au premier caractère qui diffère, et le temps
    de réponse laisse alors deviner le secret caractère par caractère.

    Secret non configuré : la route refuse tout le monde. S'ouvrir à tous parce
    qu'aucune valeur n'est définie serait exactement le mauvais sens du défaut.
    """
    parametres = get_settings()

    if not parametres.admin_configure:
        logger.error(
            "[scraper-api] Déclenchement refusé : ADMIN_SECRET n'est pas défini "
            "sur le serveur."
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Le déclenchement du scraper n'est pas configuré (ADMIN_SECRET absent).",
        )

    if not fourni or not secrets.compare_digest(
        fourni.strip(), parametres.admin_secret.strip()
    ):
        logger.warning("[scraper-api] Déclenchement refusé : secret invalide ou absent.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Secret d'administration invalide ou absent.",
        )


@router.post(
    "/scraper/declencher",
    response_model=Lancement,
    status_code=status.HTTP_202_ACCEPTED,
)
@journaliser_echecs("Déclenchement du scraper")
async def declencher(
    x_admin_secret: str | None = Header(default=None),
) -> Lancement:
    """Lance un scraping en tâche de fond et rend la main immédiatement.

    Le scraping dure plusieurs secondes — une page par GP, plus la découverte —
    et rien n'oblige l'appelant à attendre. Le compte rendu part dans les logs
    Railway, où il est de toute façon plus utile qu'au bout d'un `curl`.

    `202` plutôt que `200` : la réponse dit que le travail est accepté, pas
    qu'il est fait.
    """
    exiger_secret(x_admin_secret)

    # Le secret d'abord, la configuration ensuite : répondre « Supabase n'est
    # pas configuré » à un appelant qui n'a pas donné le bon secret lui
    # apprendrait quelque chose sur l'état du serveur pour rien.
    #
    # Sans base, le scraping irait interroger Unibet pour ne rien pouvoir
    # écrire. Mieux vaut le dire tout de suite que le lire dans les logs après
    # coup — et éviter d'aller solliciter Unibet en pure perte.
    exiger_configuration()

    tache = asyncio.create_task(scraper_en_tache_de_fond())
    _taches.add(tache)
    tache.add_done_callback(_taches.discard)

    logger.info("[scraper-api] Scraping déclenché.")
    return Lancement(statut="lance")


async def _grands_prix_servis(filtre: dict[str, str]) -> list[GrandPrixServi]:
    """Charge des GP et leurs cotes, déjà groupées par marché.

    Le regroupement est fait par la base (`cotes_du_grand_prix`) : ramener une
    ligne par issue pour les réassembler en Python coûterait une cinquantaine
    de lignes par GP, et davantage une fois la grille définitive.
    """
    lignes = await selectionner(
        "grands_prix",
        {"select": "id,nom,date_course,statut", "order": "date_course.asc", **filtre},
    )

    servis: list[GrandPrixServi] = []
    for ligne in lignes:
        groupes = await appeler_fonction("cotes_du_grand_prix", {"p_gp": ligne["id"]})
        servis.append(
            GrandPrixServi(
                id=ligne["id"],
                nom=ligne["nom"],
                date_course=ligne.get("date_course"),
                statut=ligne["statut"],
                marches=[
                    MarcheServi(
                        marche=groupe["marche"],
                        libelle=groupe["libelle"],
                        cotes=[CoteServie(**cote) for cote in groupe["cotes"]],
                    )
                    for groupe in (groupes or [])
                ],
            )
        )
    return servis


@router.get("/scraper/cotes", response_model=list[GrandPrixServi])
@journaliser_echecs("Chargement des cotes")
async def cotes_en_base() -> list[GrandPrixServi]:
    """Toutes les cotes actuellement en base, groupées par GP puis par marché.

    Publique : c'est ce que le frontend appellera pour le tableau des cotes.
    Unibet n'expose que le GP suivant, la liste reste donc courte.
    """
    return await _grands_prix_servis({})


@router.get("/grands-prix/{grand_prix_id}/cotes", response_model=GrandPrixServi)
@journaliser_echecs("Chargement des cotes du Grand Prix")
async def cotes_du_grand_prix(grand_prix_id: UUID) -> GrandPrixServi:
    """Cotes d'un GP précis, groupées par marché. Publique elle aussi."""
    servis = await _grands_prix_servis({"id": f"eq.{grand_prix_id}", "limit": "1"})

    if not servis:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ce Grand Prix n'existe pas.",
        )

    return servis[0]
