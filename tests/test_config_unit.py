import pytest

from app.config import Settings, get_settings


@pytest.mark.unit
def test_get_settings_is_cached() -> None:
    get_settings.cache_clear()
    first = get_settings()
    second = get_settings()
    assert first is second


@pytest.mark.unit
def test_settings_defaults_are_present() -> None:
    settings = Settings()
    assert settings.openai_model
    assert settings.mcp_server_url
    assert settings.auth_token_ttl_seconds > 0
