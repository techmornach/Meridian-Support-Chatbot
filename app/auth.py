from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from secrets import token_urlsafe


@dataclass(frozen=True)
class AuthSession:
    email: str
    customer_id: str
    expires_at: datetime

    @property
    def is_expired(self) -> bool:
        return datetime.now(UTC) >= self.expires_at


class SessionTokenManager:
    def __init__(self, token_ttl_seconds: int) -> None:
        self._token_ttl = token_ttl_seconds
        self._active_tokens: dict[str, AuthSession] = {}

    def issue_token(self, email: str, customer_id: str) -> str:
        token = token_urlsafe(32)
        expires_at = datetime.now(UTC) + timedelta(seconds=self._token_ttl)
        self._active_tokens[token] = AuthSession(
            email=email,
            customer_id=customer_id,
            expires_at=expires_at,
        )
        return token

    def validate_token(self, token: str) -> AuthSession | None:
        session = self._active_tokens.get(token)
        if not session:
            return None

        if session.is_expired:
            self._active_tokens.pop(token, None)
            return None

        return session
