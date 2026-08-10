"""Championnats — création, code d'invitation, adhésion, départ.

Toutes les routes sont protégées : `utilisateur_courant` rejette les appels
sans jeton Supabase valide, et son résultat est la seule source d'identité.
Le corps de la requête ne dit jamais qui est l'appelant.
"""

import re
import secrets
import string
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field

from app.api.deps import utilisateur_courant
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    inserer,
    selectionner,
    supprimer,
)

router = APIRouter(prefix="/championnats", tags=["championnats"])

# Code d'invitation : 6 caractères alphanumériques majuscules, sans séparateur
# (règle métier 4.5). Le même motif est répliqué en contrainte `check` sur la
# table : ni le frontend ni le backend ne peuvent y déroger.
ALPHABET_CODE = frozenset(string.ascii_uppercase + string.digits)
LONGUEUR_CODE = 6
MOTIF_CODE = re.compile(r"^[A-Z0-9]{6}$")

# Une collision sur 36^6 possibilités est déjà improbable ; cinq d'affilée
# signalerait autre chose qu'un hasard malheureux, et il vaut mieux échouer
# franchement que boucler.
TENTATIVES_CODE = 5

# Code d'erreur PostgreSQL d'une violation de contrainte d'unicité.
VIOLATION_UNICITE = "23505"


class CreationChampionnat(BaseModel):
    nom: str = Field(min_length=1, max_length=80)


class Adhesion(BaseModel):
    code: str = Field(min_length=1, max_length=32)


class Championnat(BaseModel):
    id: UUID
    nom: str
    code_invitation: str
    cree_par: UUID
    cree_le: datetime
    nombre_membres: int
    # Calculé ici plutôt que déduit côté frontend : la comparaison porte sur
    # l'identifiant du jeton vérifié, que le client n'a pas à refaire.
    est_createur: bool


def generer_code() -> str:
    """Code d'invitation aléatoire, tiré de `secrets` — jamais de `random`.

    Les caractères du jeton qui ne sont pas déjà des majuscules ou des chiffres
    sont écartés plutôt que transformés : passer le jeton en majuscules ferait
    tomber « a » et « A » sur la même lettre, et les lettres sortiraient deux
    fois plus souvent que les chiffres.
    """
    code = ""
    while len(code) < LONGUEUR_CODE:
        brut = secrets.token_urlsafe(LONGUEUR_CODE * 3)
        code += "".join(caractere for caractere in brut if caractere in ALPHABET_CODE)
    return code[:LONGUEUR_CODE]


def normaliser_code(saisi: str) -> str:
    """Ramène un code saisi à la main à sa forme canonique.

    Un code recopié depuis une conversation arrive avec des espaces, parfois un
    tiret, souvent en minuscules. Refuser « f1x7k2 » serait absurde : le code
    est unique en base sous sa forme majuscule.
    """
    return "".join(
        caractere for caractere in saisi.upper() if caractere in ALPHABET_CODE
    )


async def compter_membres(championnat_id: str) -> int:
    lignes = await selectionner(
        "membres_championnat",
        {"championnat_id": f"eq.{championnat_id}", "select": "profil_id"},
    )
    return len(lignes)


def en_championnat(ligne: dict, utilisateur: str, nombre_membres: int) -> Championnat:
    return Championnat(
        id=ligne["id"],
        nom=ligne["nom"],
        code_invitation=ligne["code_invitation"],
        cree_par=ligne["cree_par"],
        cree_le=ligne["cree_le"],
        nombre_membres=nombre_membres,
        est_createur=str(ligne["cree_par"]) == utilisateur,
    )


@router.post("", response_model=Championnat, status_code=status.HTTP_201_CREATED)
async def creer(
    corps: CreationChampionnat,
    utilisateur: str = Depends(utilisateur_courant),
) -> Championnat:
    """Crée un championnat et y inscrit son créateur comme premier membre."""
    nom = corps.nom.strip()
    if not 2 <= len(nom) <= 40:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Le nom du championnat doit faire entre 2 et 40 caractères.",
        )

    for tentative in range(TENTATIVES_CODE):
        try:
            # La fonction insère le championnat ET son créateur dans la même
            # transaction : un championnat sans membre serait invisible de tous,
            # y compris de celui qui vient de le créer.
            ligne = await appeler_fonction(
                "creer_championnat",
                {"p_nom": nom, "p_code": generer_code(), "p_createur": utilisateur},
            )
        except ErreurSupabase as erreur:
            # Le code tiré existait déjà : on retente avec un autre. Toute autre
            # erreur remonte telle quelle, sans consommer de tentative.
            if erreur.code == VIOLATION_UNICITE and tentative < TENTATIVES_CODE - 1:
                continue
            raise HTTPException(
                status_code=erreur.statut if erreur.statut >= 500 else 502,
                detail="La création du championnat a échoué. Réessaie.",
            ) from erreur

        return en_championnat(ligne, utilisateur, nombre_membres=1)

    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Impossible de générer un code d'invitation. Réessaie.",
    )


@router.get("/moi", response_model=list[Championnat])
async def mes_championnats(
    utilisateur: str = Depends(utilisateur_courant),
) -> list[Championnat]:
    """Championnats dont l'appelant est membre, avec leur effectif."""
    try:
        lignes = await appeler_fonction("mes_championnats", {"p_profil": utilisateur})
    except ErreurSupabase as erreur:
        raise HTTPException(
            status_code=erreur.statut if erreur.statut >= 500 else 502,
            detail="Impossible de charger tes championnats.",
        ) from erreur

    return [
        en_championnat(ligne, utilisateur, nombre_membres=ligne["nombre_membres"])
        for ligne in (lignes or [])
    ]


@router.post("/rejoindre", response_model=Championnat)
async def rejoindre(
    corps: Adhesion,
    utilisateur: str = Depends(utilisateur_courant),
) -> Championnat:
    """Inscrit l'appelant au championnat désigné par un code d'invitation."""
    code = normaliser_code(corps.code)
    if not MOTIF_CODE.match(code):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Un code d'invitation compte 6 caractères.",
        )

    try:
        trouves = await selectionner(
            "championnats",
            {"code_invitation": f"eq.{code}", "select": "*", "limit": "1"},
        )
    except ErreurSupabase as erreur:
        raise HTTPException(
            status_code=erreur.statut if erreur.statut >= 500 else 502,
            detail="Impossible de vérifier ce code. Réessaie.",
        ) from erreur

    if not trouves:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Aucun championnat ne correspond à ce code.",
        )

    championnat = trouves[0]

    try:
        await inserer(
            "membres_championnat",
            {"championnat_id": championnat["id"], "profil_id": utilisateur},
        )
    except ErreurSupabase as erreur:
        # La clé primaire (championnat_id, profil_id) rend l'adhésion en double
        # impossible : c'est elle qui répond, pas une lecture préalable qui
        # laisserait passer deux appels simultanés.
        if erreur.code == VIOLATION_UNICITE:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Tu fais déjà partie de ce championnat.",
            ) from erreur
        raise HTTPException(
            status_code=erreur.statut if erreur.statut >= 500 else 502,
            detail="Impossible de rejoindre ce championnat. Réessaie.",
        ) from erreur

    return en_championnat(
        championnat, utilisateur, nombre_membres=await compter_membres(championnat["id"])
    )


@router.delete("/{championnat_id}/quitter", status_code=status.HTTP_204_NO_CONTENT)
async def quitter(
    championnat_id: UUID,
    utilisateur: str = Depends(utilisateur_courant),
) -> Response:
    """Retire l'appelant du championnat.

    Le créateur peut partir comme n'importe quel membre : le championnat lui
    survit. Rien ne le supprime, y compris s'il devient vide — c'est une
    décision de l'étape 3, pas un oubli.
    """
    try:
        supprimees = await supprimer(
            "membres_championnat",
            {
                "championnat_id": f"eq.{championnat_id}",
                "profil_id": f"eq.{utilisateur}",
            },
        )
    except ErreurSupabase as erreur:
        raise HTTPException(
            status_code=erreur.statut if erreur.statut >= 500 else 502,
            detail="Impossible de quitter ce championnat. Réessaie.",
        ) from erreur

    if not supprimees:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tu ne fais pas partie de ce championnat.",
        )

    # TODO(étape 5) — effacer ici les pronostics de ce membre dans ce
    # championnat. La table `pronostics` n'existe pas encore ; quand elle
    # existera, sa suppression devra se faire dans la même transaction que le
    # retrait ci-dessus, sans quoi un départ interrompu laisserait des
    # pronostics orphelins qui continueraient d'alimenter le classement.

    return Response(status_code=status.HTTP_204_NO_CONTENT)
