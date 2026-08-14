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

from app.api import journal
from app.api.deps import utilisateur_courant
from app.api.routes.pronostics import exiger_membre
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    inserer,
    selectionner,
)

router = APIRouter(prefix="/championnats", tags=["championnats"])

DOMAINE = "championnats"


def echec_lisible(contexte: str, erreur: BaseException) -> HTTPException:
    """Journalise une panne avec sa trace, et la renvoie en clair à l'appelant.

    Le mécanisme, ses raisons et le choix du `422` sont documentés dans
    `app/api/journal.py` — il est partagé avec le scraper et les pronostics
    depuis l'étape 5. À appeler depuis un bloc `except`.
    """
    return journal.echec_lisible(DOMAINE, contexte, erreur)


def journaliser_echecs(contexte: str):
    """Enrobe un handler pour qu'aucune exception ne sorte sans être journalisée."""
    return journal.journaliser_echecs(DOMAINE, contexte)


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


class LigneClassement(BaseModel):
    """Un membre au classement, déjà rangé par la fonction SQL (règle 4.6)."""

    profil_id: UUID
    pseudo: str
    # Somme des `points_gagnes` du membre. `0` — jamais `null` — quand aucun de
    # ses pronostics n'a encore été noté : un classement à blanc se lit « tout le
    # monde à zéro », pas « on ne sait pas ».
    total_points: int
    pronostics_reussis: int
    # Le plus gros coup, en points (règle 4.1). `None` tant qu'il n'a rien
    # réussi — `0` dirait que son meilleur coup vaut zéro.
    meilleure_cote: int | None = None
    # Rang de 1 à N, sans ex æquo : les quatre critères de la règle 4.6 réunis
    # départagent toujours.
    rang: int
    # Rang d'adhésion au championnat, 4ᵉ critère de départage. Il sert aussi de
    # graine à la livrée de la voiture côté frontend : le premier inscrit prend
    # la première combinaison de couleurs, et il la garde.
    ordre_inscription: int


class Championnat(BaseModel):
    id: UUID
    nom: str
    code_invitation: str
    # Nullable depuis la migration `20260813182331` : supprimer un compte ne
    # dissout plus les championnats qu'il a créés, ils lui survivent sans
    # créateur. Un `UUID` strict ferait échouer la validation de la réponse —
    # donc un 500 sur toute la liste — dès qu'un seul championnat est orphelin.
    cree_par: UUID | None
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
        est_createur=ligne["cree_par"] is not None
        and str(ligne["cree_par"]) == utilisateur,
    )


@router.post("", response_model=Championnat, status_code=status.HTTP_201_CREATED)
@journaliser_echecs("Création du championnat")
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
            raise echec_lisible("Création du championnat", erreur) from erreur

        return en_championnat(ligne, utilisateur, nombre_membres=1)

    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Impossible de générer un code d'invitation. Réessaie.",
    )


@router.get("/moi", response_model=list[Championnat])
@journaliser_echecs("Chargement de tes championnats")
async def mes_championnats(
    utilisateur: str = Depends(utilisateur_courant),
) -> list[Championnat]:
    """Championnats dont l'appelant est membre, avec leur effectif."""
    try:
        lignes = await appeler_fonction("mes_championnats", {"p_profil": utilisateur})
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement de tes championnats", erreur) from erreur

    return [
        en_championnat(ligne, utilisateur, nombre_membres=ligne["nombre_membres"])
        for ligne in (lignes or [])
    ]


@router.post("/rejoindre", response_model=Championnat)
@journaliser_echecs("Adhésion au championnat")
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
        raise echec_lisible("Vérification du code d'invitation", erreur) from erreur

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
        raise echec_lisible("Adhésion au championnat", erreur) from erreur

    return en_championnat(
        championnat, utilisateur, nombre_membres=await compter_membres(championnat["id"])
    )


@router.get("/{championnat_id}/classement", response_model=list[LigneClassement])
@journaliser_echecs("Chargement du classement")
async def classement(
    championnat_id: UUID,
    utilisateur: str = Depends(utilisateur_courant),
) -> list[LigneClassement]:
    """Classement du championnat, trié selon les départages de la règle 4.6.

    L'appartenance est vérifiée **avant** toute lecture : la fonction SQL est
    `security definer` et contourne donc la RLS, comme toutes celles que le
    backend appelle avec la clé de service. C'est ici, et nulle part ailleurs,
    que l'autorisation est portée — à partir de l'identifiant du jeton vérifié,
    jamais d'une valeur reçue de l'appelant.

    Un membre qui n'a jamais pronostiqué figure au classement avec 0 point : le
    faire disparaître de la liste des membres serait un autre écran.

    **Les points ne sont pas cloisonnés par championnat**, et c'est la règle
    posée à l'étape 5 : un pronostic vaut dans tous les championnats du joueur à
    la fois. Le championnat dit qui classer, pas quels pronostics compter.
    """
    await exiger_membre(championnat_id, utilisateur)

    try:
        lignes = await appeler_fonction(
            "classement_du_championnat", {"p_championnat": str(championnat_id)}
        )
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement du classement", erreur) from erreur

    return [LigneClassement(**ligne) for ligne in (lignes or [])]


@router.delete("/{championnat_id}/quitter", status_code=status.HTTP_204_NO_CONTENT)
@journaliser_echecs("Départ du championnat")
async def quitter(
    championnat_id: UUID,
    utilisateur: str = Depends(utilisateur_courant),
) -> Response:
    """Retire l'appelant du championnat, et efface ses pronostics s'il ne lui
    reste plus aucune adhésion.

    Le créateur peut partir comme n'importe quel membre : le championnat lui
    survit, sans créateur (migration `20260813182331`). S'il ne reste plus
    personne, le trigger `membres_championnat_supprime_vide` l'efface.

    Le retrait et l'effacement des pronostics se font dans **une seule
    transaction**, côté base : c'est ce qu'exigeait le `TODO` de l'étape 3, sans
    quoi un départ interrompu laisserait des pronostics orphelins qui
    continueraient d'alimenter le classement.

    **Les pronostics ne sont effacés que si le joueur ne fait plus partie
    d'aucun championnat.** Un pronostic n'appartient pas à un championnat : le
    joueur en remplit un par Grand Prix, qui compte dans tous ses championnats à
    la fois. Les effacer au départ d'un seul détruirait son classement dans les
    autres.
    """
    try:
        retire = await appeler_fonction(
            "quitter_championnat",
            {"p_profil": utilisateur, "p_championnat": str(championnat_id)},
        )
    except ErreurSupabase as erreur:
        raise echec_lisible("Départ du championnat", erreur) from erreur

    if not retire:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tu ne fais pas partie de ce championnat.",
        )

    return Response(status_code=status.HTTP_204_NO_CONTENT)
