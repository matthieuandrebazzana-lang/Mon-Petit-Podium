"""Championnats — création, code d'invitation, adhésion, départ.

Toutes les routes sont protégées : `utilisateur_courant` rejette les appels
sans jeton Supabase valide, et son résultat est la seule source d'identité.
Le corps de la requête ne dit jamais qui est l'appelant.
"""

import logging
import re
import secrets
import string
from datetime import datetime
from functools import wraps
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

# Logger d'uvicorn : sous Railway, c'est le seul qui dispose d'un handler. Un
# logger maison (`logging.getLogger(__name__)`) écrirait dans le vide, et le
# diagnostic se ferait de nouveau à l'aveugle.
logger = logging.getLogger("uvicorn.error")

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


def _technique(erreur: BaseException) -> str:
    """Décrit une exception en une ligne, sans rien perdre de ce qui identifie la panne.

    Pour un échec Supabase, le message de PostgREST seul ne suffit pas : le code
    (`42P01` table absente, `42501` droits, `23505` doublon…) et le statut HTTP
    disent souvent à eux seuls ce qui manque. Pour tout le reste, le nom de la
    classe distingue une panne réseau d'une clé absente dans un dictionnaire.
    """
    if isinstance(erreur, ErreurSupabase):
        morceaux = [erreur.message or "Erreur Supabase."]
        if erreur.code:
            morceaux.append(f"code {erreur.code}")
        if erreur.statut:
            morceaux.append(f"statut {erreur.statut}")
        return " · ".join(morceaux)
    return f"{type(erreur).__name__}: {erreur}"


def echec_lisible(contexte: str, erreur: BaseException) -> HTTPException:
    """Journalise une panne avec sa trace, et la renvoie en clair à l'appelant.

    **Mesure de diagnostic, temporaire.** Un `502` opaque ne dit rien : ni les
    logs Railway ni le frontend ne portaient jusqu'ici la cause réelle. Le
    `422` retenu ici n'a rien d'une erreur de validation, mais c'est le seul
    statut que `lib/api.js` affiche déjà tel quel côté frontend, et qui ne se
    confond ni avec le `503` d'une configuration absente ni avec le `500` d'un
    plantage non capturé.

    À appeler **depuis un bloc `except`** : `logger.exception` n'a de trace à
    joindre que là.
    """
    detail = _technique(erreur)
    logger.exception("[championnats] %s — %s", contexte, detail)
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail=f"{contexte} — {detail}",
    )


def journaliser_echecs(contexte: str):
    """Enrobe un handler pour qu'aucune exception ne sorte sans être journalisée.

    Les `HTTPException` traversent intactes : ce sont les réponses voulues par
    la logique métier (`404` code inconnu, `409` déjà membre, `503` sans clés
    Supabase), pas des pannes. Tout le reste — panne réseau, table absente,
    clé manquante dans une réponse, bug — était jusqu'ici rendu par Railway en
    `502` sans une ligne de log ; il ressort maintenant en clair, avec sa trace.

    `functools.wraps` n'est pas cosmétique : FastAPI lit la signature du
    handler pour construire ses dépendances et son modèle de réponse, et
    `inspect.signature` suit `__wrapped__`. Sans lui, la route recevrait
    `(*args, **kwargs)` et perdrait `Depends(utilisateur_courant)`.
    """

    def decorateur(handler):
        @wraps(handler)
        async def enveloppe(*args, **kwargs):
            try:
                return await handler(*args, **kwargs)
            except HTTPException:
                raise
            except Exception as erreur:  # noqa: BLE001 — c'est tout l'objet
                raise echec_lisible(contexte, erreur) from erreur

        return enveloppe

    return decorateur


class CreationChampionnat(BaseModel):
    nom: str = Field(min_length=1, max_length=80)


class Adhesion(BaseModel):
    code: str = Field(min_length=1, max_length=32)


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


@router.delete("/{championnat_id}/quitter", status_code=status.HTTP_204_NO_CONTENT)
@journaliser_echecs("Départ du championnat")
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
        raise echec_lisible("Départ du championnat", erreur) from erreur

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
