from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://rutasegura:rutasegura@postgres:5432/rutasegura"
    osrm_url: str = "http://osrm:5000"
    cors_origins: list[str] = ["*"]

    class Config:
        env_file = ".env"


settings = Settings()
