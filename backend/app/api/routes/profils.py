"""Profils — étape 8 : voiture personnalisée et statistiques.

Trois routes, toutes protégées : `utilisateur_courant` rejette les appels sans
jeton Supabase valide, et son résultat est la seule source d'identité. Le corps
de la requête ne dit jamais qui est l'appelant — `PATCH /profils/moi` ne prend
d'ailleurs aucun identifiant, précisément pour qu'on ne puisse pas repeindre la
voiture de quelqu'un d'autre.

**Deux niveaux d'autorisation, et la différence est voulue.** Chaque route est
alignée sur la politique RLS de la donnée qu'elle sert :

- `GET /profils/{id}` sert pseudo, couleurs et numéro. La politique « Profils
  lisibles par les membres connectés » les ouvre déjà à tout membre connecté,
  qui peut les lire directement dans Supabase : restreindre la route serait du
  théâtre, et empêcherait d'afficher une voiture dans un classement.
- `GET /profils/{id}/stats` agrège des `points_gagnes`, donc des lignes que la
  politique de l'étape 5 réserve aux membres d'un championnat partagé. La route
  exige donc que le demandeur soit le membre lui-même, ou partage au moins un
  championnat avec lui. Sans ce contrôle, le backend servirait avec sa clé de
  service — qui contourne la RLS — un résumé de la saison de n'importe qui à
  n'importe quel inscrit. C'est le même raisonnement qu'à l'étape 6 pour
  `GET /grands-prix/{id}/resultats?championnat_id=`.
"""

import re
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.api.deps import utilisateur_courant
from app.api.journal import echec_lisible as _echec_lisible
from app.api.journal import journaliser_echecs
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    mettre_a_jour,
    selectionner,
)

router = APIRouter(prefix="/profils", tags=["profils"])

DOMAINE = "profils"

# Colonnes servies par les deux routes de lecture. Écrites une fois : deux
# listes séparées finiraient par diverger, et le profil d'un autre membre
# afficherait une voiture différente de la sienne au classement.
COLONNES_PROFIL = (
    "id,pseudo,couleur1,couleur2,numero,livree_mode,livree_ecurie,is_admin,cree_le"
)

# Bornes du numéro (1 à 99), doublées par la contrainte `profils_numero_valide`.
NUMERO_MINIMUM = 1
NUMERO_MAXIMUM = 99

# Les couleurs partent telles quelles dans l'attribut `fill` d'un SVG : le
# format est vérifié ici ET en base (`profils_couleurs_hex`). Le frontend n'en
# propose que vingt, mais rien n'oblige un client à passer par le frontend.
MOTIF_COULEUR = re.compile(r"^#[0-9A-Fa-f]{6}$")

# Les deux modes d'affichage d'une voiture, doublés par la contrainte
# `profils_livree_mode_valide`.
MODE_PERSO = "perso"
MODE_ECURIE = "ecurie"
MODES_LIVREE = (MODE_PERSO, MODE_ECURIE)

# Le slug d'une livrée est vérifié sur son FORMAT, jamais contre la liste des
# onze écuries. Cette liste est un actif du frontend
# (`frontend/src/lib/livrees.js`), relu à chaque saison au même titre que la
# grille des pilotes ; la coder ici en dur obligerait à déployer le backend pour
# ajouter une voiture. Un slug que le frontend ne connaît pas n'est pas une
# panne : `livreeDuMembre` retombe sur les couleurs personnalisées, ce qui se
# voit à l'écran au lieu de planter. Même motif que la contrainte
# `profils_livree_ecurie_format`.
MOTIF_LIVREE = re.compile(r"^[a-z0-9-]{2,32}$")


def echec_lisible(contexte: str, erreur: BaseException) -> HTTPException:
    """Journalise une panne avec sa trace, et la renvoie en clair à l'appelant.

    Le mécanisme, ses raisons et le choix du `422` sont documentés dans
    `app/api/journal.py`, partagé par tous les domaines depuis l'étape 5.
    """
    return _echec_lisible(DOMAINE, contexte, erreur)


def refuser(message: str) -> HTTPException:
    """Saisie refusée pour une raison métier, dite en français."""
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=message
    )


# --------------------------------------------------------------------------- #
#  Modèles
# --------------------------------------------------------------------------- #


class ProfilServi(BaseModel):
    id: UUID
    pseudo: str
    couleur1: str
    couleur2: str
    # `None` tant que le membre n'a pas choisi de numéro. Ne pas le remplacer
    # par `0` : c'est le frontend qui décide quoi afficher à la place (le rang
    # au classement), et « numéro 0 » n'existe pas en Formule 1.
    numero: int | None = None
    # Les deux champs ont une VALEUR PAR DÉFAUT, et ce n'est pas du confort : un
    # backend déployé avant la migration recevrait des lignes sans ces colonnes
    # et rendrait `500` sur toute la réponse. C'est le piège déjà rencontré avec
    # `cree_par` à la version `0.4.1`. `perso` est aussi le repli du frontend.
    livree_mode: str = MODE_PERSO
    livree_ecurie: str | None = None
    # Drapeau d'administration (migration `20260820150000`). Même valeur par
    # défaut et même raison que les deux champs ci-dessus — mais ici le défaut
    # est aussi le moins privilégié des deux : une base non migrée, une colonne
    # renommée ou une réponse tronquée referment la section d'administration,
    # jamais l'inverse.
    #
    # **Il est servi, jamais reçu.** `ModificationProfil` ne le déclare pas et
    # `modifier_mon_profil` construit son dictionnaire champ par champ : un
    # `is_admin` glissé dans le corps d'un PATCH est ignoré, comme le sont déjà
    # `id` et `pseudo`. Se promouvoir soi-même par cette route est impossible.
    is_admin: bool = False
    cree_le: datetime


class ModificationProfil(BaseModel):
    """Modification partielle : ce qui n'est pas transmis n'est pas touché.

    Tous les champs sont facultatifs et valent `None` quand ils sont absents.
    `numero` a donc besoin d'un autre moyen de dire « je retire mon numéro » :
    c'est `retirer_numero`, un drapeau explicite. Sans lui, `numero: null`
    serait indiscernable de « champ non transmis », et un membre ne pourrait
    jamais revenir à l'état sans numéro.
    """

    couleur1: str | None = Field(default=None, max_length=16)
    couleur2: str | None = Field(default=None, max_length=16)
    numero: int | None = None
    retirer_numero: bool = False
    # `livree_mode` n'a pas besoin de drapeau de retrait : revenir aux couleurs
    # personnalisées, c'est passer le mode à `perso`, et le slug reste alors en
    # base — c'est le dernier choix du membre, qu'il retrouve s'il rebascule.
    livree_mode: str | None = Field(default=None, max_length=16)
    livree_ecurie: str | None = Field(default=None, max_length=32)


class StatsProfil(BaseModel):
    """Les quatre chiffres de la grille 2×2 des maquettes 12 et 14.

    **Tous entiers, jamais de décimale.** Pour `cote_moy_tentee`, c'est la règle
    4.1 elle-même : une cote moyenne s'affiche « 31 », jamais « ×3,1 ».
    """

    paris_gagnes_pct: int
    pts_moyen_gp: int
    meilleur_coup: int
    cote_moy_tentee: int
    # Trois compteurs qui ne s'affichent pas tels quels : ils disent à
    # l'interface si la saison a commencé pour ce membre. Sans eux, « meilleur
    # coup 0 » s'afficherait avant le premier Grand Prix, ce qui se lit comme un
    # mauvais bilan alors qu'il n'y a pas encore de bilan.
    pronostics_notes: int
    gp_joues: int
    total_points: int
    saison: int


# --------------------------------------------------------------------------- #
#  Autorisation et lectures communes
# --------------------------------------------------------------------------- #


async def profil(profil_id: UUID) -> dict:
    """Le profil, ou un `404` franc."""
    lignes = await selectionner(
        "profils",
        {"id": f"eq.{profil_id}", "select": COLONNES_PROFIL, "limit": "1"},
    )
    if not lignes:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ce membre n'existe pas.",
        )
    return lignes[0]


async def exiger_lien(cible: UUID, utilisateur: str) -> None:
    """Refuse un appelant qui n'a aucun championnat en commun avec la cible.

    Son propre profil passe toujours, et sans aucune lecture : quelqu'un qui
    n'appartient encore à aucun championnat doit pouvoir consulter ses propres
    statistiques.

    Deux lectures plutôt qu'une jointure : `membres_championnat` n'a pas de
    relation déclarée avec elle-même, PostgREST n'a donc rien à suivre. Les
    effectifs restent petits — quelques championnats par personne.
    """
    if str(cible) == utilisateur:
        return

    miens = await selectionner(
        "membres_championnat",
        {"profil_id": f"eq.{utilisateur}", "select": "championnat_id"},
    )
    identifiants = [str(ligne["championnat_id"]) for ligne in miens]

    if identifiants:
        partages = await selectionner(
            "membres_championnat",
            {
                "profil_id": f"eq.{cible}",
                "championnat_id": f"in.({','.join(identifiants)})",
                "select": "championnat_id",
                "limit": "1",
            },
        )
        if partages:
            return

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Tu ne partages aucun championnat avec ce membre.",
    )


def saison_courante() -> int:
    """Année civile en cours, en UTC — la même référence que `date_course`.

    Le CLAUDE.md dit « la saison en cours est l'année civile du GP ». Prendre
    l'heure locale du serveur ferait basculer la saison une ou deux heures trop
    tôt le 31 décembre, sur une donnée stockée en UTC depuis l'étape 4.
    """
    return datetime.now(UTC).year


def couleur_valide(valeur: str, role: str) -> str:
    propre = valeur.strip()
    if not MOTIF_COULEUR.match(propre):
        raise refuser(
            f"La {role} doit être une couleur au format #RRGGBB (reçu : « {propre} »)."
        )
    return propre.upper()


def livree_valide(valeur: str) -> str:
    """Normalise et vérifie le slug d'une livrée — son format, pas son existence."""
    propre = valeur.strip().lower()
    if not MOTIF_LIVREE.match(propre):
        raise refuser(
            f"Cette livrée n'a pas un identifiant valide (reçu : « {propre} »)."
        )
    return propre


# --------------------------------------------------------------------------- #
#  Routes
# --------------------------------------------------------------------------- #


@router.patch("/moi", response_model=ProfilServi)
@journaliser_echecs(DOMAINE, "Enregistrement de ta voiture")
async def modifier_mon_profil(
    corps: ModificationProfil,
    utilisateur: str = Depends(utilisateur_courant),
) -> ProfilServi:
    """Modifie la voiture de l'appelant : ses deux couleurs et son numéro.

    Déclarée **avant** `/{profil_id}` : les deux chemins n'entrent pas en
    conflit — les méthodes diffèrent — mais l'ordre rend la lecture du fichier
    conforme à ce que FastAPI fait, et évite qu'un futur `GET /moi` ne se fasse
    prendre son chemin pour un identifiant.

    L'identifiant modifié vient **du jeton vérifié**, jamais du corps : c'est ce
    qui empêche de repeindre la voiture de quelqu'un d'autre. Les politiques RLS
    protègent l'autre chemin, celui d'un client qui écrirait directement dans
    Supabase.
    """
    # Le profil est lu d'abord : sans lui, un `PATCH` qui ne touche aucune ligne
    # serait indiscernable d'un compte sans profil (migration des profils non
    # appliquée), et l'appelant recevrait un « rien à faire » trompeur.
    actuel = await profil(UUID(utilisateur))

    valeurs: dict = {}

    if corps.couleur1 is not None:
        valeurs["couleur1"] = couleur_valide(corps.couleur1, "couleur de la coque")
    if corps.couleur2 is not None:
        valeurs["couleur2"] = couleur_valide(corps.couleur2, "couleur des ailerons")

    if corps.retirer_numero:
        valeurs["numero"] = None
    elif corps.numero is not None:
        if not NUMERO_MINIMUM <= corps.numero <= NUMERO_MAXIMUM:
            raise refuser(
                f"Le numéro doit être compris entre {NUMERO_MINIMUM} et "
                f"{NUMERO_MAXIMUM} (reçu : {corps.numero})."
            )
        valeurs["numero"] = corps.numero

    if corps.livree_ecurie is not None:
        valeurs["livree_ecurie"] = livree_valide(corps.livree_ecurie)

    if corps.livree_mode is not None:
        mode = corps.livree_mode.strip().lower()
        if mode not in MODES_LIVREE:
            raise refuser(
                "Le mode de livrée doit être « perso » ou « ecurie » "
                f"(reçu : « {mode} »)."
            )
        valeurs["livree_mode"] = mode

    # Le mode `ecurie` exige une livrée. La vérification porte sur le couple
    # RÉSULTANT, exactement comme celle des couleurs ci-dessous : passer le mode
    # à `ecurie` sans jamais avoir choisi de livrée produirait sinon une ligne
    # que la contrainte `profils_livree_ecurie_requise` refuserait en base, avec
    # un message technique au lieu d'un refus en français.
    mode_final = valeurs.get("livree_mode", actuel.get("livree_mode") or MODE_PERSO)
    livree_finale = valeurs.get("livree_ecurie", actuel.get("livree_ecurie"))
    if mode_final == MODE_ECURIE and not livree_finale:
        raise refuser("Choisis une livrée d'écurie avant de l'appliquer.")

    # Les deux couleurs doivent différer. La comparaison porte sur le couple
    # RÉSULTANT, pas sur ce qui a été transmis : n'envoyer que `couleur1` en la
    # posant sur la valeur actuelle de `couleur2` produirait sinon une voiture
    # monochrome sans que rien ne soit refusé.
    #
    # Le contrôle vaut AUSSI en mode écurie : les deux couleurs restent en base
    # et redeviennent visibles dès que le membre rebascule sur « Ma livrée ».
    finale1 = valeurs.get("couleur1", str(actuel["couleur1"])).upper()
    finale2 = valeurs.get("couleur2", str(actuel["couleur2"])).upper()
    if finale1 == finale2:
        raise refuser("Choisis deux couleurs différentes pour ta voiture.")

    if not valeurs:
        # Rien à écrire : on rend l'état courant plutôt qu'un PATCH vide, que
        # PostgREST refuserait.
        return ProfilServi(**actuel)

    try:
        modifiees = await mettre_a_jour(
            "profils", {"id": f"eq.{utilisateur}"}, valeurs
        )
    except ErreurSupabase as erreur:
        raise echec_lisible("Enregistrement de ta voiture", erreur) from erreur

    if not modifiees:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ton profil est introuvable.",
        )

    return ProfilServi(**modifiees[0])


@router.get("/{profil_id}", response_model=ProfilServi)
@journaliser_echecs(DOMAINE, "Chargement du profil")
async def lire_profil(
    profil_id: UUID,
    _utilisateur: str = Depends(utilisateur_courant),
) -> ProfilServi:
    """Pseudo, couleurs et numéro d'un membre.

    Ouverte à tout appelant authentifié, comme la politique RLS « Profils
    lisibles par les membres connectés » qui sert déjà ces mêmes colonnes au
    frontend en lecture directe. Une restriction ici ne protégerait rien et
    empêcherait d'afficher une voiture dans un classement.
    """
    try:
        ligne = await profil(profil_id)
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement du profil", erreur) from erreur

    return ProfilServi(**ligne)


@router.get("/{profil_id}/stats", response_model=StatsProfil)
@journaliser_echecs(DOMAINE, "Chargement des statistiques")
async def lire_stats(
    profil_id: UUID,
    utilisateur: str = Depends(utilisateur_courant),
) -> StatsProfil:
    """Statistiques du membre sur la saison en cours.

    L'autorisation est vérifiée **avant** toute lecture : la fonction SQL est
    `security definer` et contourne donc la RLS, comme toutes celles que le
    backend appelle avec la clé de service. C'est ici, et nulle part ailleurs,
    que le partage d'un championnat est exigé.

    **La saison est l'année civile**, celle du Grand Prix. Un membre qui n'a
    pronostiqué qu'en 2025 voit donc une grille à zéro en 2026, et c'est
    l'intention : ces statistiques racontent la saison en cours, pas une
    carrière.
    """
    try:
        await exiger_lien(profil_id, utilisateur)
        # Le profil est vérifié APRÈS l'autorisation : répondre « ce membre
        # n'existe pas » à quelqu'un qui n'a rien à voir avec lui lui
        # apprendrait quels identifiants sont des comptes réels.
        await profil(profil_id)

        saison = saison_courante()
        brut = await appeler_fonction(
            "stats_du_profil",
            {"p_profil": str(profil_id), "p_saison": saison},
        )
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement des statistiques", erreur) from erreur

    return StatsProfil(**(brut or {}), saison=saison)
