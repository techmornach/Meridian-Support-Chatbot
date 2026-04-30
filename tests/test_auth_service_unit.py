from dataclasses import dataclass
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.auth_service import AuthServiceError, MCPAuthService
from app.config import Settings


@dataclass
class FakeToolResult:
    isError: bool
    structuredContent: dict | None
    content: list


class FakeStreamableHttpClient:
    async def __aenter__(self):
        return ("read", "write", None)

    async def __aexit__(self, exc_type, exc, tb):
        return False


class FakeClientSession:
    def __init__(self, read_stream, write_stream, result: FakeToolResult):
        self._result = result

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def initialize(self):
        return None

    async def call_tool(self, name, payload):
        return self._result


def _build_settings() -> Settings:
    return Settings(openai_api_key="test-key", enable_openai_tracing=False)


def _patch_mcp(monkeypatch: pytest.MonkeyPatch, result: FakeToolResult) -> None:
    monkeypatch.setattr(
        "app.auth_service.streamable_http_client",
        lambda _url: FakeStreamableHttpClient(),
    )
    monkeypatch.setattr(
        "app.auth_service.ClientSession",
        lambda read_stream, write_stream: FakeClientSession(read_stream, write_stream, result),
    )


@pytest.mark.unit
@pytest.mark.anyio
async def test_verify_customer_pin_extracts_customer_id_from_structured_content(
    monkeypatch: pytest.MonkeyPatch,
    test_accounts,
) -> None:
    account = test_accounts[0]
    customer_id = str(uuid4())
    result = FakeToolResult(
        isError=False,
        structuredContent={"result": f"Customer ID: {customer_id}"},
        content=[],
    )
    _patch_mcp(monkeypatch, result)

    service = MCPAuthService(_build_settings())
    customer = await service.verify_customer_pin(email=account.email, pin=account.pin)
    assert customer is not None
    assert customer.email == account.email
    assert customer.customer_id == customer_id


@pytest.mark.unit
@pytest.mark.anyio
async def test_verify_customer_pin_returns_none_on_invalid_credentials(
    monkeypatch: pytest.MonkeyPatch,
    test_accounts,
) -> None:
    account = test_accounts[0]
    result = FakeToolResult(
        isError=True,
        structuredContent=None,
        content=[],
    )
    _patch_mcp(monkeypatch, result)

    service = MCPAuthService(_build_settings())
    customer = await service.verify_customer_pin(email=account.email, pin=account.pin)
    assert customer is None


@pytest.mark.unit
@pytest.mark.anyio
async def test_verify_customer_pin_raises_on_missing_customer_id(
    monkeypatch: pytest.MonkeyPatch,
    test_accounts,
) -> None:
    account = test_accounts[0]
    result = FakeToolResult(
        isError=False,
        structuredContent={"result": "verified but no id here"},
        content=[SimpleNamespace(text="verified but still no id")],
    )
    _patch_mcp(monkeypatch, result)

    service = MCPAuthService(_build_settings())
    with pytest.raises(AuthServiceError):
        await service.verify_customer_pin(email=account.email, pin=account.pin)
