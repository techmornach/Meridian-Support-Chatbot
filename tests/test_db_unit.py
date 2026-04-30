import pytest

from app.db import DatabaseManager


class FakeConnection:
    def __init__(self, exists: bool) -> None:
        self.exists = exists
        self.executed: list[str] = []
        self.closed = False

    async def fetchval(self, query: str, database_name: str):
        self.executed.append(f"fetch:{database_name}")
        return 1 if self.exists else None

    async def execute(self, query: str):
        self.executed.append(query)
        return "CREATE DATABASE"

    async def close(self):
        self.closed = True


@pytest.mark.unit
@pytest.mark.anyio
async def test_ensure_database_exists_creates_missing_database(monkeypatch: pytest.MonkeyPatch):
    fake_conn = FakeConnection(exists=False)

    async def fake_connect(**kwargs):
        return fake_conn

    monkeypatch.setattr("app.db.asyncpg.connect", fake_connect)
    manager = DatabaseManager("postgresql+asyncpg://postgres:postgres@localhost:5432/meridian_chatbot")

    await manager.ensure_database_exists()

    assert any(entry.startswith("fetch:meridian_chatbot") for entry in fake_conn.executed)
    assert any("CREATE DATABASE" in entry for entry in fake_conn.executed)
    assert fake_conn.closed


@pytest.mark.unit
@pytest.mark.anyio
async def test_ensure_database_exists_skips_when_database_present(monkeypatch: pytest.MonkeyPatch):
    fake_conn = FakeConnection(exists=True)

    async def fake_connect(**kwargs):
        return fake_conn

    monkeypatch.setattr("app.db.asyncpg.connect", fake_connect)
    manager = DatabaseManager("postgresql+asyncpg://postgres:postgres@localhost:5432/meridian_chatbot")

    await manager.ensure_database_exists()

    assert any(entry.startswith("fetch:meridian_chatbot") for entry in fake_conn.executed)
    assert not any("CREATE DATABASE" in entry for entry in fake_conn.executed)
    assert fake_conn.closed
