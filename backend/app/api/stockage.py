"""Vérification des URL de photos — le seul juge, pour les deux domaines.

Deux colonnes portent une photo depuis la migration `20260821180000` :
`profils.avatar_url` et `championnats.photo_url`. Les deux reçoivent une URL du
client, et les deux se retrouvent dans un attribut `src` **sur l'écran des
autres membres**. C'est ce dernier point qui rend la vérification nécessaire.

> ### Pourquoi une URL quelconque ne peut pas être acceptée
>
> `PATCH /profils/moi` ne prend l'identité que du jeton (règle 3.4 du
> CLAUDE.md), donc personne ne peut peindre la photo de quelqu'un d'autre. Mais
> la SIENNE s'affiche chez tout le monde : au classement, sur la piste, au résumé
> d'un Grand Prix. Une URL libre serait donc un pixel espion posé chez les autres
> joueurs — chaque affichage révélant leur adresse IP et leur `User-Agent` au
> serveur choisi par l'auteur de l'URL. L'app est ouverte au public (CLAUDE.md
> §1) ; ce n'est pas une hypothèse d'école.
>
> La contrainte `check` en base ne vérifie que la FORME (`https://…`), et c'est
> volontaire : y coder l'URL du projet Supabase figerait la base sur un projet et
> une restauration ailleurs refuserait toutes les photos existantes
> (`supabase/migrations/20260821180000` §2). Le rattachement au projet se juge
> donc ici, où `SUPABASE_URL` est connue.

**Une seule question, un seul propriétaire.** Les deux domaines appellent
`url_de_photo_valide` ; deux vérifications écrites séparément auraient divergé au
premier ajustement, et celle qu'on aurait oublié de resserrer serait devenue la
porte d'entrée.
"""

from fastapi import HTTPException, status

from app.config import get_settings

# Les deux compartiments créés par la migration `20260821180000`. Écrits ici et
# nulle part ailleurs : le chemin d'une photo est une question de stockage, pas
# une question de profil ni de championnat.
COMPARTIMENT_AVATARS = "avatars"
COMPARTIMENT_CHAMPIONNATS = "championnats"

# Préfixe d'une URL publique Supabase Storage. Le chemin est fixé par Supabase,
# pas par nous : `/storage/v1/object/public/{compartiment}/{chemin}`.
CHEMIN_PUBLIC = "/storage/v1/object/public/"

# Plafond, doublé par la contrainte `*_url_format` en base. Un chemin
# `{uuid}/avatar.webp` sous l'URL d'un projet Supabase pèse moins de cent
# cinquante caractères ; 512 laisse de la marge sans laisser passer une charge.
LONGUEUR_MAXIMALE = 512


def _prefixe_attendu(compartiment: str) -> str:
    """Le début que doit avoir toute URL de photo de ce compartiment."""
    return f"{get_settings().supabase_url.rstrip('/')}{CHEMIN_PUBLIC}{compartiment}/"


def url_de_photo_valide(valeur: str, compartiment: str, quoi: str) -> str:
    """Normalise et vérifie une URL de photo, ou refuse en français.

    Trois conditions, et il faut les trois :

    1. l'URL commence par celle du **projet Supabase configuré** — c'est ce qui
       interdit d'enregistrer l'adresse d'un serveur tiers ;
    2. elle désigne le **bon compartiment** — un avatar ne s'enregistre pas
       depuis le compartiment des championnats, ni l'inverse ;
    3. elle porte bien un **chemin** après le compartiment, et tient sous le
       plafond.

    **Sans `SUPABASE_URL`, tout est refusé** plutôt que tout accepté. Le service
    démarre sans les clés Supabase pour garder `/health` joignable
    (`docs/architecture.md` §5) ; dans cet état, une vérification qui laisserait
    passer serait exactement l'inverse du sens du doute voulu ici.
    """
    propre = valeur.strip()

    if not get_settings().supabase_url.strip():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Le stockage des photos n'est pas configuré sur le serveur.",
        )

    prefixe = _prefixe_attendu(compartiment)
    refus = HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail=f"Cette adresse n'est pas celle d'{quoi} déposée sur l'application.",
    )

    if len(propre) > LONGUEUR_MAXIMALE:
        raise refus
    if not propre.startswith(prefixe):
        raise refus
    # Le chemin qui suit le compartiment ne peut pas être vide, et ne remonte
    # jamais : `..` dans une URL publique désignerait un autre compartiment.
    reste = propre[len(prefixe) :]
    if not reste or ".." in reste:
        raise refus

    return propre
