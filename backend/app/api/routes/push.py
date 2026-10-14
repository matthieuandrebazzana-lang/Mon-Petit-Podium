"""Notifications push — enregistrement des jetons APNs (`decisions.md` §25).

Quatre routes :

- `POST /push/token` — l'app iOS enregistre le jeton de l'appareil et la langue
  de son interface. **Le jeton est la clé** : enregistré par un autre compte sur
  le même iPhone, il change de propriétaire au lieu d'être dupliqué — l'ancien
  compte ne reçoit plus rien sur un téléphone qui n'est plus le sien ;
- `DELETE /push/token` — à la déconnexion et à la suppression de compte. Avec un
  jeton, retire celui-là ; sans, retire tous ceux de l'appelant. Le filtre porte
  toujours sur `user_id` : un compte ne supprime jamais le jeton d'un autre ;
- `POST /push/test` — envoie sur-le-champ une notification de test à tous les
  appareils de l'appelant. Fermée par le jeton **et** par `X-Admin-Secret` ;
- `POST /push/test/tous` — la même, à **tous** les jetons de `push_tokens`.
  Fermée par `X-Admin-Secret` seul, sans session : elle sert au `curl` qui
  vérifie la livraison chez les testeurs TestFlight.

Les deux routes de test **répondent toujours en moins de 30 s** (`0.85.2`) :
lecture des jetons et diffusion tiennent dans `DELAI_ROUTE_TEST` (25 s, compté
dès l'entrée dans la route), la purge est bornée à part, et un envoi qu'APNs
laisse sans réponse revient comme un échec motivé dans `erreurs`. Les jetons
que le délai n'a pas laissé passer sont comptés « Non traité (délai global) ».

Les trois premières ne travaillent qu'avec l'identifiant issu du jeton vérifié.
"""

import asyncio
import logging
import re
import time
from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Response, status
from pydantic import BaseModel, Field, field_validator

from app import apns
from app.api.deps import exiger_secret, utilisateur_courant
from app.api.journal import journaliser_echecs
from app.config import get_settings
from app.jobs import notifications
from app.supabase_client import selectionner, supprimer, upserter

router = APIRouter(prefix="/push", tags=["push"])

DOMAINE = "push"

logger = logging.getLogger("uvicorn.error")

# Budget d'une route de test : lecture des jetons (5 s au plus) et diffusion
# dans 25 s, puis la purge (`notifications.DELAI_PURGE`, 3 s) = 28 s, sous les
# 30 s promis.
DELAI_LECTURE_JETONS = 5.0
DELAI_ROUTE_TEST = 25.0

# Un jeton APNs est une suite hexadécimale (64 caractères aujourd'hui, Apple se
# réserve d'allonger). Vérifié ici : il part tel quel dans l'URL d'APNs.
MOTIF_JETON = re.compile(r"^[0-9a-fA-F]{32,200}$")


class JetonPush(BaseModel):
    token: str = Field(min_length=1, max_length=200)
    langue: Literal["fr", "en"] = "fr"

    @field_validator("token")
    @classmethod
    def _hexadecimal(cls, valeur: str) -> str:
        valeur = valeur.strip()
        if not MOTIF_JETON.match(valeur):
            raise ValueError("Jeton APNs invalide.")
        return valeur.lower()


class JetonARetirer(BaseModel):
    token: str | None = None


class EchecEnvoi(BaseModel):
    jeton: str = ""
    motif: str = ""


class BilanTest(BaseModel):
    appareils: int = 0
    envoyees: int = 0
    echecs: int = 0
    supprimes: int = 0
    erreurs: list[EchecEnvoi] = []


def exiger_apns() -> None:
    """`503` explicite si APNs ne peut pas partir : clés, `APNS_ENV`, topic ou clé `.p8`."""
    try:
        apns.verifier_configuration()
    except apns.ErreurAPNs as erreur:
        logger.error("[%s] Configuration APNs inutilisable : %s", DOMAINE, erreur)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(erreur)) from None


async def _jetons(filtre: dict[str, str]) -> list[dict]:
    try:
        jetons = await asyncio.wait_for(
            selectionner("push_tokens", {"select": "token,langue", **filtre}), DELAI_LECTURE_JETONS
        )
    except TimeoutError:
        logger.error("[%s] Lecture de push_tokens : pas de réponse en %g s.", DOMAINE, DELAI_LECTURE_JETONS)
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=f"Supabase n'a pas rendu les jetons en {DELAI_LECTURE_JETONS:g} s.",
        ) from None
    logger.info("[%s] %d jeton(s) trouvé(s).", DOMAINE, len(jetons))
    return jetons


async def _diffuser_test(jetons: list[dict], debut: float) -> dict:
    """Diffuse le message de test dans ce qui reste de `DELAI_ROUTE_TEST`."""
    reste = max(DELAI_ROUTE_TEST - (time.monotonic() - debut), 0.0)
    return await notifications.diffuser(jetons, notifications.message_test, delai=reste)


@router.post("/token", status_code=status.HTTP_204_NO_CONTENT)
@journaliser_echecs(DOMAINE, "Enregistrement des notifications")
async def enregistrer_jeton(
    corps: JetonPush,
    profil_id: str = Depends(utilisateur_courant),
) -> Response:
    await upserter(
        "push_tokens",
        [
            {
                "token": corps.token,
                "user_id": profil_id,
                "plateforme": "ios",
                "langue": corps.langue,
                "mis_a_jour_le": datetime.now(UTC).isoformat(),
            }
        ],
        sur_conflit="token",
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/token", status_code=status.HTTP_204_NO_CONTENT)
@journaliser_echecs(DOMAINE, "Désactivation des notifications")
async def retirer_jeton(
    corps: JetonARetirer | None = Body(default=None),
    profil_id: str = Depends(utilisateur_courant),
) -> Response:
    filtre = {"user_id": f"eq.{profil_id}"}
    if corps and corps.token and corps.token.strip():
        filtre["token"] = f"eq.{corps.token.strip().lower()}"
    await supprimer("push_tokens", filtre)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/test", response_model=BilanTest)
@journaliser_echecs(DOMAINE, "Notification de test")
async def tester(
    x_admin_secret: str | None = Header(default=None),
    profil_id: str = Depends(utilisateur_courant),
) -> BilanTest:
    debut = time.monotonic()
    exiger_secret(x_admin_secret, DOMAINE)
    exiger_apns()
    jetons = await _jetons({"user_id": f"eq.{profil_id}"})
    bilan = await _diffuser_test(jetons, debut)
    return BilanTest(appareils=len(jetons), **bilan)


class BilanTestTous(BaseModel):
    jetons: int = 0
    envoyees: int = 0
    echecs: int = 0
    supprimes: int = 0
    erreurs: list[EchecEnvoi] = []
    duree: float = 0.0


@router.post("/test/tous", response_model=BilanTestTous)
@journaliser_echecs(DOMAINE, "Notification de test à tous les appareils")
async def tester_tous(
    x_admin_secret: str | None = Header(default=None),
) -> BilanTestTous:
    debut = time.monotonic()
    exiger_secret(x_admin_secret, DOMAINE)
    exiger_apns()
    jetons = await _jetons({})
    bilan = await _diffuser_test(jetons, debut)
    duree = round(time.monotonic() - debut, 1)
    logger.info("[%s] Test à tous les appareils : %.1f s au total.", DOMAINE, duree)
    return BilanTestTous(jetons=len(jetons), duree=duree, **bilan)
