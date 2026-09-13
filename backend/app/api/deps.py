"""Dépendances communes aux routes protégées."""

import logging
import secrets

from fastapi import Depends, Header, HTTPException, status

from app.config import get_settings
from app.supabase_client import ErreurSupabase, identifiant_du_jeton, selectionner

# Même logger que les routes : sous Railway, seul `uvicorn.error` a un handler.
logger = logging.getLogger("uvicorn.error")

SERVICE_INDISPONIBLE = (
    "Le serveur n'est pas relié à sa base de données. "
    "Les variables SUPABASE_URL, SUPABASE_ANON_KEY et "
    "SUPABASE_SERVICE_ROLE_KEY sont absentes."
)


def exiger_configuration() -> None:
    """Sans clés Supabase, mieux vaut un message explicite qu'une erreur 500."""
    if not get_settings().supabase_configure:
        # Déjà signalé au démarrage, mais un log daté du refus dit quelle
        # requête a échoué et à quel moment — l'avertissement de démarrage est
        # loin dans l'historique Railway au moment où le problème se voit.
        logger.error(
            "Appel refusé faute de configuration Supabase : %s", SERVICE_INDISPONIBLE
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=SERVICE_INDISPONIBLE,
        )


async def utilisateur_courant(
    authorization: str | None = Header(default=None),
    _: None = Depends(exiger_configuration),
) -> str:
    """Identifiant Supabase de l'appelant, extrait de l'en-tête Authorization.

    Le jeton n'est jamais cru sur parole : il est présenté à Supabase, qui seul
    peut dire s'il est valide et à qui il appartient. Toute route qui dépend de
    cette fonction est donc fermée aux appels anonymes.
    """
    schema, _, jeton = (authorization or "").partition(" ")

    if schema.lower() != "bearer" or not jeton.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentification requise.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        identifiant = await identifiant_du_jeton(jeton.strip())
    except ErreurSupabase as erreur:
        # Cette dépendance s'exécute AVANT le handler : son échec échappe à
        # l'enrobage de `journaliser_echecs`. Sans ce log, une panne du service
        # d'authentification resterait la panne la moins visible de toutes,
        # alors qu'elle bloque les quatre routes à la fois.
        logger.exception(
            "[auth] Validation du jeton impossible — %s (statut %s)",
            erreur.message,
            erreur.statut,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=erreur.message
        ) from erreur
    except Exception as erreur:  # noqa: BLE001 — sinon la panne sort en 500 muet
        logger.exception("[auth] Erreur inattendue à la validation du jeton")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Validation du jeton — {type(erreur).__name__}: {erreur}",
        ) from erreur

    if not identifiant:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expirée. Reconnecte-toi.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return identifiant


async def utilisateur_optionnel(
    authorization: str | None = Header(default=None),
) -> str | None:
    """Identifie l'appelant s'il présente un jeton, sans l'exiger.

    Sert aux routes **mixtes** : le résultat d'une course est public, la liste
    des pronostics de ses membres ne l'est pas. Une seule route sert les deux,
    et c'est son propre code qui exige une identité au moment où il en a besoin.

    Un en-tête absent rend `None`. Un en-tête **présent mais invalide** rend un
    `401` comme `utilisateur_courant` : accepter en silence un jeton expiré
    reviendrait à servir la partie publique à quelqu'un qui se croit connecté,
    et à lui cacher ses championnats sans rien lui dire.
    """
    if not (authorization or "").strip():
        return None

    exiger_configuration()
    return await utilisateur_courant(authorization=authorization)


async def exiger_admin(
    profil_id: str = Depends(utilisateur_courant),
) -> str:
    """Identifiant de l'appelant, à la condition qu'il soit administrateur.

    C'est le garde des routes d'administration appelées **depuis l'application**,
    et il remplace le secret partagé pour ce chemin-là (version `0.64.0`) : un
    secret inliné par Vite dans le bundle public n'en était plus un.
    `decisions.md` §14 annonçait cette route comme « la bonne réponse le jour où
    ce sera nécessaire » ; c'est elle.

    Trois points à ne jamais défaire :

    - **le drapeau est relu en base, jamais lu dans le jeton.** Le jeton dit
      *qui* appelle et rien d'autre ; ce qu'il porte en `app_metadata` se
      négocie à l'inscription et se recopie dans une requête. La lecture passe
      par la clé de service, donc hors RLS, donc sur la valeur réelle de la
      colonne — pas sur ce qu'une politique laisse voir à l'appelant ;
    - **le doute refuse, il n'accorde jamais.** Ligne absente, colonne absente,
      base non migrée : tous ces cas rendent `403`. C'est le même sens du doute
      que `chargerEstAdmin` côté frontend, où il referme la section ;
    - **une panne de lecture rend `503`, jamais `403`.** « Tu n'es pas
      administrateur » serait faux, et enverrait chercher la cause du côté des
      droits alors que Supabase est simplement injoignable.

    > **Ce garde vaut ce que vaut le droit de colonne sur `is_admin`.** La
    > politique « Chacun modifie son profil » porte sur la LIGNE et est aveugle
    > sur la COLONNE : sans la migration `20260827_audit_rls.sql` §2, qui retire
    > `update` de table à `authenticated` pour le redonner colonne par colonne,
    > n'importe quel membre écrit son propre `is_admin` depuis les outils de
    > développement et franchit cette porte. **La migration n'est pas un
    > complément de cette route, elle en est la moitié.**
    """
    try:
        lignes = await selectionner(
            "profils",
            {"select": "is_admin", "id": f"eq.{profil_id}", "limit": "1"},
        )
    except ErreurSupabase as erreur:
        # Comme dans `utilisateur_courant` : une dépendance s'exécute AVANT le
        # handler, son échec échappe donc à l'enrobage de `journaliser_echecs`.
        logger.exception(
            "[admin] Lecture du drapeau is_admin impossible — %s (statut %s)",
            erreur.message,
            erreur.statut,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Vérification des droits impossible. Réessaie dans un instant.",
        ) from erreur
    except Exception as erreur:  # noqa: BLE001 — sinon la panne sort en 500 muet
        logger.exception("[admin] Erreur inattendue à la lecture de is_admin")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Vérification des droits impossible. Réessaie dans un instant.",
        ) from erreur

    # `is not True` et non `not …` : une colonne absente rend `None`, une ligne
    # absente rend une liste vide, et les deux valent « pas administrateur »
    # sans que personne ait à s'en souvenir.
    if not lignes or lignes[0].get("is_admin") is not True:
        logger.warning(
            "[admin] Action refusée : le profil %s n'est pas administrateur.",
            profil_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cette action est réservée aux administrateurs.",
        )

    return profil_id


def exiger_secret(fourni: str | None, domaine: str) -> None:
    """Refuse l'appel si l'en-tête `X-Admin-Secret` ne correspond pas.

    Partagé depuis l'étape 6 entre le déclenchement du scraper et celui du job
    de résultats. Deux points à ne jamais défaire :

    - la comparaison passe par `secrets.compare_digest`, **à temps constant**.
      Un `==` sur des chaînes s'arrête au premier caractère qui diffère, et le
      temps de réponse laisse alors deviner le secret caractère par caractère ;
    - **secret non configuré ferme la route**, il ne l'ouvre pas. S'ouvrir à
      tous parce qu'aucune valeur n'est définie serait exactement le mauvais
      sens du défaut — ces routes écrivent en base.
    """
    parametres = get_settings()

    if not parametres.admin_configure:
        logger.error(
            "[%s] Déclenchement refusé : ADMIN_SECRET n'est pas défini sur le serveur.",
            domaine,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Le déclenchement n'est pas configuré (ADMIN_SECRET absent).",
        )

    if not fourni or not secrets.compare_digest(
        fourni.strip(), parametres.admin_secret.strip()
    ):
        logger.warning("[%s] Déclenchement refusé : secret invalide ou absent.", domaine)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Secret d'administration invalide ou absent.",
        )
