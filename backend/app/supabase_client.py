"""Accès à Supabase depuis le backend : validation des jetons et écritures.

Deux clés, deux usages qu'il ne faut jamais confondre :

- la **clé anonyme** sert uniquement à valider le jeton de l'appelant, en
  demandant à Supabase qui il est ;
- la **clé de service** sert aux lectures et écritures. Elle contourne la RLS,
  ce qui est voulu : plusieurs opérations de l'étape 3 sont impossibles sous
  RLS (retrouver un championnat par son code alors qu'on n'en est pas encore
  membre, par exemple). L'autorisation est alors portée par le code des routes,
  qui ne travaille jamais qu'avec l'identifiant issu du jeton vérifié.

Les politiques RLS de la migration restent la protection du chemin direct
frontend → Supabase (lecture d'un championnat et de ses membres). Elles ne sont
pas redondantes : elles couvrent un autre appelant.
"""

import time

import httpx

from app.config import get_settings

# Délai généreux : Railway et Supabase peuvent tous deux sortir de veille.
DELAI = httpx.Timeout(15.0, connect=10.0)

# Durée de mise en cache d'un jeton déjà validé. Sans elle, chaque appel d'API
# coûterait un aller-retour supplémentaire vers Supabase. Assez court pour
# qu'une déconnexion soit prise en compte presque tout de suite.
CACHE_JETON_SECONDES = 60
CACHE_JETON_TAILLE = 512


class ErreurSupabase(Exception):
    """Échec d'un appel à Supabase, avec le code PostgREST quand il existe."""

    def __init__(self, message: str, code: str = "", statut: int = 0) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.statut = statut


_client: httpx.AsyncClient | None = None
# jeton -> (identifiant utilisateur, instant d'expiration du cache)
_jetons_valides: dict[str, tuple[str, float]] = {}


def client() -> httpx.AsyncClient:
    """Client HTTP partagé : les connexions restent ouvertes entre les appels."""
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=DELAI)
    return _client


async def fermer_client() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


def _entetes_service() -> dict[str, str]:
    cle = get_settings().supabase_service_role_key.strip()
    return {
        "apikey": cle,
        "Authorization": f"Bearer {cle}",
        "Content-Type": "application/json",
    }


async def identifiant_du_jeton(jeton: str) -> str | None:
    """Valide un jeton d'accès Supabase et renvoie l'identifiant de son porteur.

    La validation est déléguée à Supabase (`/auth/v1/user`) plutôt que faite
    localement : elle ne demande alors aucun secret de signature, et reste
    valable quelle que soit la clé avec laquelle le projet signe ses jetons.
    Renvoie `None` si le jeton est absent, expiré ou invalide.
    """
    if not jeton:
        return None

    maintenant = time.monotonic()
    en_cache = _jetons_valides.get(jeton)
    if en_cache and en_cache[1] > maintenant:
        return en_cache[0]

    parametres = get_settings()
    try:
        reponse = await client().get(
            f"{parametres.supabase_base}/auth/v1/user",
            headers={
                "apikey": parametres.supabase_anon_key.strip(),
                "Authorization": f"Bearer {jeton}",
            },
        )
    except httpx.HTTPError as erreur:
        raise ErreurSupabase(
            "Le service d'authentification est injoignable.", statut=503
        ) from erreur

    if reponse.status_code != 200:
        _jetons_valides.pop(jeton, None)
        return None

    identifiant = reponse.json().get("id")
    if not identifiant:
        return None

    # Purge grossière mais suffisante : le cache ne sert qu'à éviter des
    # allers-retours, le perdre entièrement n'a aucune conséquence.
    if len(_jetons_valides) >= CACHE_JETON_TAILLE:
        _jetons_valides.clear()
    _jetons_valides[jeton] = (identifiant, maintenant + CACHE_JETON_SECONDES)

    return identifiant


async def _appeler(methode: str, chemin: str, **kwargs) -> httpx.Response:
    parametres = get_settings()
    entetes = {**_entetes_service(), **kwargs.pop("headers", {})}
    try:
        return await client().request(
            methode,
            f"{parametres.supabase_base}/rest/v1{chemin}",
            headers=entetes,
            **kwargs,
        )
    except httpx.HTTPError as erreur:
        raise ErreurSupabase(
            "La base de données est injoignable.", statut=503
        ) from erreur


def _verifier(reponse: httpx.Response) -> None:
    if reponse.status_code < 400:
        return

    # PostgREST répond en JSON ; en cas de panne franche (proxy, 502) le corps
    # peut être du HTML, d'où le repli.
    try:
        corps = reponse.json()
    except ValueError:
        corps = {}

    raise ErreurSupabase(
        message=str(corps.get("message") or "Erreur de la base de données."),
        code=str(corps.get("code") or ""),
        statut=reponse.status_code,
    )


async def selectionner(table: str, parametres: dict[str, str]) -> list[dict]:
    reponse = await _appeler("GET", f"/{table}", params=parametres)
    _verifier(reponse)
    return reponse.json()


async def inserer(table: str, ligne: dict) -> list[dict]:
    reponse = await _appeler(
        "POST",
        f"/{table}",
        json=ligne,
        headers={"Prefer": "return=representation"},
    )
    _verifier(reponse)
    return reponse.json()


async def upserter(table: str, lignes: list[dict], sur_conflit: str) -> list[dict]:
    """Insère des lignes, ou met à jour celles qui existent déjà.

    `sur_conflit` nomme la ou les colonnes portant la contrainte d'unicité,
    séparées par des virgules. PostgREST traduit l'ensemble en un seul
    `insert … on conflict … do update` : c'est ce qui rend le scraper
    idempotent, là où un `insert` nu échouerait au deuxième passage et où un
    `delete` suivi d'un `insert` laisserait le GP sans aucune cote pendant un
    court instant — et définitivement si l'insertion échouait.

    Une liste vide n'appelle pas Supabase : PostgREST refuse un corps vide.
    """
    if not lignes:
        return []

    reponse = await _appeler(
        "POST",
        f"/{table}",
        json=lignes,
        params={"on_conflict": sur_conflit},
        headers={"Prefer": "resolution=merge-duplicates,return=representation"},
    )
    _verifier(reponse)
    return reponse.json()


async def inserer_sans_doublon(table: str, ligne: dict) -> bool:
    """Insère une ligne si sa clé n'existe pas encore. Rend `True` si elle a été créée.

    `insert … on conflict do nothing` : la clé primaire tranche, pas une lecture
    préalable — deux appels simultanés ne peuvent pas obtenir `True` tous les
    deux. C'est la réservation des notifications push (`notifications_envoyees`).
    """
    reponse = await _appeler(
        "POST",
        f"/{table}",
        json=[ligne],
        headers={"Prefer": "resolution=ignore-duplicates,return=representation"},
    )
    _verifier(reponse)
    return bool(reponse.json())


async def mettre_a_jour(
    table: str, parametres: dict[str, str], valeurs: dict
) -> list[dict]:
    """Modifie les lignes filtrées et renvoie celles qui l'ont été.

    `return=representation` sert ici de preuve : une liste vide dit que le
    filtre n'a touché aucune ligne, ce qui distingue « le GP n'existe pas » de
    « le GP est passé à `termine` ».
    """
    reponse = await _appeler(
        "PATCH",
        f"/{table}",
        params=parametres,
        json=valeurs,
        headers={"Prefer": "return=representation"},
    )
    _verifier(reponse)
    return reponse.json()


async def supprimer(table: str, parametres: dict[str, str]) -> list[dict]:
    """Supprime et renvoie les lignes supprimées.

    `return=representation` n'est pas cosmétique : une liste vide est le seul
    moyen de distinguer « rien à supprimer » d'une suppression effective, ce qui
    distingue ici « pas membre » de « a bien quitté ».
    """
    reponse = await _appeler(
        "DELETE",
        f"/{table}",
        params=parametres,
        headers={"Prefer": "return=representation"},
    )
    _verifier(reponse)
    return reponse.json()


async def appeler_fonction(nom: str, arguments: dict):
    reponse = await _appeler("POST", f"/rpc/{nom}", json=arguments)
    _verifier(reponse)
    if not reponse.content:
        return None
    return reponse.json()


async def supprimer_objets_storage(compartiment: str, chemins: list[str]) -> None:
    """Efface des objets Storage — avec la clé de service, hors RLS.

    Appelée depuis le backend et non depuis le client (`lib/stockage.js`,
    `DepotPhoto.swift`) : la suppression de compte doit réussir même après que
    le compte Supabase Auth a disparu, quand la session de l'appelant n'existe
    déjà plus.

    **Requête différente de `_appeler`** : Storage a sa propre API
    (`/storage/v1`), pas `/rest/v1`. Le corps porte `prefixes`, au pluriel —
    c'est le point d'entrée de suppression EN LOT de Supabase Storage
    (`DELETE /object/{compartiment}`, body `{"prefixes": [...]}`), le même
    qu'appelle `supabase.storage.from(...).remove(...)` côté client.

    Son échec est journalisé par l'appelant, jamais renvoyé à l'appelant final :
    un objet orphelin en Storage est un défaut d'exploitation, pas une raison de
    faire échouer la suppression du compte.
    """
    if not chemins:
        return
    parametres = get_settings()
    try:
        reponse = await client().request(
            "DELETE",
            f"{parametres.supabase_base}/storage/v1/object/{compartiment}",
            headers=_entetes_service(),
            json={"prefixes": chemins},
        )
    except httpx.HTTPError as erreur:
        raise ErreurSupabase("Le stockage est injoignable.", statut=503) from erreur
    _verifier(reponse)


async def supprimer_utilisateur_auth(utilisateur_id: str) -> None:
    """Supprime le compte Supabase Auth — API d'administration de GoTrue.

    **Jamais `/rest/v1`** : c'est une autre API que PostgREST, réservée à la
    clé de service. `public.profils` suit par cascade (1-1, `docs/database.md`
    §1) ; c'est pourquoi cette fonction est appelée EN DERNIER par la route de
    suppression de compte, une fois les championnats, pronostics et la photo
    déjà traités — au cas où l'appelant ne rejouerait pas la requête jusqu'au
    bout.

    Un `404` est toléré plutôt que refusé : il dit que le compte est déjà
    supprimé, ce qu'un appel rejoué après un premier succès partiel doit
    pouvoir constater sans échouer sur ce qu'il a déjà obtenu.
    """
    parametres = get_settings()
    try:
        reponse = await client().delete(
            f"{parametres.supabase_base}/auth/v1/admin/users/{utilisateur_id}",
            headers=_entetes_service(),
        )
    except httpx.HTTPError as erreur:
        raise ErreurSupabase(
            "Le service d'authentification est injoignable.", statut=503
        ) from erreur
    if reponse.status_code < 400 or reponse.status_code == 404:
        return

    try:
        corps = reponse.json()
    except ValueError:
        corps = {}
    raise ErreurSupabase(
        message=str(
            corps.get("msg")
            or corps.get("message")
            or corps.get("error_description")
            or "Suppression du compte impossible."
        ),
        statut=reponse.status_code,
    )
