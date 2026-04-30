from pathlib import Path

import pytest

from tests.support.accounts import load_test_accounts


@pytest.mark.unit
def test_load_test_accounts_from_text_file() -> None:
    data_file = Path(__file__).resolve().parents[1] / "test_data.txt"
    accounts = load_test_accounts(data_file)

    assert len(accounts) > 0
    assert all(account.email for account in accounts)
    assert all(len(account.pin) == 4 for account in accounts)
