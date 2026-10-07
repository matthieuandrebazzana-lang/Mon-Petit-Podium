"""Calendrier de la saison — la lecture légère des Grands Prix en base.

`GET /scraper/cotes` sert le même calendrier, mais avec toutes les cotes de chaque
GP : un appel à `cotes_du_grand_prix` par ligne, et plusieurs centaines de lignes
de marchés que le calendrier ne lit jamais — il ne veut savoir que **s'il en
existe**. Cette route répond à cette seule question, en **une requête** : le
comptage des cotes est embarqué dans la lecture des GP (`cotes(count)`, que
PostgREST traduit en sous-requête agrégée sur la clé étrangère `cotes.gp_id`).

Publique, comme `/scraper/cotes` : elle n'en dit pas plus, et la landing doit
pouvoir s'en servir sans session.
"""

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.api import journal
from app.api.deps import exiger_configuration
from app.supabase_client import selectionner

router = APIRouter(tags=["calendrier"])

DOMAINE = "calendrier"


class GrandPrixCalendrier(BaseModel):
    id: UUID
    nom: str
    # Nulle tant qu'Unibet n'a pas annoncé l'horaire : ce n'est pas une date passée.
    date_course: datetime | None = None
    date_qualifications: datetime | None = None
    statut: str
    # Au moins une cote en base. Défaut : une réponse incomplète perd l'information,
    # jamais la ligne (règle 3.3).
    a_des_cotes: bool = False


def _filtre_saison(saison: int) -> dict[str, str]:
    """Les GP courus dans l'année, plus ceux dont l'horaire n'est pas encore connu.

    Bornes en UTC, fin exclue. Un GP sans `date_course` n'appartient à aucune année
    connue : l'écarter le ferait disparaître du calendrier au moment précis où il
    vient d'être découvert par le scraper.
    """
    debut = f"{saison}-01-01T00:00:00Z"
    fin = f"{saison + 1}-01-01T00:00:00Z"
    return {"or": f"(date_course.is.null,and(date_course.gte.{debut},date_course.lt.{fin}))"}


def _compte(embarque) -> int:
    """`cotes(count)` revient en `[{"count": n}]` — ou en `{"count": n}` selon la
    version de PostgREST. Toute autre forme compte pour zéro."""
    if isinstance(embarque, list):
        embarque = embarque[0] if embarque else {}
    if isinstance(embarque, dict):
        return int(embarque.get("count") or 0)
    return 0


@router.get(
    "/calendrier",
    response_model=list[GrandPrixCalendrier],
    dependencies=[Depends(exiger_configuration)],
)
@journal.journaliser_echecs(DOMAINE, "Chargement du calendrier")
async def calendrier(saison: int | None = None) -> list[GrandPrixCalendrier]:
    """Les Grands Prix de la saison (l'année en cours par défaut), sans leurs cotes."""
    annee = saison or datetime.now(UTC).year
    lignes = await selectionner(
        "grands_prix",
        {
            "select": "id,nom,date_course,date_qualifications,statut,cotes(count)",
            "order": "date_course.asc.nullslast",
            **_filtre_saison(annee),
        },
    )
    return [
        GrandPrixCalendrier(
            id=ligne["id"],
            nom=ligne["nom"],
            date_course=ligne.get("date_course"),
            date_qualifications=ligne.get("date_qualifications"),
            statut=ligne["statut"],
            a_des_cotes=_compte(ligne.get("cotes")) > 0,
        )
        for ligne in lignes
    ]
