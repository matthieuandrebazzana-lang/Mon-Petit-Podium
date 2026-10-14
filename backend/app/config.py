import json
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

# Version de l'API, alignée sur celle du frontend.
# À incrémenter à chaque commit qui modifie l'application.
VERSION = "0.85.2"

# Toujours autorisées : le serveur de dev Vite, pour ne jamais casser le local.
ORIGINES_LOCALES = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
]

# URL du frontend de production. Sert de valeur par défaut à FRONTEND_URL :
# l'origine Vercel reste ainsi autorisée même si la variable d'environnement
# n'a pas encore été définie sur Railway.
ORIGINE_PRODUCTION = "https://mon-petit-podium.vercel.app"


def _decouper_origines(valeur: str) -> list[str]:
    """Transforme la valeur brute d'une variable d'environnement en liste d'origines.

    Accepte « https://a.com,https://b.com ». L'ancien format JSON
    (`["https://a.com"]`) reste toléré pour ne pas casser un `.env` existant.
    """
    texte = valeur.strip()
    if not texte:
        return []

    if texte.startswith("["):
        try:
            decodees = json.loads(texte)
        except json.JSONDecodeError:
            return []
        return [str(origine).strip() for origine in decodees if str(origine).strip()]

    return [part.strip() for part in texte.split(",") if part.strip()]


class Settings(BaseSettings):
    """Configuration lue depuis l'environnement, ou depuis backend/.env en local."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: str = "development"

    # URL du frontend déployé (Vercel). La variable d'environnement FRONTEND_URL
    # la surcharge sur Railway ; à défaut, l'origine de production reste couverte.
    frontend_url: str = ORIGINE_PRODUCTION

    # Origines supplémentaires éventuelles (préproduction, domaine personnalisé…),
    # séparées par des virgules. Typé `str` volontairement : pydantic-settings
    # exigerait du JSON strict pour un `list[str]` et planterait au démarrage
    # sur une valeur simple comme « https://exemple.com ».
    cors_origins: str = ""

    # — Supabase —
    # `supabase_url` et `supabase_anon_key` servent à valider le jeton de
    # l'appelant. `supabase_service_role_key` sert aux écritures en base : elle
    # contourne la RLS, ne doit JAMAIS quitter le serveur, et n'a donc aucun
    # équivalent VITE_ côté frontend.
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""

    # — Déclenchement en `curl` —
    # Secret partagé attendu dans l'en-tête `X-Admin-Secret` de
    # POST /scraper/declencher, POST /jobs/resultats/{id} et son banc d'essai.
    # Vide par défaut, et c'est délibéré : sans valeur définie, ces routes
    # refusent tout le monde plutôt que de s'ouvrir à tous. Le scraping écrit en
    # base ; une route d'administration ouverte serait le moyen le plus simple
    # de le faire tourner en boucle depuis dehors.
    #
    # **Il n'a plus d'équivalent VITE_ depuis la version `0.64.0`**, et il ne
    # doit jamais en retrouver un : l'application passe par POST /admin/action,
    # fermée par le jeton du membre et une relecture de `is_admin` en base. Ce
    # secret-ci ne sert plus qu'aux appels qui n'ont pas de session Supabase,
    # et ne quitte donc jamais Railway.
    admin_secret: str = ""

    # — Sign in with Apple —
    # Servent UNIQUEMENT à révoquer le jeton Apple d'un compte supprimé (App
    # Store, règle 5.1.1(v)) : la connexion elle-même passe par Supabase, qui
    # valide le jeton d'identité sans rien demander à Railway. La clé privée
    # (`.p8`, « Sign in with Apple » coché) se colle en PEM, retours à la ligne
    # écrits `\n` acceptés. Vides par défaut : la suppression de compte reste
    # possible, la révocation est sautée et journalisée.
    apple_team_id: str = ""
    apple_key_id: str = ""
    apple_private_key: str = ""
    # L'audience du jeton natif est le bundle identifier de l'app iOS.
    apple_client_id: str = "com.bazzana.greedf1"

    # — Notifications push (APNs) —
    # Clé `.p8` « Apple Push Notifications service » (Sandbox & Production),
    # collée en PEM dans `APNS_KEY`, retours à la ligne écrits `\n` acceptés.
    # `APNS_ENV` vaut `sandbox` (build Xcode, entitlement `development`) ou
    # `production` (TestFlight, App Store) : un jeton d'appareil n'est valable
    # que sur la passerelle de son environnement. Sans ces quatre valeurs, le
    # job de notifications ne démarre pas et `POST /push/test` rend `503`.
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_key: str = ""
    apns_bundle_id: str = "com.bazzana.greedf1"
    apns_env: str = "sandbox"

    @property
    def apns_configure(self) -> bool:
        return bool(
            self.apns_key_id.strip()
            and self.apns_team_id.strip()
            and self.apns_key.strip()
            and self.apns_bundle_id.strip()
        )

    @property
    def apple_configure(self) -> bool:
        return bool(
            self.apple_team_id.strip()
            and self.apple_key_id.strip()
            and self.apple_private_key.strip()
        )

    @property
    def admin_configure(self) -> bool:
        return bool(self.admin_secret.strip())

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    @property
    def supabase_configure(self) -> bool:
        """Vrai si les trois variables Supabase sont présentes.

        Le service démarre même sans elles : `/health` doit rester joignable
        pour diagnostiquer, et une configuration incomplète se signale à
        l'appel des routes concernées plutôt qu'en refusant de démarrer.
        """
        return bool(
            self.supabase_url.strip()
            and self.supabase_anon_key.strip()
            and self.supabase_service_role_key.strip()
        )

    @property
    def supabase_base(self) -> str:
        """URL du projet Supabase, sans barre oblique finale."""
        return self.supabase_url.strip().rstrip("/")

    @property
    def allowed_origins(self) -> list[str]:
        """Liste finale des origines autorisées par le middleware CORS.

        La barre oblique finale est retirée : l'en-tête `Origin` envoyé par le
        navigateur n'en comporte jamais, et « https://site.com/ » en variable
        d'environnement ne correspondrait donc jamais à rien.
        """
        # Les deux origines du projet — production Vercel et dev Vite — sont
        # garanties quoi qu'il arrive à la configuration de l'environnement.
        origines = [ORIGINE_PRODUCTION, *ORIGINES_LOCALES]

        if self.frontend_url.strip():
            origines.append(self.frontend_url.strip())

        origines.extend(_decouper_origines(self.cors_origins))

        # Normalisation puis dédoublonnage en conservant l'ordre.
        nettoyees = [origine.rstrip("/") for origine in origines if origine.strip()]
        return list(dict.fromkeys(nettoyees))


@lru_cache
def get_settings() -> Settings:
    """Instance unique, mise en cache : la configuration ne change pas à chaud."""
    return Settings()
