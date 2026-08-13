"""Favoris et pronostics — étape 5.

Quatre routes, toutes protégées : `utilisateur_courant` rejette les appels sans
jeton Supabase valide, et son résultat est la seule source d'identité. Le corps
de la requête ne dit jamais qui est l'appelant.

La cinquième route du parcours, `GET /grands-prix/{id}/cotes`, existe depuis
l'étape 4 et vit dans `routes/scraper.py` : elle est **publique**, comme les
politiques RLS des tables `grands_prix` et `cotes`. Elle n'est pas redéfinie
ici — deux handlers sur le même chemin, et c'est le premier routeur monté qui
gagne, silencieusement.

Les valeurs servies sont toujours des **points** (règle 4.1). Aucune cote brute
ne sort d'ici : la base ne stocke que des entiers, et rien à l'étage du frontend
n'a à diviser par 100.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.api.deps import utilisateur_courant
from app.api.journal import journaliser_echecs
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    inserer,
    selectionner,
    supprimer,
)

router = APIRouter(tags=["pronostics"])

DOMAINE = "pronostics"

# Marchés dont sont tirés les deux pronostics obligatoires (règle 4.2). Ce sont
# les slugs fabriqués par `scraper.unibet.slug()` à partir des libellés Unibet
# « Vainqueur » et « Podium ».
#
# Le contrôle est strict, et c'est un choix : un pronostic « vainqueur » qui
# désignerait en réalité une écurie ou un abandon serait impossible à valider à
# l'étape 6, et le joueur ne le découvrirait qu'après la course. Si Unibet
# renomme un jour ces marchés, la saisie sera refusée franchement — avec un
# message qui nomme le marché attendu — plutôt que d'enregistrer des pronostics
# que rien ne saura départager.
MARCHE_VAINQUEUR = "vainqueur"
MARCHE_PODIUM = "podium"

# Règle 4.2 : trois pronostics bonus au choix. La maquette 09 affiche « sur 3
# max » et son bouton de validation reste actif : le joueur peut donc enregistrer
# moins de trois bonus et compléter plus tard, jusqu'à la fermeture. C'est un
# maximum, pas un quota.
BONUS_MAXIMUM = 3

# Règle 4.3 : fermeture cinq minutes avant le départ.
MARGE_FERMETURE = timedelta(minutes=5)

# Codes d'erreur levés par les fonctions de la migration de l'étape 5.
FERMETURE_DEPASSEE = "PT423"
TROP_DE_BONUS = "PT403"
VIOLATION_UNICITE = "23505"

PRONOSTICS_FERMES = (
    "Les pronostics de ce Grand Prix sont fermés : le départ est dans moins de "
    "cinq minutes."
)


# --------------------------------------------------------------------------- #
#  Modèles
# --------------------------------------------------------------------------- #


class BasculeFavori(BaseModel):
    id_outcome_unibet: str = Field(min_length=1, max_length=64)


class EtatFavori(BaseModel):
    """Réponse de la bascule : l'état dans lequel se trouve la cote après coup."""

    favori: bool


class FavoriServi(BaseModel):
    id_outcome_unibet: str
    # Les quatre champs suivants sont nuls quand la cote a disparu du GP depuis
    # que le joueur l'a épinglée. Le favori reste servi : le supprimer en douce
    # ferait disparaître une ligne de l'écran sans explication.
    marche: str | None = None
    libelle: str | None = None
    pilote: str | None = None
    points: int | None = None


class Podium(BaseModel):
    """Les deux pilotes du podium, sans ordre entre eux."""

    pilote_1: str = Field(min_length=1, max_length=64)
    pilote_2: str = Field(min_length=1, max_length=64)


class SaisiePronostics(BaseModel):
    vainqueur: str = Field(min_length=1, max_length=64)
    podium: Podium
    bonus: list[str] = Field(default_factory=list, max_length=BONUS_MAXIMUM)


class PodiumServi(BaseModel):
    pilote_1: str
    pilote_2: str
    nom_1: str | None = None
    nom_2: str | None = None
    points_2: int | None = None


class PronosticServi(BaseModel):
    id: UUID
    type: str
    outcome: str
    pilote: str | None = None
    marche: str | None = None
    libelle: str | None = None
    points: int | None = None
    podium: PodiumServi | None = None


class MembrePronostics(BaseModel):
    profil_id: UUID
    pseudo: str
    rejoint_le: datetime
    pronostics: list[PronosticServi]


# --------------------------------------------------------------------------- #
#  Lectures communes
# --------------------------------------------------------------------------- #


async def grand_prix(gp_id: UUID) -> dict:
    """Le GP, ou un `404` franc. Toutes les routes commencent par là."""
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


async def cotes_du_gp(gp_id: UUID) -> dict[str, dict]:
    """Les cotes du GP, indexées par identifiant d'issue.

    Une seule lecture sert à la fois de contrôle (l'issue pronostiquée
    existe-t-elle ?) et de source des libellés et des points renvoyés. Un GP
    compte quelques dizaines de cotes : les ramener toutes coûte moins qu'un
    aller-retour par issue vérifiée.
    """
    lignes = await selectionner(
        "cotes",
        {
            "gp_id": f"eq.{gp_id}",
            "select": "id_outcome_unibet,marche,libelle_marche,pilote,valeur",
        },
    )
    return {ligne["id_outcome_unibet"]: ligne for ligne in lignes}


def pronostics_fermes(gp: dict) -> bool:
    """Règle 4.3 — plus aucune modification cinq minutes avant le départ.

    Un GP dont l'heure de départ n'est pas connue reste ouvert : refuser tout le
    monde parce qu'Unibet n'a pas encore annoncé l'horaire serait le mauvais sens
    du doute. La même règle, écrite de la même façon, est rejouée en base par
    `public.pronostics_fermes(uuid)` — c'est elle qui fait foi au moment de
    l'écriture.
    """
    brut = gp.get("date_course")
    if not brut:
        return False

    depart = datetime.fromisoformat(str(brut).replace("Z", "+00:00"))
    if depart.tzinfo is None:
        depart = depart.replace(tzinfo=UTC)

    return datetime.now(UTC) >= depart - MARGE_FERMETURE


def exiger_ouvert(gp: dict) -> None:
    if pronostics_fermes(gp):
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED, detail=PRONOSTICS_FERMES
        )


async def exiger_membre(championnat_id: UUID, utilisateur: str) -> None:
    """Refuse un appelant qui n'est pas membre du championnat demandé.

    Les pronostics des autres ne sont lisibles qu'entre membres d'un même
    championnat (règle 4.3). Le backend lit avec la clé de service, qui
    contourne la RLS : c'est donc ici, et nulle part ailleurs, que
    l'autorisation est portée — à partir de l'identifiant du jeton vérifié,
    jamais d'une valeur reçue dans le corps de la requête.
    """
    lignes = await selectionner(
        "membres_championnat",
        {
            "championnat_id": f"eq.{championnat_id}",
            "profil_id": f"eq.{utilisateur}",
            "select": "profil_id",
            "limit": "1",
        },
    )
    if not lignes:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu ne fais pas partie de ce championnat.",
        )


def refuser(message: str) -> HTTPException:
    """Saisie refusée pour une raison métier, dite en français."""
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=message
    )


def exiger_cote(cotes: dict[str, dict], outcome: str, role: str) -> dict:
    cote = cotes.get(outcome)
    if cote is None:
        raise refuser(f"Cette cote n'existe pas pour ce Grand Prix ({role}).")
    return cote


def exiger_marche(cote: dict, attendu: str, role: str) -> None:
    if cote.get("marche") != attendu:
        raise refuser(
            f"Le pronostic « {role} » doit être choisi dans le marché "
            f"« {attendu} » (reçu : « {cote.get('marche')} »)."
        )


# --------------------------------------------------------------------------- #
#  Favoris
# --------------------------------------------------------------------------- #


@router.post("/grands-prix/{gp_id}/favoris", response_model=EtatFavori)
@journaliser_echecs(DOMAINE, "Mise en favori")
async def basculer_favori(
    gp_id: UUID,
    corps: BasculeFavori,
    utilisateur: str = Depends(utilisateur_courant),
) -> EtatFavori:
    """Épingle une cote, ou la retire si elle l'était déjà.

    La bascule est faite par une suppression suivie, si rien n'a été supprimé,
    d'une insertion. Lire d'abord pour décider ensuite laisserait deux appuis
    rapprochés se croiser et retomber tous deux du même côté ; ici, c'est la
    base qui tranche, et la clé primaire qui arbitre l'insertion concurrente.
    """
    await grand_prix(gp_id)

    outcome = corps.id_outcome_unibet.strip()
    cotes = await cotes_du_gp(gp_id)
    exiger_cote(cotes, outcome, "favori")

    filtre = {
        "profil_id": f"eq.{utilisateur}",
        "gp_id": f"eq.{gp_id}",
        "id_outcome_unibet": f"eq.{outcome}",
    }

    if await supprimer("favoris", filtre):
        return EtatFavori(favori=False)

    try:
        await inserer(
            "favoris",
            {
                "profil_id": utilisateur,
                "gp_id": str(gp_id),
                "id_outcome_unibet": outcome,
            },
        )
    except ErreurSupabase as erreur:
        # Deux appuis simultanés : l'autre a gagné la course, la cote est bien
        # en favori. C'est l'état demandé, pas une erreur.
        if erreur.code != VIOLATION_UNICITE:
            raise
    return EtatFavori(favori=True)


@router.get("/grands-prix/{gp_id}/favoris", response_model=list[FavoriServi])
@journaliser_echecs(DOMAINE, "Chargement de tes favoris")
async def mes_favoris(
    gp_id: UUID,
    utilisateur: str = Depends(utilisateur_courant),
) -> list[FavoriServi]:
    """Favoris de l'appelant pour ce GP, dans l'ordre où il les a épinglés."""
    await grand_prix(gp_id)

    lignes = await selectionner(
        "favoris",
        {
            "profil_id": f"eq.{utilisateur}",
            "gp_id": f"eq.{gp_id}",
            "select": "id_outcome_unibet,cree_le",
            "order": "cree_le.asc",
        },
    )
    if not lignes:
        return []

    cotes = await cotes_du_gp(gp_id)
    return [
        FavoriServi(
            id_outcome_unibet=ligne["id_outcome_unibet"],
            **_details(cotes.get(ligne["id_outcome_unibet"])),
        )
        for ligne in lignes
    ]


def _details(cote: dict | None) -> dict:
    """Libellés et points d'une cote, ou des `None` si elle a disparu."""
    if not cote:
        return {}
    return {
        "marche": cote.get("marche"),
        "libelle": cote.get("libelle_marche"),
        "pilote": cote.get("pilote"),
        "points": cote.get("valeur"),
    }


# --------------------------------------------------------------------------- #
#  Pronostics
# --------------------------------------------------------------------------- #


@router.post(
    "/grands-prix/{gp_id}/pronostics", response_model=list[PronosticServi]
)
@journaliser_echecs(DOMAINE, "Enregistrement de tes pronostics")
async def enregistrer(
    gp_id: UUID,
    corps: SaisiePronostics,
    utilisateur: str = Depends(utilisateur_courant),
) -> list[PronosticServi]:
    """Remplace le pronostic de l'appelant pour ce GP.

    Toute la saisie est reçue d'un bloc et remplace la précédente : le joueur
    modifie librement jusqu'à la fermeture (règle 4.3), et un enregistrement
    partiel n'aurait pas de sens — un pronostic à moitié effacé vaut moins que
    l'ancien, qui au moins était complet.
    """
    gp = await grand_prix(gp_id)
    exiger_ouvert(gp)

    vainqueur = corps.vainqueur.strip()
    pilote_1 = corps.podium.pilote_1.strip()
    pilote_2 = corps.podium.pilote_2.strip()
    bonus = [choix.strip() for choix in corps.bonus if choix.strip()]

    if pilote_1 == pilote_2:
        raise refuser("Choisis deux pilotes différents pour le podium.")

    if len(set(bonus)) != len(bonus):
        raise refuser("Chaque pronostic bonus doit porter sur une cote différente.")

    if len(bonus) > BONUS_MAXIMUM:
        raise refuser(f"Trois pronostics bonus au maximum ({len(bonus)} reçus).")

    cotes = await cotes_du_gp(gp_id)
    exiger_marche(
        exiger_cote(cotes, vainqueur, "vainqueur"), MARCHE_VAINQUEUR, "vainqueur"
    )
    exiger_marche(exiger_cote(cotes, pilote_1, "podium"), MARCHE_PODIUM, "podium")
    exiger_marche(exiger_cote(cotes, pilote_2, "podium"), MARCHE_PODIUM, "podium")
    for choix in bonus:
        exiger_cote(cotes, choix, "bonus")

    # Règle 4.2 : les bonus se choisissent parmi les favoris. Le contrôle est
    # fait ici plutôt qu'en base pour pouvoir nommer la cote fautive — « ce
    # pronostic n'est pas dans tes favoris » sans dire lequel n'aide personne.
    if bonus:
        epingles = {
            ligne["id_outcome_unibet"]
            for ligne in await selectionner(
                "favoris",
                {
                    "profil_id": f"eq.{utilisateur}",
                    "gp_id": f"eq.{gp_id}",
                    "select": "id_outcome_unibet",
                },
            )
        }
        hors_favoris = [choix for choix in bonus if choix not in epingles]
        if hors_favoris:
            noms = ", ".join(
                str(cotes[choix].get("pilote") or choix) for choix in hors_favoris
            )
            raise refuser(
                f"Les pronostics bonus se choisissent parmi tes favoris. "
                f"À mettre en favori d'abord : {noms}."
            )

    try:
        # Une seule transaction : le pronostic précédent n'est effacé que si le
        # nouveau s'écrit en entier. La fermeture y est revérifiée — entre le
        # contrôle ci-dessus et l'écriture, quelques dizaines de millisecondes
        # passent, et c'est à cinq minutes du départ que cela se joue.
        rendus = await appeler_fonction(
            "enregistrer_pronostics",
            {
                "p_profil": utilisateur,
                "p_gp": str(gp_id),
                "p_vainqueur": vainqueur,
                "p_podium_1": pilote_1,
                "p_podium_2": pilote_2,
                "p_bonus": bonus,
            },
        )
    except ErreurSupabase as erreur:
        if erreur.code == FERMETURE_DEPASSEE:
            raise HTTPException(
                status_code=status.HTTP_423_LOCKED, detail=PRONOSTICS_FERMES
            ) from erreur
        if erreur.code == TROP_DE_BONUS:
            raise refuser("Trois pronostics bonus au maximum.") from erreur
        raise

    return [PronosticServi(**ligne) for ligne in (rendus or [])]


@router.get(
    "/grands-prix/{gp_id}/pronostics/championnat/{championnat_id}",
    response_model=list[MembrePronostics],
)
@journaliser_echecs(DOMAINE, "Chargement des pronostics du championnat")
async def pronostics_du_championnat(
    gp_id: UUID,
    championnat_id: UUID,
    utilisateur: str = Depends(utilisateur_courant),
) -> list[MembrePronostics]:
    """Pronostics de tous les membres du championnat pour ce GP.

    Les membres sans pronostic sont renvoyés avec une liste vide : l'interface
    doit pouvoir montrer qui manque à l'appel, pas seulement qui a joué.
    """
    await exiger_membre(championnat_id, utilisateur)
    await grand_prix(gp_id)

    membres = await appeler_fonction(
        "pronostics_du_championnat",
        {"p_championnat": str(championnat_id), "p_gp": str(gp_id)},
    )
    return [MembrePronostics(**membre) for membre in (membres or [])]
