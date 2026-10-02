"""Actions d'administration déclenchées **depuis l'application**.

Une seule route, `POST /admin/action`, et un seul garde : le **jeton Supabase**
de l'appelant, doublé d'une relecture de `profils.is_admin` en base avec la clé
de service (`deps.exiger_admin`). Aucun secret ne circule, donc aucun secret
n'a besoin d'être connu du navigateur — c'est tout l'objet de la version
`0.64.0`.

### Pourquoi cette route existe, et pourquoi les anciennes restent

Jusqu'ici la section « Administration » du profil appelait directement
`POST /scraper/declencher` en joignant `X-Admin-Secret`, dont la valeur venait
de `VITE_ADMIN_SECRET`. Vite remplace les `VITE_*` par leur valeur littérale
**à la construction** : le secret partait donc en clair dans le bundle public,
lisible par quiconque ouvrait les outils de développement. `decisions.md` §14
le documentait comme une conséquence assumée et nommait le remède ; le voici.

Les routes au secret **ne sont pas supprimées** : elles servent le `curl`, qui
n'a pas de session Supabase, et le banc d'essai `POST /jobs/resultats/{id}/test`
dont le corps n'a aucun sens dans une interface. Le secret ne quitte simplement
plus jamais Railway.

### Une route, un verbe, un corps

`/admin/action` plutôt que trois routes protégées à l'identique : le garde est
la seule chose que ces actions ont en commun, et c'est justement lui qu'on ne
veut écrire qu'une fois. Ajouter une action se fait alors dans `_EXECUTANTS`,
sans nouvelle surface à protéger — et sans risque d'oublier le garde sur la
quatrième.

**Le travail lui-même n'est pas réécrit ici.** `scraper.lancer_scraping` et
`resultats.traiter_grand_prix` sont les fonctions qu'appellent déjà les routes
au secret : un même déclenchement doit avoir le même effet, qu'il vienne d'un
bouton ou d'un `curl`.
"""

import logging
from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.api.deps import exiger_admin
from app.api.journal import journaliser_echecs
from app.api.routes.resultats import RapportJob, traiter_grand_prix
from app.api.routes.scraper import lancer_scraping
from app.jobs.resultats import DEFINITIF_EN_ECHEC, SEUIL_ALERTE_DEFINITIF
from app.scraper.unibet import GRAND_PRIX_AMBIGU
from app.supabase_client import ErreurSupabase, selectionner

router = APIRouter(tags=["admin"])

DOMAINE = "admin"

logger = logging.getLogger("uvicorn.error")


class DemandeAction(BaseModel):
    """Ce que l'administrateur demande, et les réglages de son action.

    Les paramètres de toutes les actions cohabitent dans un seul modèle plat, et
    **chacun a une valeur par défaut** sauf `action` : c'est la règle 3.3 du
    `CLAUDE.md` appliquée dans les deux sens — un frontend déployé avant le
    backend n'envoie pas encore un champ que le backend attendrait, et un
    frontend déployé après n'en envoie pas un que le backend ignorerait en
    échouant.

    `action` est un `Literal` : une valeur inconnue est refusée par FastAPI
    **avant** d'entrer dans le handler, donc avant toute écriture. Le prix à
    payer est un `422` là où un `400` serait plus juste, et il est payé
    volontiers.
    """

    action: Literal["scraper", "resultats"]

    # — action « scraper » —
    # Même défaut que `POST /scraper/declencher` : le figeage suit le succès.
    figer: bool = True

    # — action « resultats » —
    # Nul par défaut, et vérifié dans le handler plutôt que dans le type : un
    # `gp_id` obligatoire au niveau du modèle rendrait `POST /admin/action`
    # impossible pour l'action « scraper », qui n'en a que faire.
    # `forcer` a disparu en 0.78.0 : un client qui l'enverrait encore est
    # ignoré sans erreur (Pydantic écarte les champs inconnus). Le recalcul d'un
    # GP définitif passe par `POST /jobs/resultats/{id}/recalcul`, et par elle
    # seule.
    gp_id: UUID | None = None


class ReponseAction(BaseModel):
    """Le compte rendu, quelle que soit l'action.

    Un modèle par action aurait obligé la route à déclarer une union, et le
    frontend à savoir laquelle il lit. Les champs propres à une action sont donc
    optionnels : `figera` ne veut rien dire pour les résultats, `rapport` ne veut
    rien dire pour le scraper.

    **`statut` distingue « accepté » de « fait », et c'est le seul champ qui
    compte à l'écran.** Le scraper rend `lance` — la tâche part en arrière-plan,
    son compte rendu va dans les logs Railway — là où les résultats rendent
    `traite`, le travail étant terminé quand la réponse arrive. Annoncer « cotes
    mises à jour » sur un `lance` serait une promesse que la réponse ne porte pas.
    """

    action: str = ""
    statut: str = ""
    figera: bool = True
    rapport: RapportJob | None = None


async def _executer_scraper(demande: DemandeAction) -> ReponseAction:
    lancement = await lancer_scraping(demande.figer)
    return ReponseAction(
        action=demande.action, statut=lancement.statut, figera=lancement.figera
    )


async def _executer_resultats(demande: DemandeAction) -> ReponseAction:
    if demande.gp_id is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Cette action demande l'identifiant d'un Grand Prix.",
        )

    rapport = await traiter_grand_prix(demande.gp_id)
    return ReponseAction(action=demande.action, statut="traite", rapport=rapport)


# Le registre des actions. Ajouter une action se fait ici, et le garde de la
# route couvre la nouvelle sans qu'on ait à y penser.
_EXECUTANTS = {
    "scraper": _executer_scraper,
    "resultats": _executer_resultats,
}


@router.post("/admin/action", response_model=ReponseAction)
@journaliser_echecs(DOMAINE, "Action d'administration")
async def executer_action(
    demande: DemandeAction,
    profil_id: str = Depends(exiger_admin),
) -> ReponseAction:
    """Exécute une action d'administration au nom d'un administrateur identifié.

    Le statut rendu est `200` et non `202`, y compris pour le scraper : la
    réponse porte `statut`, qui dit lui-même si le travail est accepté ou fait.
    Un `202` sur une route dont une action sur deux est synchrone mentirait une
    fois sur deux.

    **L'appelant est journalisé, et ce n'est pas décoratif.** Ces actions
    écrivent en base : savoir *qui*
    a appuyé est la seule chose que les logs ne pourront pas reconstituer après
    coup. Le secret partagé, lui, ne disait jamais qui l'avait employé — c'est
    un gain de cette version, au-delà du secret retiré du bundle.
    """
    logger.info(
        "[%s] Action « %s » demandée par le profil %s.",
        DOMAINE,
        demande.action,
        profil_id,
    )
    return await _EXECUTANTS[demande.action](demande)


class AlerteAdmin(BaseModel):
    """Une alerte du profil admin (`alertes_admin`, migration 26).

    Trois types : `libelle_non_reconnu` (une issue pilote ou écurie ne désigne
    aucun engagé au figeage — `marche` et `libelle` la nomment),
    `rattachement_impossible` (OpenF1 muette au figeage) et
    `definitif_en_echec` (`tentatives` échecs consécutifs du calcul définitif).
    Un quatrième depuis la migration 29 : `grand_prix_ambigu` — un Grand Prix
    d'Unibet que le scraper n'a pas su rattacher à une seule ligne. Il peut
    n'avoir **aucun** `gp_id` (rien n'a été créé) : `gp` reprend alors le nom
    d'Unibet, porté par `libelle`.
    Chaque champ a une valeur par défaut (règle 3.3 du `CLAUDE.md`).
    """

    type: str = ""
    gp_id: str | None = None
    gp: str = ""
    marche: str | None = None
    libelle: str | None = None
    tentatives: int = 0
    derniere_erreur: str | None = None
    modifie_le: datetime | None = None


class ReponseAlertes(BaseModel):
    # `False` quand la table manque (migration 26 non appliquée) : l'écran le
    # dit plutôt que d'afficher « aucune alerte ».
    disponible: bool = True
    alertes: list[AlerteAdmin] = []


@router.get("/admin/alertes", response_model=ReponseAlertes)
@journaliser_echecs(DOMAINE, "Chargement des alertes")
async def alertes(profil_id: str = Depends(exiger_admin)) -> ReponseAlertes:
    """Ce que l'administrateur doit voir sans lire les logs Railway.

    Un échec du définitif n'est servi qu'à partir de `SEUIL_ALERTE_DEFINITIF`
    tentatives consécutives : un hoquet d'OpenF1 rattrapé au tour suivant n'a
    rien à faire ici.
    """
    try:
        lignes = await selectionner(
            "alertes_admin",
            {
                "select": "type,gp_id,marche,libelle,tentatives,derniere_erreur,"
                "modifie_le,grands_prix(nom)",
                "order": "modifie_le.desc",
            },
        )
    except ErreurSupabase as erreur:
        # `42P01` / `PGRST205` : table absente, la migration 26 n'est pas jouée.
        if erreur.code in ("42P01", "PGRST205"):
            logger.warning("[%s] Table alertes_admin absente : migration 26 à appliquer.", DOMAINE)
            return ReponseAlertes(disponible=False)
        raise

    servies: list[AlerteAdmin] = []
    for ligne in lignes:
        if ligne.get("type") == DEFINITIF_EN_ECHEC and (
            ligne.get("tentatives") or 0
        ) < SEUIL_ALERTE_DEFINITIF:
            continue
        gp = ligne.get("grands_prix") or {}
        if isinstance(gp, list):
            gp = gp[0] if gp else {}
        servies.append(
            AlerteAdmin(
                **{cle: valeur for cle, valeur in ligne.items() if cle != "grands_prix"},
                gp=str(
                    gp.get("nom")
                    or (ligne.get("libelle") if ligne.get("type") == GRAND_PRIX_AMBIGU else "")
                    or ""
                ),
            )
        )
    return ReponseAlertes(alertes=servies)
