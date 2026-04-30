from fastapi.testclient import TestClient
import pytest
from datetime import UTC, datetime

from app.agent_service import InputGuardrailViolationError
from app.auth_service import AuthenticatedCustomer
from app.config import Settings
from app.conversation_store import ConversationMessage
from app.main import create_app
from tests.support.accounts import AccountCredential


pytestmark = pytest.mark.unit


class FakeAuthService:
    def __init__(self, account_map: dict[str, str]) -> None:
        self._account_map = account_map

    async def verify_customer_pin(
        self,
        email: str,
        pin: str,
        request_id: str | None = None,
    ) -> AuthenticatedCustomer | None:
        normalized_email = email.lower()
        if self._account_map.get(normalized_email) != pin:
            return None
        customer_id = f"customer-{normalized_email.replace('@', '-at-').replace('.', '-')}"
        return AuthenticatedCustomer(email=normalized_email, customer_id=customer_id)


class FakeChatService:
    async def get_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ) -> str:
        if "blocked" in message:
            raise InputGuardrailViolationError("Request blocked by input safety guardrail.")
        return f"echo:{customer_email}:{customer_id}:{message}:{request_id}"

    async def stream_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ):
        if "blocked" in message:
            raise InputGuardrailViolationError("Request blocked by input safety guardrail.")
        yield "hello "
        yield f"{customer_email}"


class FakeConversationStore:
    def __init__(self) -> None:
        self._messages: dict[str, list[ConversationMessage]] = {}

    def seed_customer(self, customer_id: str) -> None:
        now = datetime.now(UTC)
        self._messages[customer_id] = [
            ConversationMessage(role="user", content="hello-1", created_at=now),
            ConversationMessage(role="assistant", content="reply-1", created_at=now),
            ConversationMessage(role="user", content="hello-2", created_at=now),
            ConversationMessage(role="assistant", content="reply-2", created_at=now),
        ]

    async def get_recent_messages(self, customer_id: str, limit: int | None = None):
        messages = self._messages.get(customer_id, [])
        if limit is None:
            return messages
        return messages[-limit:]


def build_client(account_map: dict[str, str]) -> tuple[TestClient, FakeConversationStore]:
    settings = Settings(openai_api_key="test-key", enable_openai_tracing=False)
    store = FakeConversationStore()
    for email in account_map:
        cid = f"customer-{email.replace('@', '-at-').replace('.', '-')}"
        store.seed_customer(cid)
    app = create_app(
        settings=settings,
        auth_service=FakeAuthService(account_map=account_map),
        chat_service=FakeChatService(),
        conversation_store=store,
    )
    return TestClient(app), store


def test_chat_requires_authentication(test_account_map: dict[str, str]) -> None:
    client, _ = build_client(test_account_map)
    response = client.post("/chat", json={"message": "hello"})
    assert response.status_code == 401


def test_login_then_chat_succeeds_for_all_accounts(
    test_accounts: list[AccountCredential],
    test_account_map: dict[str, str],
) -> None:
    client, _ = build_client(test_account_map)
    for account in test_accounts:
        login_response = client.post(
            "/auth/login",
            json={"email": account.email, "pin": account.pin},
        )
        assert login_response.status_code == 200
        token = login_response.json()["access_token"]
        assert token

        chat_response = client.post(
            "/chat",
            headers={"Authorization": f"Bearer {token}"},
            json={"message": "where is my order"},
        )
        assert chat_response.status_code == 200
        assert account.email in chat_response.json()["reply"]
        assert "None" not in chat_response.json()["reply"]


def test_chat_returns_400_when_guardrail_blocks(
    test_accounts: list[AccountCredential],
    test_account_map: dict[str, str],
) -> None:
    client, _ = build_client(test_account_map)
    first_account = test_accounts[0]
    login_response = client.post(
        "/auth/login",
        json={"email": first_account.email, "pin": first_account.pin},
    )
    token = login_response.json()["access_token"]
    response = client.post(
        "/chat",
        headers={"Authorization": f"Bearer {token}"},
        json={"message": "blocked content"},
    )
    assert response.status_code == 400


def test_chat_stream_returns_sse_chunks(
    test_accounts: list[AccountCredential],
    test_account_map: dict[str, str],
) -> None:
    client, _ = build_client(test_account_map)
    first_account = test_accounts[0]
    login_response = client.post(
        "/auth/login",
        json={"email": first_account.email, "pin": first_account.pin},
    )
    token = login_response.json()["access_token"]
    response = client.post(
        "/chat?stream=true",
        headers={"Authorization": f"Bearer {token}"},
        json={"message": "stream this"},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    assert "data:" in response.text
    assert first_account.email in response.text
    assert "event: done" in response.text


def test_conversation_history_requires_authentication(test_account_map: dict[str, str]) -> None:
    client, _ = build_client(test_account_map)
    response = client.get("/conversations/me")
    assert response.status_code == 401


def test_conversation_history_returns_all_messages_when_limit_not_provided(
    test_accounts: list[AccountCredential],
    test_account_map: dict[str, str],
) -> None:
    client, _ = build_client(test_account_map)
    first_account = test_accounts[0]
    login_response = client.post(
        "/auth/login",
        json={"email": first_account.email, "pin": first_account.pin},
    )
    token = login_response.json()["access_token"]

    response = client.get("/conversations/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    payload = response.json()
    assert "messages" in payload
    assert len(payload["messages"]) == 4
    assert payload["messages"][0]["role"] == "user"
    assert payload["messages"][1]["role"] == "assistant"


def test_conversation_history_honors_limit(
    test_accounts: list[AccountCredential],
    test_account_map: dict[str, str],
) -> None:
    client, _ = build_client(test_account_map)
    first_account = test_accounts[0]
    login_response = client.post(
        "/auth/login",
        json={"email": first_account.email, "pin": first_account.pin},
    )
    token = login_response.json()["access_token"]
    response = client.get("/conversations/me?limit=2", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    payload = response.json()
    assert len(payload["messages"]) == 2
