import re
from dataclasses import dataclass
from pathlib import Path


EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
PIN_RE = re.compile(r"^\d{4}$")


@dataclass(frozen=True)
class AccountCredential:
    email: str
    pin: str


def load_test_accounts(path: Path) -> list[AccountCredential]:
    tokens = [line.strip() for line in path.read_text(encoding="utf-8").splitlines()]
    tokens = [token for token in tokens if token]

    accounts: list[AccountCredential] = []
    pending_email: str | None = None
    for token in tokens:
        maybe_email = token.lower()
        if EMAIL_RE.match(maybe_email):
            pending_email = maybe_email
            continue

        if pending_email and PIN_RE.match(token):
            accounts.append(AccountCredential(email=pending_email, pin=token))
            pending_email = None

    if not accounts:
        raise ValueError(f"No test accounts found in {path}")
    return accounts
