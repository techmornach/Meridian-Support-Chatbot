import asyncpg
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker, create_async_engine

from app.conversation_store import Base


class DatabaseManager:
    def __init__(self, database_url: str) -> None:
        self._database_url = database_url
        self._engine: AsyncEngine = create_async_engine(database_url, echo=False)
        self.session_factory = async_sessionmaker(
            bind=self._engine,
            expire_on_commit=False,
        )

    async def ensure_database_exists(self) -> None:
        url = make_url(self._database_url)
        if url.drivername != "postgresql+asyncpg" or not url.database:
            return

        admin_db = "postgres"
        conn = await asyncpg.connect(
            host=url.host or "localhost",
            port=url.port or 5432,
            user=url.username or "postgres",
            password=url.password,
            database=admin_db,
        )
        try:
            exists = await conn.fetchval(
                "SELECT 1 FROM pg_database WHERE datname = $1",
                url.database,
            )
            if exists:
                return

            # Safe identifier quoting for database name.
            database_name = url.database.replace('"', '""')
            await conn.execute(f'CREATE DATABASE "{database_name}"')
        finally:
            await conn.close()

    async def init_models(self) -> None:
        async with self._engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    async def close(self) -> None:
        await self._engine.dispose()
