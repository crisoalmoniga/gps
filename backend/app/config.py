from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://rutasegura:rutasegura@postgres:5432/rutasegura"
    osrm_url: str = "http://osrm:5000"
    cors_origins: list[str] = ["*"]

    # Capa A de Claude (seccion 3.1 del spec). Sin API key, los endpoints de
    # /analysis fallan explicitamente en vez de degradar en silencio.
    anthropic_api_key: str = ""
    claude_model: str = "claude-haiku-4-5-20251001"  # modelo economico para batch/clasificacion
    mention_confidence_threshold: float = 0.55

    class Config:
        env_file = ".env"


settings = Settings()
