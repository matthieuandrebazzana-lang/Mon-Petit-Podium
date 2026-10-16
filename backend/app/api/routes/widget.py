"""Widgets iOS « Classement » et « Mes pronos » — un jeton dédié, des routes en lecture seule.

Trois routes (`decisions.md` §28, §30) :

- `POST /widget/token` — authentifiée par la **session Supabase** de l'app, rend
  un jeton widget signé (`app/api/jeton_widget.py`) : identifiant du profil,
  30 jours, lecture seule. Aucune table ;
- `GET /widget/championnats/{id}/classement` — authentifiée **uniquement** par ce
  jeton. Vérifie que le profil est membre du championnat, puis rend le classement
  réduit à ce que dessine la vue Piste : rang, points, pseudo, avatar, livrée et
  couleurs. Rien d'autre ;
- `GET /widget/pronos` — authentifiée **uniquement** par ce jeton. Le prochain
  Grand Prix et le dernier couru, chacun avec les pronostics du porteur.

Le jeton widget n'est accepté par aucune autre route : `utilisateur_courant` le
refuse avant même d'interroger Supabase. Sans `WIDGET_TOKEN_SECRET`, les trois
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
from app.supabase_client import ErreurSupabase, appeler_fonction, selectionner

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


class PronosticWidget(BaseModel):
    """Un pronostic tel que le widget « Mes pronos » le dessine — une ligne.

    **Le podium arrive en deux lignes**, une par pilote, chacune avec ses points en
    jeu et son verdict (`metier.md` §2) : le widget ne recoupe jamais un total.
    """

    # `obligatoire` (vainqueur, podium) ou `bonus`.
    categorie: str
    # `vainqueur`, `podium` ou `bonus` — le type en base.
    type: str
    marche: str | None = None
    # Le nom du marché selon Unibet (« Vainqueur », « Top 6 »…).
    libelle: str | None = None
    # L'issue choisie : un pilote, une écurie, une tranche.
    choix: str | None = None
    # Ce que le pronostic PEUT rapporter — des points, jamais une cote (règle 3.1).
    points: int | None = None
    # Ce qu'il a rapporté. `None` tant qu'il n'est pas jugé — jamais `0`, qui dirait
    # « raté ».
    points_gagnes: int | None = None
    # `en_attente` | `non_evaluable` | `gagne` | `perdu`.
    statut: str | None = None


class GrandPrixPronosWidget(BaseModel):
    """Un Grand Prix et les pronostics du porteur du jeton.

    Ni slug ni nom traduit : l'app les tire du nom et de la date de course
    (`SlugCircuit`, son seul propriétaire), comme pour toute ligne de la base.
    """

    id: UUID
    nom: str
    date_course: datetime | None = None
    date_qualifications: datetime | None = None
    statut: str
    statut_resultats: str | None = None
    # `aucun` ou `enregistres`.
    etat_pronos: str = "aucun"
    pronostics: list[PronosticWidget] = []
    # Le total marqué sur ce GP, **seulement une fois `termine`** et dès qu'un
    # pronostic est jugé. `None` sinon — jamais `0` avant la course.
    points_gagnes: int | None = None


class PronosWidget(BaseModel):
    # Le premier GP non terminé, départ croissant, un départ inconnu en dernier —
    # la règle de l'accueil. Son départ peut être passé : résultats en attente.
    prochain: GrandPrixPronosWidget | None = None
    # Le dernier GP terminé. Le widget l'affiche « Résultats disponibles » dans les
    # heures qui suivent son départ, puis passe au prochain.
    dernier: GrandPrixPronosWidget | None = None


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


# --------------------------------------------------------------------------- #
#  Mes pronos
# --------------------------------------------------------------------------- #

COLONNES_GP = "id,nom,date_course,date_qualifications,statut,statut_resultats"


def _statut_jambe(gain: int | None, statut_parent: str | None) -> str | None:
    """Le verdict d'un pilote du podium : son propre gain, sinon celui du pronostic."""
    if gain is None:
        return statut_parent
    return "gagne" if gain > 0 else "perdu"


def _lignes(pronostic: dict) -> list[PronosticWidget]:
    """Un pronostic de `pronostics_du_joueur`, en une ligne — deux pour le podium."""
    type_ = pronostic.get("type") or "bonus"
    commun = {
        "categorie": "bonus" if type_ == "bonus" else "obligatoire",
        "type": type_,
        "marche": pronostic.get("marche"),
        "libelle": pronostic.get("libelle"),
    }
    podium = pronostic.get("podium")
    if type_ == "podium" and isinstance(podium, dict):
        statut = pronostic.get("statut_evaluation")
        return [
            PronosticWidget(
                **commun,
                choix=podium.get("nom_1") or podium.get("pilote_1"),
                points=pronostic.get("points"),
                points_gagnes=podium.get("points_gagnes_1"),
                statut=_statut_jambe(podium.get("points_gagnes_1"), statut),
            ),
            PronosticWidget(
                **commun,
                choix=podium.get("nom_2") or podium.get("pilote_2"),
                points=podium.get("points_2"),
                points_gagnes=podium.get("points_gagnes_2"),
                statut=_statut_jambe(podium.get("points_gagnes_2"), statut),
            ),
        ]
    return [
        PronosticWidget(
            **commun,
            choix=pronostic.get("pilote"),
            points=pronostic.get("points"),
            points_gagnes=pronostic.get("points_gagnes"),
            statut=pronostic.get("statut_evaluation"),
        )
    ]


async def _grand_prix_widget(gp: dict, utilisateur: str) -> GrandPrixPronosWidget:
    """Un GP de la base, rapproché des pronostics du porteur.

    La même fonction SQL que les écrans de l'app (`pronostics_du_joueur`) : un
    second rapprochement des cotes aurait pu annoncer d'autres points en jeu.
    """
    pronostics = await appeler_fonction(
        "pronostics_du_joueur", {"p_profil": utilisateur, "p_gp": str(gp["id"])}
    ) or []
    gains = [p["points_gagnes"] for p in pronostics if p.get("points_gagnes") is not None]
    termine = gp.get("statut") == "termine"
    return GrandPrixPronosWidget(
        id=gp["id"],
        nom=gp["nom"],
        date_course=gp.get("date_course"),
        date_qualifications=gp.get("date_qualifications"),
        statut=gp["statut"],
        statut_resultats=gp.get("statut_resultats"),
        etat_pronos="enregistres" if pronostics else "aucun",
        pronostics=[ligne for p in pronostics for ligne in _lignes(p)],
        points_gagnes=sum(gains) if termine and gains else None,
    )


@router.get("/pronos", response_model=PronosWidget)
@journaliser_echecs(DOMAINE, "Pronostics du widget")
async def pronos_widget(
    utilisateur: str = Depends(utilisateur_widget),
    _: None = Depends(exiger_configuration),
) -> PronosWidget:
    """Le prochain Grand Prix et le dernier terminé, avec les pronostics du porteur.

    Lecture seule. L'identifiant vient du jeton widget vérifié, jamais d'un
    paramètre : un porteur ne lit que ses propres pronostics.
    """
    try:
        prochains = await selectionner(
            "grands_prix",
            {
                "select": COLONNES_GP,
                "statut": "in.(a_venir,cotes_figees)",
                "order": "date_course.asc.nullslast",
                "limit": "1",
            },
        )
        derniers = await selectionner(
            "grands_prix",
            {
                "select": COLONNES_GP,
                "statut": "eq.termine",
                "date_course": "not.is.null",
                "order": "date_course.desc",
                "limit": "1",
            },
        )
        return PronosWidget(
            prochain=await _grand_prix_widget(prochains[0], utilisateur) if prochains else None,
            dernier=await _grand_prix_widget(derniers[0], utilisateur) if derniers else None,
        )
    except ErreurSupabase as erreur:
        raise echec_lisible(DOMAINE, "Pronostics du widget", erreur) from erreur
