import json
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

# Version de l'API, alignée sur celle du frontend.
# À incrémenter à chaque commit qui modifie l'application.
VERSION = "0.1.2"

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

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

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
