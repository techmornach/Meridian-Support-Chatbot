from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from uuid import uuid4

from sqlalchemy import DateTime, String, Text, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


class Base(DeclarativeBase):
    pass


class ConversationMessageModel(Base):
    __tablename__ = "conversation_messages"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid4())
    )
    customer_id: Mapped[str] = mapped_column(String(64), index=True)
    customer_email: Mapped[str] = mapped_column(String(320))
    role: Mapped[str] = mapped_column(String(32))
    content: Mapped[str] = mapped_column(Text())
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )


@dataclass(frozen=True)
class ConversationMessage:
    role: str
    content: str
    created_at: datetime


class ConversationStore(Protocol):
    async def add_message(
        self,
        customer_id: str,
        customer_email: str,
        role: str,
        content: str,
    ) -> None:
        ...

    async def get_recent_messages(
        self, customer_id: str, limit: int | None = None
    ) -> list[ConversationMessage]:
        ...


class PostgresConversationStore:
    def __init__(self, session_factory: sessionmaker[AsyncSession]) -> None:
        self._session_factory = session_factory

    async def add_message(
        self,
        customer_id: str,
        customer_email: str,
        role: str,
        content: str,
    ) -> None:
        async with self._session_factory() as session:
            session.add(
                ConversationMessageModel(
                    customer_id=customer_id,
                    customer_email=customer_email,
                    role=role,
                    content=content,
                )
            )
            await session.commit()

    async def get_recent_messages(
        self, customer_id: str, limit: int | None = None
    ) -> list[ConversationMessage]:
        async with self._session_factory() as session:
            query = (
                select(ConversationMessageModel)
                .where(ConversationMessageModel.customer_id == customer_id)
                .order_by(ConversationMessageModel.created_at.desc())
            )
            if limit is not None:
                query = query.limit(max(1, limit))
            result = await session.execute(query)
            rows = list(result.scalars().all())

        rows.reverse()
        return [
            ConversationMessage(
                role=row.role,
                content=row.content,
                created_at=row.created_at,
            )
            for row in rows
        ]
