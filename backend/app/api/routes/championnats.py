"""Championnats — création, code d'invitation, adhésion, départ.

Toutes les routes sont protégées : `utilisateur_courant` rejette les appels
sans jeton Supabase valide, et son résultat est la seule source d'identité.
Le corps de la requête ne dit jamais qui est l'appelant.
"""

import asyncio
import re
import secrets
import string
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field

from app.api import journal
from app.api.deps import utilisateur_courant
from app.api.routes.pronostics import exiger_membre
from app.api.stockage import COMPARTIMENT_CHAMPIONNATS, url_de_photo_valide
from app.supabase_client import (
    ErreurSupabase,
    appeler_fonction,
    inserer,
    mettre_a_jour,
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

# Statuts d'un Grand Prix qui n'a pas encore été couru. `termine` en est exclu,
# et c'est tout l'objet du filtre : le « prochain GP » d'un championnat est
# celui sur lequel il reste quelque chose à faire.
STATUTS_A_VENIR = ("a_venir", "cotes_figees")

# Nombre maximum de championnats dont la carte porte le rang de l'appelant.
# Chaque rang coûte un appel à `classement_du_championnat` ; ils partent tous en
# parallèle, mais la règle 4.5 ne borne pas le nombre d'adhésions et rien
# n'empêche d'en avoir cinquante. Au-delà de cette limite, les cartes suivantes
# s'affichent **sans** rang plutôt que d'allonger la route la plus sollicitée de
# l'application. Les championnats sont servis dans l'ordre de `mes_championnats`,
# donc ce sont toujours les mêmes qui portent le rang d'un chargement à l'autre.
LIMITE_CLASSEMENTS = 12

# Saison servie par défaut au calendrier. Écrite ici plutôt que déduite de
# `datetime.now()` : le calendrier doit rester lisible en intersaison, où
# l'année courante n'a encore aucun Grand Prix en base. À faire évoluer avec la
# grille de `backend/app/calcul/pilotes.py`, qui décrit la même saison.
SAISON_COURANTE = 2026


class CreationChampionnat(BaseModel):
    nom: str = Field(min_length=1, max_length=80)


class Adhesion(BaseModel):
    code: str = Field(min_length=1, max_length=32)


class ModificationChampionnat(BaseModel):
    """Modification partielle d'un championnat : aujourd'hui, sa photo seule.

    Le nom n'y figure PAS, et c'est un choix de portée, pas un oubli : le
    renommer changerait ce que lisent tous ses membres, et cette route n'existe
    que pour poser une photo au moment de la création. Le jour où le nom devient
    modifiable, il prendra sa place ici — avec la même validation de longueur que
    `creer`, tirée d'un helper commun plutôt que recopiée.

    `retirer_photo` est un drapeau explicite, comme `retirer_numero` au profil :
    un `photo_url: null` serait indiscernable d'un champ non transmis, et la
    photo ne pourrait plus jamais être retirée.
    """

    photo_url: str | None = Field(default=None, max_length=512)
    retirer_photo: bool = False


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
    # Rang d'adhésion au championnat, 4ᵉ critère de départage.
    ordre_inscription: int
    # La voiture du membre (étape 8). Les couleurs ne sont jamais nulles : la
    # fonction SQL retombe sur les défauts de la colonne quand le profil manque,
    # sans quoi le SVG afficherait des aplats transparents. Le numéro, lui, reste
    # nul tant que le membre n'en a pas choisi — c'est alors son rang qui
    # s'affiche sur la voiture, comme à l'étape 7.
    couleur1: str = "#800111"
    couleur2: str = "#FFFFFF"
    # Couleur du numéro et du pseudo peints sur la voiture (migration
    # `20260823120000`). `None` veut dire « pas de choix », pas « pas de
    # couleur » : le frontend calcule alors l'encre qui contraste avec l'aplat.
    # Valeur par défaut pour la même raison que les champs voisins.
    couleur_texte: str | None = None
    numero: int | None = None
    # **Le skin, et il doit être déclaré ici pour exister.** `response_model`
    # de FastAPI ne laisse passer que les champs du modèle : la fonction SQL
    # les servait depuis la migration `20260819124500`, mais ils étaient
    # **filtrés avant d'atteindre le client**, si bien que `livreeDuMembre`
    # retombait toujours sur `perso` et qu'aucun skin n'apparaissait jamais sur
    # la piste ni au classement. Valeurs par défaut pour la même raison que les
    # deux couleurs : un backend déployé avant la migration rendrait sinon
    # TOUTE la réponse en `500` (piège de `cree_par`, version 0.4.1).
    livree_mode: str = "perso"
    livree_ecurie: str | None = None
    # La photo du membre (migration `20260821180000`). `None` quand il n'en a
    # pas : le classement affiche alors ses initiales, comme il l'a toujours
    # fait. Valeur par défaut pour la même raison que les champs ci-dessus.
    avatar_url: str | None = None


class LigneCalendrier(BaseModel):
    """Un membre au classement d'un seul Grand Prix (maquette 15)."""

    profil_id: UUID
    pseudo: str
    points: int
    # Le rang de CE Grand Prix, calculé par `rank` et non `row_number` : la
    # règle 4.6 départage le classement de la saison, pas une course isolée.
    # Deux membres à égalité sur un GP le sont vraiment, et partagent le rang.
    rang: int
    couleur1: str = "#800111"
    couleur2: str = "#FFFFFF"


class GrandPrixCalendrier(BaseModel):
    gp_id: UUID
    nom: str
    # Nulle tant qu'Unibet n'a pas annoncé l'horaire. Le GP est servi quand
    # même, en fin de liste : l'écarter le rendrait invisible jusqu'au samedi.
    date_course: datetime | None = None
    # Heure des qualifications (migration `20260816120000`, servie au calendrier
    # par la migration `20260820120000`). L'écran ne propose « Pronostiquer » que sur
    # un GP dont les cotes sont figées ET dont les qualifications sont passées :
    # le statut seul se laisse avancer par un déclenchement manuel du scraper,
    # l'heure des qualifications non (règle 4.3). Valeur par défaut pour qu'une
    # base non migrée ne fasse pas échouer la validation de TOUTE la réponse —
    # le piège de `cree_par` à la version `0.4.1`. Le frontend se ferme alors,
    # il ne s'ouvre jamais, sur un champ qu'il n'a pas.
    date_qualifications: datetime | None = None
    statut: str
    # Lus dans `cotes` et `resultats_gp`, jamais déduits du statut : rien ne fait
    # passer un GP en `cotes_figees` aujourd'hui, et le statut peut donc mentir
    # dans les deux sens.
    cotes_disponibles: bool = False
    resultats_disponibles: bool = False
    vainqueur: str | None = None
    # Ce que l'appelant a marqué sur ce GP. `None` tant qu'aucun de ses
    # pronostics n'a été noté — jamais `0`, qui se lirait « tout raté ».
    mes_points: int | None = None
    mon_rang: int | None = None
    mes_pronostics: int = 0
    classement: list[LigneCalendrier] = []


class ProchainGp(BaseModel):
    """Le Grand Prix à venir, annoncé sur chaque carte de championnat.

    Il est **le même pour tous les championnats** : `public.grands_prix` est une
    table globale, un Grand Prix n'appartient à personne. C'est ce qui permet de
    le lire une seule fois pour toute la liste (voir `prochain_grand_prix`).
    """

    id: UUID
    nom: str
    # Nulle tant qu'Unibet n'a pas annoncé l'horaire. Le GP est servi quand
    # même : l'écarter le rendrait invisible jusqu'au samedi des qualifications,
    # exactement le choix déjà fait pour le calendrier à l'étape 9.
    date_course: datetime | None = None
    statut: str


class PositionMembre(BaseModel):
    """Où en est l'appelant dans un championnat, pour sa carte de liste.

    Trois nombres et pas un de plus : le rang qui s'affiche en grand, ses points
    et ceux du leader — de quoi remplir la jauge de progression sans que l'écran
    ait à savoir comment un classement se calcule.

    `points_leader` est le **plus haut total du championnat**, pas celui du
    premier de la liste : les deux coïncident aujourd'hui, la fonction SQL triant
    d'abord par points, mais dériver la jauge d'une hypothèse d'ordre la ferait
    mentir le jour où le tri changerait.
    """

    mon_rang: int
    mes_points: int
    points_leader: int


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
    # Le prochain Grand Prix (étape 10), pour l'onglet Calendrier. `None` quand
    # aucun n'est à venir — la saison est terminée, ou le scraper n'a jamais
    # tourné. Valeur par défaut pour que les autres routes qui construisent un
    # `Championnat` (création, adhésion) n'aient pas à s'en soucier : elles
    # rendent un championnat qu'on vient de créer ou de rejoindre, l'écran
    # d'arrivée n'affiche pas de Grand Prix.
    prochain_gp: ProchainGp | None = None
    # La photo du championnat (migration `20260821180000`). `None` quand il n'en
    # a pas, et l'interface n'affiche alors RIEN à son emplacement — pas de
    # cadre vide, pas d'image de remplacement : une carte sans photo est
    # exactement la carte d'avant cette version.
    photo_url: str | None = None
    # La position de l'appelant dans ce championnat. `None` quand le classement
    # n'a pas pu être lu, ou au-delà de `LIMITE_CLASSEMENTS`. Valeur par défaut
    # pour la même raison que `prochain_gp` : la création et l'adhésion rendent
    # un championnat qu'on vient tout juste de rejoindre, où le classement n'a
    # rien à dire, et un frontend déployé avant le backend n'y perd rien.
    position: PositionMembre | None = None


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


def en_championnat(
    ligne: dict,
    utilisateur: str,
    nombre_membres: int,
    prochain_gp: ProchainGp | None = None,
    position: PositionMembre | None = None,
) -> Championnat:
    return Championnat(
        id=ligne["id"],
        nom=ligne["nom"],
        code_invitation=ligne["code_invitation"],
        cree_par=ligne["cree_par"],
        cree_le=ligne["cree_le"],
        nombre_membres=nombre_membres,
        est_createur=ligne["cree_par"] is not None
        and str(ligne["cree_par"]) == utilisateur,
        prochain_gp=prochain_gp,
        # `.get` et non `[…]` : `mes_championnats` sert cette colonne depuis la
        # migration `20260821180000`, mais `creer_championnat` rend la ligne
        # entière et `rejoindre` un `select *` — trois sources dont une seule
        # peut être en retard sur la migration. Une clé absente vaut « pas de
        # photo », jamais une exception qui emporterait toute la liste.
        photo_url=ligne.get("photo_url"),
        position=position,
    )


async def position_dans(championnat_id: str, profil: str) -> PositionMembre | None:
    """La place de l'appelant au classement d'un championnat.

    Elle est tirée de `classement_du_championnat`, **la fonction même** que sert
    `GET /championnats/{id}/classement` : le rang lu sur une carte de liste et
    celui lu sur l'écran du championnat ne peuvent donc pas diverger, et les
    quatre critères de départage de la règle 4.6 s'appliquent ici sans être
    réécrits. Les reprogrammer en Python aurait créé un second classement à
    tenir d'accord avec le premier.

    Un appelant absent du classement rend `None` plutôt que d'inventer une
    position : le cas ne devrait pas se produire — `mes_championnats` ne rend
    que des championnats dont il est membre, et un membre figure toujours au
    classement, fût-ce à zéro point — mais un rang faux sur une carte serait pire
    qu'une carte sans rang.
    """
    lignes = await appeler_fonction(
        "classement_du_championnat", {"p_championnat": championnat_id}
    )
    if not lignes:
        return None

    mienne = next(
        (l for l in lignes if str(l.get("profil_id")) == profil),
        None,
    )
    if mienne is None:
        return None

    return PositionMembre(
        mon_rang=int(mienne["rang"]),
        mes_points=int(mienne.get("total_points") or 0),
        points_leader=max(int(l.get("total_points") or 0) for l in lignes),
    )


async def positions_des_championnats(
    identifiants: list[str], profil: str
) -> dict[str, PositionMembre]:
    """Les positions de l'appelant dans plusieurs championnats, en parallèle.

    Un classement ne se lit **que** championnat par championnat : la fonction SQL
    est paramétrée par un championnat, et les points ne sont de toute façon pas
    cloisonnés (règle de l'étape 5) — c'est le championnat qui dit qui classer.
    Les appels partent donc ensemble plutôt qu'à la file : mis bout à bout, ils
    ajouteraient autant d'allers-retours Supabase que de championnats sur la
    route la plus chargée de l'application.

    **L'échec d'un classement n'emporte ni les autres ni la liste.** C'est le
    même arbitrage que pour le prochain Grand Prix depuis l'étape 10 : une carte
    sans rang reste une carte utile, une liste vide serait un cul-de-sac. Les
    pannes partent dans les logs Railway avec leur cause.
    """
    vises = identifiants[:LIMITE_CLASSEMENTS]
    if not vises:
        return {}

    resultats = await asyncio.gather(
        *(position_dans(identifiant, profil) for identifiant in vises),
        return_exceptions=True,
    )

    positions: dict[str, PositionMembre] = {}
    for identifiant, resultat in zip(vises, resultats):
        if isinstance(resultat, BaseException):
            journal.logger.warning(
                "[%s] Classement indisponible pour %s — %s",
                DOMAINE,
                identifiant,
                journal.technique(resultat),
            )
        elif resultat is not None:
            positions[identifiant] = resultat

    return positions


async def prochain_grand_prix() -> ProchainGp | None:
    """Le prochain Grand Prix non couru, ou `None` s'il n'y en a plus.

    **Lu une seule fois pour toute la liste des championnats.** Un Grand Prix
    n'appartient à aucun championnat : la table est globale, et le prochain GP
    est donc le même pour tous. Une lecture par championnat, ou une jointure
    dans `mes_championnats`, referait N fois le même travail.

    Deux points de mise en œuvre à ne pas défaire :

    - **Un GP sans horaire annoncé reste servi**, mais après les autres
      (`nullslast`). Sans cette clause, PostgreSQL place les NULL en tête et un
      GP dont Unibet n'a pas encore publié la date passerait devant la course de
      dimanche. C'est le même piège que `nullsFirst: false` à l'accueil.
    - **L'instant de comparaison est calculé ici, en UTC**, et non laissé à un
      `now` interprété par PostgreSQL : le résultat ne dépend alors ni du fuseau
      de la session, ni de la façon dont PostgREST transmet la valeur. Le suffixe
      `Z` est préféré à `+00:00`, dont le `+` se confond avec une espace une fois
      la requête encodée.
    """
    maintenant = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lignes = await selectionner(
        "grands_prix",
        {
            "statut": f"in.({','.join(STATUTS_A_VENIR)})",
            "or": f"(date_course.is.null,date_course.gte.{maintenant})",
            "select": "id,nom,date_course,statut",
            "order": "date_course.asc.nullslast",
            "limit": "1",
        },
    )
    return ProchainGp(**lignes[0]) if lignes else None


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
    """Championnats dont l'appelant est membre, avec leur effectif et le prochain GP.

    Le prochain Grand Prix est ajouté à l'étape 10 pour l'onglet Calendrier, qui
    annonce pour chaque championnat ce qui l'attend. Il est lu **une seule fois**
    et recopié sur chaque ligne : la table `grands_prix` est globale.

    **Son échec n'emporte pas la liste.** Un championnat sans Grand Prix annoncé
    reste un championnat lisible, alors qu'une liste vide serait un cul-de-sac —
    c'est le même arbitrage qu'à la version `0.5.1` pour les pronostics de
    l'accueil. La panne part dans les logs Railway, avec sa cause.
    """
    try:
        lignes = await appeler_fonction("mes_championnats", {"p_profil": utilisateur})
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement de tes championnats", erreur) from erreur

    if not lignes:
        return []

    try:
        prochain = await prochain_grand_prix()
    except Exception as erreur:  # noqa: BLE001 — le GP est un enrichissement
        journal.logger.warning(
            "[%s] Prochain Grand Prix indisponible — %s",
            DOMAINE,
            journal.technique(erreur),
        )
        prochain = None

    positions = await positions_des_championnats(
        [str(ligne["id"]) for ligne in lignes], utilisateur
    )

    return [
        en_championnat(
            ligne,
            utilisateur,
            nombre_membres=ligne["nombre_membres"],
            prochain_gp=prochain,
            position=positions.get(str(ligne["id"])),
        )
        for ligne in lignes
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


@router.patch("/{championnat_id}", response_model=Championnat)
@journaliser_echecs("Enregistrement de la photo du championnat")
async def modifier(
    championnat_id: UUID,
    corps: ModificationChampionnat,
    utilisateur: str = Depends(utilisateur_courant),
) -> Championnat:
    """Modifie un championnat — sa photo, et rien d'autre à ce jour.

    **Le créateur seul, et c'est la route qui le vérifie.** La politique RLS
    « Seul le createur modifie » dit déjà exactement cela, mais le backend écrit
    avec la clé de service, qui la contourne (`docs/architecture.md` §4) :
    l'autorisation est donc portée ici, à partir de l'identifiant du **jeton
    vérifié**, jamais d'une valeur reçue de l'appelant.

    Le refus est un `403` et non un `404` : le championnat existe, l'appelant en
    est peut-être membre, et lui répondre « il n'existe pas » serait faux.

    **Pourquoi cette route existe alors que la photo se choisit à la création.**
    Le chemin de stockage d'une photo est `{championnat_id}/photo.{ext}` : il a
    besoin d'un identifiant que seule la création rend. L'écran crée donc le
    championnat, dépose la photo sous l'identifiant obtenu, puis appelle cette
    route. Une photo transmise à `POST /championnats` obligerait à la déposer
    d'abord ailleurs, puis à la déplacer — deux fois plus d'opérations de
    stockage pour le même résultat.

    **Son échec n'annule pas la création** : l'écran d'arrivée affiche le
    championnat sans sa photo plutôt que de perdre le championnat. C'est le même
    arbitrage que pour le rang d'une carte et le prochain Grand Prix.
    """
    try:
        trouves = await selectionner(
            "championnats",
            {"id": f"eq.{championnat_id}", "select": "*", "limit": "1"},
        )
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement du championnat", erreur) from erreur

    if not trouves:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ce championnat n'existe pas.",
        )

    championnat = trouves[0]
    createur = championnat.get("cree_par")
    if createur is None or str(createur) != utilisateur:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Seul le créateur du championnat peut changer sa photo.",
        )

    valeurs: dict = {}
    # Le retrait l'emporte sur l'envoi, comme au profil : de deux intentions
    # contradictoires dans un même corps, celle qui efface est la seule qui ne
    # laisse pas de trace non voulue.
    if corps.retirer_photo:
        valeurs["photo_url"] = None
    elif corps.photo_url is not None:
        valeurs["photo_url"] = url_de_photo_valide(
            corps.photo_url, COMPARTIMENT_CHAMPIONNATS, "une photo de championnat"
        )

    if not valeurs:
        # Rien à écrire : on rend l'état courant plutôt qu'un PATCH vide, que
        # PostgREST refuserait.
        return en_championnat(
            championnat,
            utilisateur,
            nombre_membres=await compter_membres(championnat["id"]),
        )

    try:
        modifiees = await mettre_a_jour(
            "championnats", {"id": f"eq.{championnat_id}"}, valeurs
        )
    except ErreurSupabase as erreur:
        raise echec_lisible(
            "Enregistrement de la photo du championnat", erreur
        ) from erreur

    if not modifiees:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Ce championnat n'existe pas.",
        )

    return en_championnat(
        modifiees[0],
        utilisateur,
        nombre_membres=await compter_membres(championnat["id"]),
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


@router.get("/{championnat_id}/calendrier", response_model=list[GrandPrixCalendrier])
@journaliser_echecs("Chargement du calendrier")
async def calendrier(
    championnat_id: UUID,
    saison: int = SAISON_COURANTE,
    utilisateur: str = Depends(utilisateur_courant),
) -> list[GrandPrixCalendrier]:
    """Grands Prix de la saison, avec ce que le championnat y a marqué (maquette 15).

    L'appartenance est vérifiée **avant** toute lecture, comme au classement : la
    fonction SQL est `security definer` et contourne donc la RLS. C'est ici, et
    nulle part ailleurs, que l'autorisation est portée — à partir de
    l'identifiant du jeton vérifié, jamais d'une valeur reçue de l'appelant.

    Le profil transmis à la fonction est celui du **jeton**, pas un paramètre :
    « mon score sur ce GP » ne peut désigner que l'appelant. Un identifiant reçu
    dans l'URL laisserait un membre demander le calendrier vu par un autre.

    Aucun Grand Prix en base est un état normal tant que le scraper n'a pas
    tourné : la réponse est alors une liste vide, jamais un `404`.
    """
    await exiger_membre(championnat_id, utilisateur)

    try:
        lignes = await appeler_fonction(
            "calendrier_du_championnat",
            {
                "p_championnat": str(championnat_id),
                "p_profil": utilisateur,
                "p_saison": saison,
            },
        )
    except ErreurSupabase as erreur:
        raise echec_lisible("Chargement du calendrier", erreur) from erreur

    return [GrandPrixCalendrier(**ligne) for ligne in (lignes or [])]


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
