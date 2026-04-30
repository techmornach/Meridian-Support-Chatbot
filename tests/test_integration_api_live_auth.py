import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


class FakeChatService:
    async def get_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ) -> str:
        return f"ok:{customer_email}:{customer_id}:{message}:{request_id}"


@pytest.mark.integration
def test_login_and_chat_for_all_test_accounts_with_live_mcp_auth(test_accounts) -> None:
    app = create_app(
        settings=Settings(openai_api_key="test-key", enable_openai_tracing=False),
        chat_service=FakeChatService(),
    )
    client = TestClient(app)

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
            json={"message": "check my latest order"},
        )
        assert chat_response.status_code == 200
        assert account.email in chat_response.json()["reply"]
