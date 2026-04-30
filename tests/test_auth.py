import time

import pytest

from app.auth import SessionTokenManager


@pytest.mark.unit
def test_issue_and_validate_token() -> None:
    manager = SessionTokenManager(token_ttl_seconds=60)
    token = manager.issue_token("user@example.com", "customer-123")

    session = manager.validate_token(token)
    assert session is not None
    assert session.email == "user@example.com"
    assert session.customer_id == "customer-123"


@pytest.mark.unit
def test_reject_unknown_token() -> None:
    manager = SessionTokenManager(token_ttl_seconds=60)
    assert manager.validate_token("unknown-token") is None


@pytest.mark.unit
def test_expired_token_is_rejected() -> None:
    manager = SessionTokenManager(token_ttl_seconds=0)
    token = manager.issue_token("expires@example.com", "customer-exp")
    time.sleep(0.01)
    assert manager.validate_token(token) is None
