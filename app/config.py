from functools import lru_cache

from pydantic import AnyHttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
    guardrail_model: str = "gpt-4o-mini"
    mcp_server_url: AnyHttpUrl = "https://order-mcp-74afyau24q-uc.a.run.app/mcp"
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/meridian_chatbot"
    auth_token_ttl_seconds: int = 3600
    max_input_chars: int = 4000
    history_context_limit: int = 30
    log_level: str = "INFO"
    enable_openai_tracing: bool = True
    cors_allowed_origins: str = "http://localhost:3000"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
