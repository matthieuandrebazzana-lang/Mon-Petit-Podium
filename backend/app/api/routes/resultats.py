"""Résultats d'un Grand Prix — consultation et déclenchement manuel du job.

Deux routes, deux régimes d'accès, et la frontière entre les deux n'est pas un
détail :

- `GET /grands-prix/{id}/resultats` est **publique pour le classement de la
  course** — un résultat de F1 est public partout ailleurs, et l'écran doit
  pouvoir s'afficher sans session. Elle sert **en plus** les pronostics des
  membres d'un championnat, et cette partie-là exige un jeton **et**
  l'appartenance au championnat demandé.
- `POST /jobs/resultats/{id}` écrit en base. Elle est fermée par le secret
  partagé `X-Admin-Secret`, comme `POST /scraper/declencher`.

Les valeurs servies sont toujours des **points** (règle 4.1). `points_fia` fait
exception et porte son nom pour cette raison : ce sont les points du
championnat du monde (25, 18, 15…), affichés comme tels, jamais les points de
l'application.
"""

import logging
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel

from app.api.deps import (
    exiger_configuration,
    exiger_secret,
    utilisateur_optionnel,
)
from app.api.journal import journaliser_echecs
from app.api.routes.pronostics import MembrePronostics, exiger_membre
from app.jobs import resultats as job
from app.scraper.openf1 import ResultatsIndisponibles
from app.supabase_client import appeler_fonction, selectionner

router = APIRouter(tags=["resultats"])

DOMAINE = "resultats"

logger = logging.getLogger("uvicorn.error")


# --------------------------------------------------------------------------- #
#  Modèles
# --------------------------------------------------------------------------- #


class LigneClassement(BaseModel):
    """Une ligne du classement final, telle qu'OpenF1 l'a publiée."""

    # Nulle pour un abandon non classé (section 3.2). `abandon` est un champ à
    # part : un pilote peut abandonner ET rester classé.
    position: int | None = None
    driver_number: int | None = None
    pilote: str
    equipe: str | None = None
    # Points du championnat du monde FIA, jamais ceux de l'app (règle 4.1).
    points_fia: int = 0
    nombre_de_tours: int | None = None
    abandon: bool = False
    non_partant: bool = False
    disqualifie: bool = False


class GrandPrixResume(BaseModel):
    id: UUID
    nom: str
    date_course: datetime | None = None
    statut: str


class ResultatsServis(BaseModel):
    grand_prix: GrandPrixResume
    # `false` tant que le job n'a pas récupéré la course : l'écran affiche alors
    # « résultats en attente » plutôt qu'un classement vide, qui se lirait comme
    # une course où personne n'aurait fini.
    disponible: bool
    recupere_le: datetime | None = None
    classement: list[LigneClassement] = []
    # Renseigné seulement si `championnat_id` est fourni ET que l'appelant en est
    # membre. `None` veut dire « pas demandé », jamais « championnat vide ».
    membres: list[MembrePronostics] | None = None


class RapportJob(BaseModel):
    gp: str
    gp_id: UUID
    statut: str | None = None
    deja_recupere: bool = False
    pronostics_a_noter: int = 0
    attribues: int = 0
    restants: int = 0
    en_attente: list[str] = []
    erreur: str | None = None


# --------------------------------------------------------------------------- #
#  Consultation
# --------------------------------------------------------------------------- #


async def _grand_prix(gp_id: UUID) -> dict:
    lignes = await selectionner(
        "grands_prix",
        {"id": f"eq.{gp_id}", "select": "id,nom,date_course,statut", "limit": "1"},
    )
    if not lignes:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ce Grand Prix n'existe pas.",
        )
    return lignes[0]


@router.get("/grands-prix/{gp_id}/resultats", response_model=ResultatsServis)
@journaliser_echecs(DOMAINE, "Chargement des résultats du Grand Prix")
async def resultats_du_grand_prix(
    gp_id: UUID,
    championnat_id: UUID | None = None,
    utilisateur: str | None = Depends(utilisateur_optionnel),
) -> ResultatsServis:
    """Classement de la course, et au choix les pronostics d'un championnat.

    **Écart assumé par rapport à la demande**, et c'est le point important de
    cette route. Elle devait être « publique » et rendre « pour chaque membre du
    championnat ses pronostics ». Les deux ensemble sont contradictoires : la
    route ne reçoit aucun championnat par défaut, et surtout la politique RLS de
    l'étape 5 réserve la lecture des pronostics d'un joueur aux membres de ses
    championnats. Une route publique qui les servirait ouvrirait à quiconque
    devine un identifiant les pronostics de n'importe quel championnat — elle
    contournerait, depuis le backend et avec la clé de service, la protection
    même que l'étape 5 a mise en place.

    Le partage retenu :

    - **sans `championnat_id`** : le classement de la course, publiquement. Rien
      de ce qui appartient à un joueur n'en sort ;
    - **avec `championnat_id`** : jeton exigé, appartenance vérifiée, puis les
      pronostics de tous les membres avec leurs points gagnés.
    """
    gp = await _grand_prix(gp_id)

    membres = None
    if championnat_id is not None:
        # L'ordre compte : on refuse l'appelant anonyme AVANT de dire quoi que
        # ce soit du championnat demandé.
        if utilisateur is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Connecte-toi pour voir les pronostics de ce championnat.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        await exiger_membre(championnat_id, utilisateur)
        lignes = await appeler_fonction(
            "pronostics_du_championnat",
            {"p_championnat": str(championnat_id), "p_gp": str(gp_id)},
        )
        membres = [MembrePronostics(**ligne) for ligne in (lignes or [])]

    brut = await appeler_fonction("classement_du_grand_prix", {"p_gp": str(gp_id)})

    if not brut:
        # Course pas encore récupérée : la réponse est complète et honnête, avec
        # `disponible: false`. Un 404 ferait croire que le GP n'existe pas.
        return ResultatsServis(
            grand_prix=GrandPrixResume(**gp), disponible=False, membres=membres
        )

    return ResultatsServis(
        grand_prix=GrandPrixResume(**gp),
        disponible=True,
        recupere_le=brut.get("recupere_le"),
        classement=[LigneClassement(**ligne) for ligne in brut.get("classement") or []],
        membres=membres,
    )


# --------------------------------------------------------------------------- #
#  Déclenchement manuel
# --------------------------------------------------------------------------- #


@router.post("/jobs/resultats/{gp_id}", response_model=RapportJob)
@journaliser_echecs(DOMAINE, "Déclenchement du job de résultats")
async def declencher_resultats(
    gp_id: UUID,
    x_admin_secret: str | None = Header(default=None),
) -> RapportJob:
    """Traite un Grand Prix à la demande : résultats, points, clôture.

    Contrairement au scraper, la réponse est **synchrone** et porte le compte
    rendu complet. C'est la route des tests et des interventions manuelles :
    savoir combien de pronostics ont été notés, et surtout lesquels sont restés
    en attente, est tout l'intérêt de l'appel. Le traitement dure quelques
    secondes — cinq appels OpenF1 au plus, et aucun si les résultats sont déjà
    en base.

    Elle ignore la fenêtre horaire de la règle 4.3, jamais l'idempotence : un
    pronostic déjà noté ne le sera pas une seconde fois, quel que soit le nombre
    d'appels.
    """
    exiger_secret(x_admin_secret, DOMAINE)

    # Le secret d'abord, la configuration ensuite : répondre « Supabase n'est
    # pas configuré » à qui n'a pas donné le bon secret lui apprendrait quelque
    # chose sur l'état du serveur pour rien. Même ordre qu'au scraper.
    exiger_configuration()

    try:
        rapport = await job.declencher_maintenant(str(gp_id))
    except ValueError as erreur:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(erreur)
        ) from erreur
    except ResultatsIndisponibles as erreur:
        # Ce n'est pas une panne : la course n'a simplement pas encore de
        # classement publié. Un `422` la ferait passer pour un bug ; `425 Too
        # Early` dit exactement de quoi il s'agit, et invite à réessayer.
        raise HTTPException(
            status_code=status.HTTP_425_TOO_EARLY,
            detail=f"Les résultats ne sont pas encore publiés. {erreur}",
        ) from erreur

    return RapportJob(**rapport)
