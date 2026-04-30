from pathlib import Path

import pytest

from tests.support.accounts import AccountCredential, load_test_accounts


@pytest.fixture(scope="session")
def test_accounts() -> list[AccountCredential]:
    data_file = Path(__file__).resolve().parents[1] / "test_data.txt"
    return load_test_accounts(data_file)


@pytest.fixture(scope="session")
def test_account_map(test_accounts: list[AccountCredential]) -> dict[str, str]:
    return {account.email: account.pin for account in test_accounts}
