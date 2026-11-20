from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "OpsForge"
    # Local SQLite fallback for development; Compose overrides this with PostgreSQL.
    database_url: str = "sqlite:///./opsforge-local.db"
    log_level: str = "INFO"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
