import pytest

from app.auth_service import MCPAuthService
from app.config import Settings


@pytest.mark.integration
@pytest.mark.anyio
async def test_verify_customer_pin_for_all_test_accounts(test_accounts) -> None:
    service = MCPAuthService(Settings(openai_api_key="test-key", enable_openai_tracing=False))

    for account in test_accounts:
        verified = await service.verify_customer_pin(email=account.email, pin=account.pin)
        assert verified is not None
        assert verified.email == account.email
        assert verified.customer_id
