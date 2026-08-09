from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

# Version de l'API, alignée sur celle du frontend.
# À incrémenter à chaque commit qui modifie l'application.
VERSION = "0.1.0"


class Settings(BaseSettings):
    """Configuration lue depuis l'environnement, ou depuis backend/.env en local."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: str = "development"

    # Origines autorisées à appeler l'API. En local, le serveur de dev Vite.
    # En production, y ajouter l'URL Vercel.
    cors_origins: list[str] = [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]

    @property
    def is_production(self) -> bool:
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    """Instance unique, mise en cache : la configuration ne change pas à chaud."""
    return Settings()
