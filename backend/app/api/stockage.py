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

> ### Le PROJET ne suffit pas, il faut aussi le DOSSIER (audit IDOR, `0.58.0`)
>
> Jusqu'à cette version, la vérification s'arrêtait au projet et au
> compartiment : n'importe quelle URL commençant par
> `…/public/avatars/` était acceptée, **quel que soit le dossier**. Or le
> premier segment du chemin *est* l'identifiant du propriétaire — c'est sur lui
> que porte la politique `storage.objects` (`docs/database.md` §9). Il manquait
> donc au backend la moitié de la règle que la base applique déjà à l'écriture
> du fichier.
>
> Conséquence : un joueur pouvait enregistrer `avatars/{id d'un autre}/avatar.jpg`
> comme SA photo, et porter le visage d'un autre membre au classement, sur la
> piste et au résumé d'un Grand Prix. Le créateur d'un championnat pouvait de
> même accrocher la photo d'un championnat auquel il n'appartient pas. **La RLS
> Storage n'y pouvait rien** : elle garde le dépôt du fichier, pas l'écriture de
> l'URL en base, qui passe par la clé de service.
>
> Le propriétaire attendu est donc un argument **obligatoire**, jamais facultatif :
> un défaut à `None` aurait rouvert la porte au premier appelant qui l'oublie.

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


def url_de_photo_valide(
    valeur: str, compartiment: str, quoi: str, proprietaire: str
) -> str:
    """Normalise et vérifie une URL de photo, ou refuse en français.

    Quatre conditions, et il faut les quatre :

    1. l'URL commence par celle du **projet Supabase configuré** — c'est ce qui
       interdit d'enregistrer l'adresse d'un serveur tiers ;
    2. elle désigne le **bon compartiment** — un avatar ne s'enregistre pas
       depuis le compartiment des championnats, ni l'inverse ;
    3. elle porte bien un **chemin** après le compartiment, et tient sous le
       plafond ;
    4. le **premier segment de ce chemin est `proprietaire`** — l'identifiant du
       profil pour un avatar, celui du championnat pour une photo de
       championnat.

    **La quatrième est celle qui manquait, et c'est la seule qui traite d'IDOR.**
    Les trois premières disent « cette photo vient bien de chez nous » ; seule la
    quatrième dit « et elle est bien la tienne ». Sans elle, `avatars/{id}/…`
    acceptait n'importe quel `{id}`, et la clé de service écrivait en base une
    URL que la RLS Storage n'aurait jamais laissé déposer. Le rapprochement se
    fait sans tenir compte de la casse : un UUID est insensible à la casse, et
    refuser une majuscule ferait échouer un client parfaitement légitime.

    **`proprietaire` est obligatoire.** Une valeur par défaut aurait rendu le
    contrôle facultatif, donc absent du premier appel qui l'oublie — exactement
    la porte qu'on vient de fermer.

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

    # Le dossier, puis ce qu'il contient. La séparation est faite sur le PREMIER
    # `/` seulement : le nom du fichier peut porter un `?v=…`, ce qui ne regarde
    # pas le dossier. Un chemin réduit au seul dossier est refusé — il désigne un
    # répertoire, jamais une image.
    dossier, separateur, objet = reste.partition("/")
    if not separateur or not objet:
        raise refus
    if dossier.lower() != str(proprietaire).strip().lower():
        raise refus

    return propre
