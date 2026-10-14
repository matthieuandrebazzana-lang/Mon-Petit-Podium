"""Widget iOS « Classement » — un jeton dédié et une route en lecture seule.

Deux routes (`decisions.md` §28) :

- `POST /widget/token` — authentifiée par la **session Supabase** de l'app, rend
  un jeton widget signé (`app/api/jeton_widget.py`) : identifiant du profil,
  30 jours, lecture seule. Aucune table ;
- `GET /widget/championnats/{id}/classement` — authentifiée **uniquement** par ce
  jeton. Vérifie que le profil est membre du championnat, puis rend le classement
  réduit à ce que dessine la vue Piste : rang, points, pseudo, avatar, livrée et
  couleurs. Rien d'autre.

Le jeton widget n'est accepté par aucune autre route : `utilisateur_courant` le
refuse avant même d'interroger Supabase. Sans `WIDGET_TOKEN_SECRET`, les deux
routes répondent `503`.
"""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel

from app.api import jeton_widget
from app.api.deps import exiger_configuration, utilisateur_courant
from app.api.journal import echec_lisible, journaliser_echecs
from app.api.routes.pronostics import exiger_membre
from app.supabase_client import ErreurSupabase, appeler_fonction

router = APIRouter(prefix="/widget", tags=["widget"])

DOMAINE = "widget"


class JetonWidget(BaseModel):
    jeton: str
    # L'app le range avec le jeton : c'est ce qui permet au widget de retrouver
    # la ligne de l'utilisateur dans le classement sans décoder le jeton.
    profil_id: UUID
    expire_le: datetime


class LigneClassementWidget(BaseModel):
    """Une ligne du classement, réduite à ce que dessine la vue Piste.

    Mêmes noms de champs et mêmes défauts que `LigneClassement`
    (`championnats.py`) : l'app décode les deux avec le même modèle `Membre`.
    """

    profil_id: UUID
    pseudo: str
    rang: int
    total_points: int
    avatar_url: str | None = None
    couleur1: str = "#800111"
    couleur2: str = "#FFFFFF"
    couleur_texte: str | None = None
    numero: int | None = None
    livree_mode: str = "perso"
    livree_ecurie: str | None = None


def utilisateur_widget(authorization: str | None = Header(default=None)) -> str:
    """L'identifiant porté par le jeton widget — le seul garde de `/widget/championnats`."""
    return jeton_widget.verifier(authorization)


@router.post("/token", response_model=JetonWidget)
@journaliser_echecs(DOMAINE, "Émission du jeton widget")
async def emettre_jeton(
    utilisateur: str = Depends(utilisateur_courant),
) -> JetonWidget:
    """Échange la session Supabase de l'app contre un jeton widget de 30 jours.

    L'identifiant vient du jeton Supabase vérifié, jamais du corps : il n'y en a
    pas.
    """
    jeton, expire = jeton_widget.emettre(utilisateur)
    return JetonWidget(jeton=jeton, profil_id=UUID(utilisateur), expire_le=expire)


@router.get(
    "/championnats/{championnat_id}/classement",
    response_model=list[LigneClassementWidget],
)
@journaliser_echecs(DOMAINE, "Classement du widget")
async def classement_widget(
    championnat_id: UUID,
    utilisateur: str = Depends(utilisateur_widget),
    _: None = Depends(exiger_configuration),
) -> list[LigneClassementWidget]:
    """Le classement d'un championnat dont le porteur du jeton est membre.

    La même fonction SQL que `GET /championnats/{id}/classement` — un second
    calcul aurait pu poser le widget à un autre rang que l'app.
    """
    await exiger_membre(championnat_id, utilisateur)

    try:
        lignes = await appeler_fonction(
            "classement_du_championnat", {"p_championnat": str(championnat_id)}
        )
    except ErreurSupabase as erreur:
        raise echec_lisible(DOMAINE, "Classement du widget", erreur) from erreur

    champs = LigneClassementWidget.model_fields.keys()
    return [
        LigneClassementWidget(**{cle: ligne[cle] for cle in champs if cle in ligne})
        for ligne in (lignes or [])
    ]
