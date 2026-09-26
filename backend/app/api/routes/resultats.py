"""Résultats d'un Grand Prix — consultation et déclenchement manuel du job.

Deux routes, deux régimes d'accès, et la frontière entre les deux n'est pas un
détail :

- `GET /grands-prix/{id}/resultats` est **publique pour le classement de la
  course** — un résultat de F1 est public partout ailleurs, et l'écran doit
  pouvoir s'afficher sans session. Elle sert **en plus** les pronostics des
  membres d'un championnat, et cette partie-là exige un jeton **et**
  l'appartenance au championnat demandé.
- `POST /jobs/resultats/{id}` écrit en base (calcul provisoire). Elle est
  fermée par le secret partagé `X-Admin-Secret`, comme `POST /scraper/declencher`.
- `POST /jobs/resultats/{id}/recalcul` rejuge un GP **définitif**, même secret.
  C'est la seule écriture qui réécrit des verdicts hors du définitif de J+1.
- `POST /jobs/resultats/{id}/test` **n'écrit rien du tout** : elle rejoue le
  calcul sur des résultats fictifs fournis dans le corps de la requête. Même
  secret, mais aucun effet de bord — c'est un banc d'essai, pas un job.

Les valeurs servies sont toujours des **points** (règle 4.1). `points_fia` fait
exception et porte son nom pour cette raison : ce sont les points du
championnat du monde (25, 18, 15…), affichés comme tels, jamais les points de
l'application.
"""

import logging
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, model_validator

from app.api.deps import (
    exiger_configuration,
    exiger_secret,
    utilisateur_optionnel,
)
from app.api.journal import journaliser_echecs
from app.api.routes.pronostics import MembrePronostics, exiger_membre
from app.calcul import points as calcul
from app.calcul import pilotes as grille
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
    # `provisoire` jusqu'au calcul définitif de J+1, puis `definitif` ; nul tant
    # que la course n'a pas de résultats. Défaut pour une base non migrée.
    statut_resultats: str | None = None


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
    # `provisoire` après le calcul de l'arrivée, `definitif` après J+1 ou un
    # recalcul. Valeurs par défaut, comme tout nouveau champ de modèle (règle 3.3).
    statut_resultats: str | None = None
    # Verdicts réellement changés par le définitif ou le recalcul. Zéro sur le
    # calcul provisoire, qui n'écrit que des `NULL`.
    modifies: int = 0
    attribues: int = 0
    restants: int = 0
    en_attente: list[str] = []
    # Pronostics dont le marché n'a aucun évaluateur (statut `non_evaluable`).
    non_evaluables: list[str] = []
    erreur: str | None = None


# --------------------------------------------------------------------------- #
#  Modèles du banc d'essai
# --------------------------------------------------------------------------- #


class LigneFictive(BaseModel):
    """Une ligne de `session_result` fabriquée à la main.

    Les champs reprennent ceux de la section 3.2, avec les mêmes pièges assumés :
    `position` peut être nulle (abandon non classé) **sans** que `dnf` le soit,
    et l'inverse est vrai aussi — un pilote peut abandonner et rester classé.

    Seul `driver_number` est obligatoire : c'est la seule chose sans laquelle la
    ligne ne désigne personne. Tout le reste a le défaut le plus neutre.

    `extra="allow"` laisse coller une réponse OpenF1 réelle sans l'élaguer : les
    champs non déclarés (`duration`, `meeting_key`…) traversent tels quels
    jusqu'au calcul, qui les ignore ou non selon les validateurs.
    """

    model_config = ConfigDict(extra="allow")

    driver_number: int
    position: int | None = None
    dnf: bool = False
    dns: bool = False
    dsq: bool = False
    points: float = 0
    number_of_laps: int = 0
    # Type mixte assumé (section 3.2) : nombre, chaîne « +1 LAP » ou nul. Aucun
    # validateur ne le lit aujourd'hui, il est accepté pour que le corps puisse
    # être copié tel quel depuis OpenF1.
    gap_to_leader: float | str | None = None


class ResultatsFictifs(BaseModel):
    """Le corps de la requête : un classement fictif, et de quoi l'entourer.

    **Deux formes sont acceptées.** Le tableau nu de `session_result` — la forme
    documentée, celle qu'on écrit à la main pour tester un vainqueur et un
    podium — et un objet qui permet en plus de fournir `race_control` et `laps`.
    La seconde n'est pas un supplément gratuit : les marchés safety car, drapeau
    rouge et meilleur tour sont les seuls que le CLAUDE.md annonce sans qu'aucun
    vrai libellé Unibet ne les ait jamais confrontés, et sans ces deux tableaux
    ils resteraient les seuls impossibles à essayer avant la course.
    """

    session_result: list[LigneFictive]
    # Messages de direction de course, au format `/race_control` :
    # `{"category": "SafetyCar", "message": "SAFETY CAR DEPLOYED"}`, ou
    # `{"flag": "RED"}`.
    race_control: list[dict] = []
    # Meilleurs tours, au format déjà réduit par `openf1._meilleurs_tours` :
    # `{"driver_number": 12, "lap_duration": 71.2}`.
    laps: list[dict] = []

    @model_validator(mode="before")
    @classmethod
    def _accepter_un_tableau_nu(cls, valeur):
        """Enveloppe le tableau nu documenté dans la forme complète."""
        if isinstance(valeur, list):
            return {"session_result": valeur}
        return valeur


class PronosticTeste(BaseModel):
    """Le verdict du calcul sur un pronostic, sans qu'il ait été écrit nulle part."""

    pronostic_id: UUID
    profil_id: UUID
    type: str
    id_outcome_unibet: str
    # Renseignés depuis les cotes figées du GP. Nuls si l'issue n'y est plus.
    marche: str | None = None
    pilote: str | None = None
    # Ce que le pronostic POUVAIT rapporter : la cote figée (règle 4.1).
    points: int | None = None
    # Ce qu'il rapporte sur ces résultats fictifs. `null` ne veut pas dire zéro :
    # il veut dire « le calcul n'a pas su juger », et `raison` dit pourquoi.
    points_gagnes: int | None = None
    reussi: bool | None = None
    # `gagne`, `perdu`, `non_evaluable` (aucun évaluateur) ou `en_attente`
    # (donnée manquante) — le statut que le vrai job écrirait.
    statut: str | None = None
    detail: str | None = None
    raison: str | None = None
    # Ce que la base contient réellement, laissé intact par cet appel. C'est la
    # preuve vérifiable que le banc d'essai n'a rien écrit : rejouer la requête
    # rend toujours la même valeur.
    points_en_base: int | None = None


class ResumeCourse(BaseModel):
    """Ce que le calcul a compris des résultats fictifs.

    Sans ce résumé, un safety car mal orthographié dans le corps de la requête
    donnerait des pronostics ratés sans qu'on sache si c'est le pronostic ou la
    donnée d'essai qui est en cause.
    """

    vainqueur: str | None = None
    pilotes_classes: int = 0
    abandons: int = 0
    safety_car: bool = False
    virtual_safety_car: bool = False
    drapeau_rouge: bool = False
    meilleur_tour: str | None = None


class RapportTest(BaseModel):
    gp: str
    gp_id: UUID
    # Toujours `false`, et le champ existe pour le dire à l'appelant plutôt que
    # de le lui faire déduire de la documentation.
    ecrit_en_base: bool = False
    saison_grille: int = grille.SAISON
    # Numéros présents dans le corps mais absents de `calcul/pilotes.py` : ils
    # ne seront rapprochés d'aucun libellé Unibet. C'est le premier symptôme
    # d'une table de pilotes périmée.
    numeros_inconnus: list[int] = []
    course: ResumeCourse
    pronostics: list[PronosticTeste] = []
    notes: int = 0
    reussis: int = 0
    non_valides: int = 0
    total_points: int = 0


# --------------------------------------------------------------------------- #
#  Consultation
# --------------------------------------------------------------------------- #


async def _grand_prix(gp_id: UUID) -> dict:
    lignes = await selectionner(
        "grands_prix",
        # `*` : `statut_resultats` en fait partie sur une base migrée, et son
        # absence ne fait pas échouer la route sur une base qui ne l'est pas.
        {"id": f"eq.{gp_id}", "select": "*", "limit": "1"},
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


def _traduire(erreur: Exception) -> HTTPException:
    """Les refus du job, traduits en codes HTTP. **Un seul propriétaire** pour
    les deux routes au secret et l'action d'administration.

    `ResultatsIndisponibles` vaut `425 Too Early`, pas `422` : ce n'est pas une
    panne, la course n'a simplement pas encore de classement publié. Les deux
    refus de statut valent `409` : la requête est juste, c'est l'état du GP qui
    l'empêche.
    """
    if isinstance(erreur, ValueError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(erreur))
    if isinstance(erreur, ResultatsIndisponibles):
        return HTTPException(
            status_code=status.HTTP_425_TOO_EARLY,
            detail=f"Les résultats ne sont pas encore publiés. {erreur}",
        )
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(erreur))


_REFUS = (
    ValueError,
    ResultatsIndisponibles,
    job.GrandPrixDefinitif,
    job.GrandPrixNonDefinitif,
)


async def traiter_grand_prix(gp_id: UUID) -> RapportJob:
    """Calcul provisoire d'un Grand Prix, et son compte rendu. **Le garde est
    chez l'appelant.**

    Deux routes mènent ici — `POST /jobs/resultats/{id}` fermée par
    `X-Admin-Secret` pour le `curl`, et `POST /admin/action` fermée par le jeton
    du membre pour l'application. Aucune identité n'est vérifiée ici : chaque
    route pose son garde avant.
    """
    exiger_configuration()
    try:
        rapport = await job.declencher_maintenant(str(gp_id))
    except _REFUS as erreur:
        raise _traduire(erreur) from erreur
    return RapportJob(**rapport)


@router.post("/jobs/resultats/{gp_id}", response_model=RapportJob)
@journaliser_echecs(DOMAINE, "Déclenchement du job de résultats")
async def declencher_resultats(
    gp_id: UUID,
    x_admin_secret: str | None = Header(default=None),
) -> RapportJob:
    """Calcul **provisoire** d'un Grand Prix à la demande : résultats, points,
    clôture.

    La réponse est **synchrone** et porte le compte rendu complet : savoir
    combien de pronostics ont été notés, et lesquels sont restés en attente, est
    tout l'intérêt de l'appel.

    Elle ignore la fenêtre horaire de la règle 4.3, jamais l'idempotence : un
    pronostic déjà noté ne l'est pas une seconde fois. Sur un GP **définitif**,
    elle répond `409` et renvoie vers `/recalcul`.

    `?forcer=true` n'existe plus depuis la `0.78.0` : il est remplacé par
    `/recalcul`, transactionnel.
    """
    exiger_secret(x_admin_secret, DOMAINE)

    # Le secret d'abord, la configuration ensuite : répondre « Supabase n'est
    # pas configuré » à qui n'a pas donné le bon secret lui apprendrait quelque
    # chose sur l'état du serveur pour rien. Même ordre qu'au scraper.
    return await traiter_grand_prix(gp_id)


@router.post("/jobs/resultats/{gp_id}/recalcul", response_model=RapportJob)
@journaliser_echecs(DOMAINE, "Recalcul d'un Grand Prix définitif")
async def recalculer_resultats(
    gp_id: UUID,
    relire: bool = False,
    x_admin_secret: str | None = Header(default=None),
) -> RapportJob:
    """Rejuge **tous** les pronostics d'un GP définitif. Seule route qui le fasse.

    Après le calcul définitif de J+1, plus rien ne recalcule un GP tout seul.
    Cette route existe pour les deux cas où il le faut :

    - un évaluateur corrigé après coup — défaut, `relire=false` : le calcul
      rejoue le `donnees_brutes` conservé, sans appel à OpenF1 ;
    - une décision tardive des commissaires — `relire=true` : OpenF1 est relue
      et `resultats_gp` remplacé.

    **L'écriture est transactionnelle** (`remplacer_verdicts`) : résultats,
    verdicts, podiums et statut changent d'un bloc, ou pas du tout. Jamais un GP
    « tout en attente » entre deux appels, le défaut de l'ancien
    `?forcer=true` (risque R5 de l'audit).

    `409` sur un GP qui n'est pas encore définitif : sa boucle s'en charge.
    """
    exiger_secret(x_admin_secret, DOMAINE)
    exiger_configuration()
    try:
        rapport = await job.recalculer(str(gp_id), relire=relire)
    except _REFUS as erreur:
        raise _traduire(erreur) from erreur
    return RapportJob(**rapport)


# --------------------------------------------------------------------------- #
#  Banc d'essai — résultats fictifs, aucune écriture
# --------------------------------------------------------------------------- #


def _lire_le_pari(pronostic: dict, cotes: dict[str, dict]):
    """Décrit ce sur quoi porte un pronostic : marché, libellé, points possibles.

    Un podium est le seul cas qui demande un traitement à part, et pour la même
    raison qu'au calcul : il porte **deux** pilotes, il s'affiche « A + B », et
    ce qu'il peut rapporter est la **somme** des deux cotes (règle tranchée à
    l'étape 6, ordre-indépendante). Lire la seule cote de `pilote_1` afficherait
    ici un potentiel deux fois trop faible.

    Les points rendus sont un potentiel, jamais un gain : c'est `points` dans la
    réponse, à ne pas confondre avec `points_gagnes`.
    """
    cote = cotes.get(str(pronostic.get("id_outcome_unibet") or ""))
    marche = str((cote or {}).get("marche") or "")

    if pronostic.get("type") != "podium":
        return marche, str((cote or {}).get("pilote") or ""), (cote or {}).get("valeur")

    # PostgREST rend cette relation tantôt en objet, tantôt en tableau d'un
    # élément selon la version : les deux formes sont acceptées, comme au calcul.
    detail = pronostic.get("pronostic_podium") or {}
    if isinstance(detail, list):
        detail = detail[0] if detail else {}

    deux = [cotes.get(str(detail.get(champ) or "")) for champ in ("pilote_1", "pilote_2")]
    libelle = " + ".join(str((une or {}).get("pilote") or "?") for une in deux)
    total = (
        sum(int(une["valeur"]) for une in deux)
        if all(une and une.get("valeur") is not None for une in deux)
        else None
    )
    return marche, libelle, total


@router.post("/jobs/resultats/{gp_id}/test", response_model=RapportTest)
@journaliser_echecs(DOMAINE, "Banc d'essai du calcul des points")
async def tester_resultats(
    gp_id: UUID,
    corps: ResultatsFictifs,
    x_admin_secret: str | None = Header(default=None),
) -> RapportTest:
    """Rejoue le calcul des points sur des résultats fictifs, **sans rien écrire**.

    Le GP des Pays-Bas se court le 23 août : le calcul doit être validé avant, et
    non découvert après. Cette route sert exactement à cela — elle prend les
    pronostics **réels** déjà saisis en base, les confronte à un classement
    fabriqué à la main, et rend le verdict ligne à ligne.

    **Trois écritures du vrai job sont volontairement absentes**, et c'est toute
    la différence entre les deux routes :

    - rien n'est enregistré dans `resultats_gp` — le classement fictif ne doit
      jamais devenir la vérité de ce Grand Prix, ni empêcher la vraie
      récupération OpenF1 le jour venu (l'unicité de `gp_id` la bloquerait) ;
    - le statut du GP n'est pas passé à `termine` — il sortirait de la
      surveillance du scheduler et la course ne serait jamais notée ;
    - aucun `points_gagnes` n'est attribué — `attribuer_points` n'écrit que les
      NULL, un essai les remplirait donc **définitivement** avec des valeurs
      inventées, que le vrai job ne corrigerait plus jamais.

    C'est ce qui rend l'essai reproductible : on peut le rejouer autant de fois
    qu'on veut, avec des classements différents, sans jamais polluer les données.
    `points_en_base` le prouve dans la réponse — il ne bouge pas.

    **Tous** les pronostics du GP sont évalués, y compris ceux qui auraient déjà
    des points. Le filtre `points_gagnes is null` du vrai job est un mécanisme
    d'idempotence, pas une règle de calcul : ici il masquerait précisément les
    lignes qu'on veut vérifier.

    Le jugement lui-même n'est pas réécrit : c'est `calcul.points_du_pronostic`
    qui est appelé, la fonction sur laquelle `calculer()` boucle dans le vrai
    job. Ce qui est validé ici est donc bien ce qui tournera dimanche.
    """
    exiger_secret(x_admin_secret, DOMAINE)
    exiger_configuration()

    if not corps.session_result:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                "Aucune ligne de résultat fournie. Le corps attend un tableau "
                "`session_result`, ou un objet le contenant."
            ),
        )

    gp = await _grand_prix(gp_id)

    # Le classement fictif prend la place de celui d'OpenF1, et l'index des
    # pilotes vient de `calcul/pilotes.py` au lieu de `/drivers` : c'est la seule
    # substitution du banc d'essai. Tout ce qui suit est le chemin normal.
    donnees = {
        "source": "test",
        "session_result": [ligne.model_dump() for ligne in corps.session_result],
        "race_control": corps.race_control,
        "laps": corps.laps,
        "pilotes": grille.index_pilotes(),
    }

    connus = set(grille.PAR_NUMERO)
    numeros_inconnus = sorted(
        {ligne.driver_number for ligne in corps.session_result} - connus
    )
    if numeros_inconnus:
        logger.warning(
            "[%s] Banc d'essai : %d numéro(s) absent(s) de la grille %d (%s). "
            "Aucun libellé Unibet ne leur sera rapproché.",
            DOMAINE,
            len(numeros_inconnus),
            grille.SAISON,
            ", ".join(str(numero) for numero in numeros_inconnus),
        )

    pronostics = await selectionner(
        "pronostics",
        {
            "gp_id": f"eq.{gp_id}",
            "select": (
                "id,profil_id,type,id_outcome_unibet,points_gagnes,"
                "pronostic_podium(pilote_1,pilote_2)"
            ),
            "order": "cree_le.asc",
        },
    )
    # Les mêmes cotes figées que le vrai job, lues par la même fonction : ce sont
    # elles qui portent les points, jamais une cote recalculée (règle 4.3).
    cotes = await job.cotes_du_gp(str(gp_id))

    course = calcul.analyser(donnees)

    lignes: list[PronosticTeste] = []
    for pronostic in pronostics:
        attribution, raison = calcul.points_du_pronostic(pronostic, cotes, course)
        marche, pilote, potentiel = _lire_le_pari(pronostic, cotes)

        lignes.append(
            PronosticTeste(
                pronostic_id=pronostic["id"],
                profil_id=pronostic["profil_id"],
                type=str(pronostic.get("type") or ""),
                id_outcome_unibet=str(pronostic.get("id_outcome_unibet") or ""),
                marche=marche or None,
                pilote=pilote or None,
                points=potentiel,
                points_gagnes=attribution.points if attribution else None,
                reussi=(
                    attribution.reussi
                    if attribution and attribution.points is not None
                    else None
                ),
                statut=attribution.statut if attribution else calcul.EN_ATTENTE,
                detail=attribution.detail if attribution else None,
                raison=raison or None,
                points_en_base=pronostic.get("points_gagnes"),
            )
        )

    tete = course.par_position(1)
    resume = ResumeCourse(
        vainqueur=(course.pilotes.get(tete.numero) or {}).get("nom") if tete else None,
        pilotes_classes=sum(1 for ligne in course.lignes.values() if ligne.classe),
        abandons=sum(1 for ligne in course.lignes.values() if ligne.abandon),
        safety_car=course.safety_car,
        virtual_safety_car=course.virtual_safety_car,
        drapeau_rouge=course.drapeau_rouge,
        meilleur_tour=(
            (course.pilotes.get(course.meilleur_tour) or {}).get("nom")
            if course.meilleur_tour is not None
            else None
        ),
    )

    notes = [ligne for ligne in lignes if ligne.points_gagnes is not None]
    rapport = RapportTest(
        gp=str(gp.get("nom") or gp_id),
        gp_id=gp_id,
        numeros_inconnus=numeros_inconnus,
        course=resume,
        pronostics=lignes,
        notes=len(notes),
        reussis=sum(1 for ligne in notes if ligne.reussi),
        non_valides=len(lignes) - len(notes),
        total_points=sum(ligne.points_gagnes or 0 for ligne in notes),
    )

    logger.info(
        "[%s] Banc d'essai %s — %d pronostic(s) : %d noté(s) dont %d réussi(s), "
        "%d non validé(s). Aucune écriture en base.",
        DOMAINE,
        rapport.gp,
        len(lignes),
        rapport.notes,
        rapport.reussis,
        rapport.non_valides,
    )
    return rapport
