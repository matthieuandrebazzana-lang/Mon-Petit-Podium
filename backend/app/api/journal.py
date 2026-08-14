"""Journalisation des pannes des routes, et traduction en réponse lisible.

Mis en commun à l'étape 5. Le mécanisme date de la version `0.3.1`, où il
répondait à un constat précis : les routes `/championnats` renvoyaient `502`
sans qu'aucune ligne n'apparaisse dans les logs Railway, et le diagnostic — clé
absente, table non créée, Supabase injoignable — se faisait à l'aveugle.

Il en existait deux copies (`routes/championnats.py` et `routes/scraper.py`) au
moment d'en écrire une troisième pour les pronostics. Elles sont réunies ici :
le comportement est celui de la version `0.3.1`, seul le préfixe des logs
change d'un domaine à l'autre.
"""

import logging
from functools import wraps

from fastapi import HTTPException, status

from app.supabase_client import ErreurSupabase

# Sous Railway, `uvicorn.error` est le SEUL logger doté d'un handler. Un
# `logging.getLogger(__name__)` écrirait dans le vide — c'est exactement l'état
# que ce module corrige. Ne pas le remplacer.
logger = logging.getLogger("uvicorn.error")


def technique(erreur: BaseException) -> str:
    """Décrit une exception en une ligne, sans rien perdre de ce qui l'identifie.

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


def echec_lisible(domaine: str, contexte: str, erreur: BaseException) -> HTTPException:
    """Journalise une panne avec sa trace, et rend un message français à l'appelant.

    **La cause technique ne quitte plus le serveur** (étape 9). Jusqu'à la
    version `0.8.1`, le `detail` portait le message Supabase, son code
    PostgreSQL et son statut HTTP jusque dans l'interface — délibérément, le
    temps de la mise en service, et le CLAUDE.md l'inscrivait au « Reste à
    faire ». Une chaîne comme
    `relation "public.cotes" does not exist · code 42P01` n'apprend rien à un
    joueur et lui fait croire que l'application est cassée pour de bon.

    Ce que l'appelant reçoit désormais : le **contexte en français** (« Le
    classement n'a pas pu être chargé »), et l'invitation à réessayer. Ce que
    les logs Railway reçoivent : exactement ce qu'ils recevaient avant, message,
    code, statut et trace complète. Rien n'est perdu au diagnostic — la seule
    chose qui change, c'est où on le lit.

    Le `422` est conservé, et il reste un choix de transport, pas de sémantique :
    il ne se confond ni avec le `503` d'une configuration absente, ni avec le
    `500` d'un plantage non capturé, ni avec les statuts métier (`404`, `409`,
    `423`) que le décorateur laisse passer intacts.

    À appeler **depuis un bloc `except`** : `logger.exception` n'a de trace à
    joindre que là.
    """
    logger.exception("[%s] %s — %s", domaine, contexte, technique(erreur))
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        # Formulé pour rester grammatical quel que soit le contexte, qui est un
        # groupe nominal (« Chargement du classement », « Adhésion au
        # championnat ») : le deux-points évite d'avoir à lui accorder un verbe.
        detail=f"{contexte} : impossible pour le moment. Réessaie dans quelques instants.",
    )


def journaliser_echecs(domaine: str, contexte: str):
    """Enrobe un handler pour qu'aucune exception ne sorte sans être journalisée.

    Les `HTTPException` traversent intactes : ce sont les réponses voulues par
    la logique métier (`404` GP inconnu, `409` déjà membre, `423` pronostics
    fermés, `503` sans clés Supabase), pas des pannes. Tout le reste — panne
    réseau, table absente, clé manquante dans une réponse, bug — ressort en
    clair, avec sa trace dans les logs.

    `functools.wraps` n'est pas cosmétique : FastAPI lit la signature du handler
    pour construire ses dépendances et ses paramètres, et `inspect.signature`
    suit `__wrapped__`. Sans lui, la route recevrait `(*args, **kwargs)` et
    perdrait `Depends(utilisateur_courant)` comme son en-tête `X-Admin-Secret` :
    les routes protégées s'ouvriraient aux appels anonymes. Un contrôle du jeu
    de tests couvre précisément ce cas.
    """

    def decorateur(handler):
        @wraps(handler)
        async def enveloppe(*args, **kwargs):
            try:
                return await handler(*args, **kwargs)
            except HTTPException:
                raise
            except Exception as erreur:  # noqa: BLE001 — c'est tout l'objet
                raise echec_lisible(domaine, contexte, erreur) from erreur

        return enveloppe

    return decorateur
