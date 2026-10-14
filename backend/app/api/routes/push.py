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

Les trois premières ne travaillent qu'avec l'identifiant issu du jeton vérifié.
"""

import re
from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Response, status
from pydantic import BaseModel, Field, field_validator

from app.api.deps import exiger_secret, utilisateur_courant
from app.api.journal import journaliser_echecs
from app.config import get_settings
from app.jobs import notifications
from app.supabase_client import selectionner, supprimer, upserter

router = APIRouter(prefix="/push", tags=["push"])

DOMAINE = "push"

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


class BilanTest(BaseModel):
    appareils: int = 0
    envoyees: int = 0
    echecs: int = 0
    supprimes: int = 0


def exiger_apns() -> None:
    if not get_settings().apns_configure:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="APNs n'est pas configuré (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY).",
        )


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
    exiger_secret(x_admin_secret, DOMAINE)
    exiger_apns()
    jetons = await selectionner(
        "push_tokens", {"select": "token,langue", "user_id": f"eq.{profil_id}"}
    )
    bilan = await notifications.diffuser(jetons, notifications.message_test)
    return BilanTest(appareils=len(jetons), **bilan)


class BilanTestTous(BaseModel):
    jetons: int = 0
    envoyees: int = 0
    echecs: int = 0
    supprimes: int = 0


@router.post("/test/tous", response_model=BilanTestTous)
@journaliser_echecs(DOMAINE, "Notification de test à tous les appareils")
async def tester_tous(
    x_admin_secret: str | None = Header(default=None),
) -> BilanTestTous:
    exiger_secret(x_admin_secret, DOMAINE)
    exiger_apns()
    jetons = await selectionner("push_tokens", {"select": "token,langue"})
    bilan = await notifications.diffuser(jetons, notifications.message_test)
    return BilanTestTous(jetons=len(jetons), **bilan)
