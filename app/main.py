import os
import json
import logging
import time
from contextlib import asynccontextmanager
from uuid import uuid4
from typing import Protocol

from fastapi import Depends, FastAPI, HTTPException, Query, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import Response, StreamingResponse

from app.agent_service import (
    AgentServiceError,
    ChatAgentService,
    InputGuardrailViolationError,
)
from app.auth_service import AuthServiceError, AuthenticatedCustomer, MCPAuthService
from app.auth import AuthSession, SessionTokenManager
from app.config import Settings, get_settings
from app.conversation_store import ConversationMessage, PostgresConversationStore
from app.db import DatabaseManager
from app.logging_config import configure_logging
from app.schemas import (
    ChatRequest,
    ChatResponse,
    ConversationHistoryResponse,
    ConversationMessageResponse,
    LoginRequest,
    LoginResponse,
)


class ChatServiceProtocol(Protocol):
    async def get_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ) -> str:
        ...

    async def stream_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ):
        ...


class AuthServiceProtocol(Protocol):
    async def verify_customer_pin(
        self,
        email: str,
        pin: str,
        request_id: str | None = None,
    ) -> AuthenticatedCustomer | None:
        ...


class ConversationStoreProtocol(Protocol):
    async def get_recent_messages(
        self, customer_id: str, limit: int | None = None
    ) -> list[ConversationMessage]:
        ...


security = HTTPBearer(auto_error=False)


def parse_cors_origins(value: str) -> list[str]:
    origins = [origin.strip() for origin in value.split(",")]
    return [origin for origin in origins if origin]


class DisabledChatService:
    async def get_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ) -> str:
        raise AgentServiceError("Chat agent is not configured.")

    async def stream_reply(
        self,
        customer_email: str,
        customer_id: str,
        message: str,
        request_id: str | None = None,
    ):
        raise AgentServiceError("Chat agent is not configured.")


def create_app(
    settings: Settings | None = None,
    auth_service: AuthServiceProtocol | None = None,
    chat_service: ChatServiceProtocol | None = None,
    conversation_store: ConversationStoreProtocol | None = None,
) -> FastAPI:
    active_settings = settings or get_settings()
    if active_settings.openai_api_key:
        os.environ.setdefault("OPENAI_API_KEY", active_settings.openai_api_key)
    configure_logging(active_settings.log_level)
    logger = logging.getLogger(__name__)
    app = FastAPI(title="Meridian Support Chatbot API", version="0.1.0")
    cors_origins = parse_cors_origins(active_settings.cors_allowed_origins)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.state.settings = active_settings
    app.state.auth_service = auth_service or MCPAuthService(active_settings)
    app.state.db_manager = None
    app.state.conversation_store = conversation_store
    app.state.token_manager = SessionTokenManager(
        token_ttl_seconds=active_settings.auth_token_ttl_seconds
    )
    if chat_service:
        app.state.chat_service = chat_service
    else:
        try:
            db_manager = DatabaseManager(active_settings.database_url)
            app.state.db_manager = db_manager
            store = app.state.conversation_store or PostgresConversationStore(
                db_manager.session_factory
            )
            app.state.conversation_store = store
            app.state.chat_service = ChatAgentService(active_settings, store)
        except ValueError:
            # This helps to keep API bootable for health checks/tests whenever OPENAI_API_KEY is missing.
            app.state.chat_service = DisabledChatService()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        db_manager: DatabaseManager | None = app.state.db_manager
        if db_manager is not None:
            await db_manager.ensure_database_exists()
            await db_manager.init_models()
            logger.info("database_initialized")
        try:
            yield
        finally:
            db_manager = app.state.db_manager
            if db_manager is not None:
                await db_manager.close()
                logger.info("database_closed")

    app.router.lifespan_context = lifespan

    @app.middleware("http")
    async def request_logging_middleware(request: Request, call_next) -> Response:
        request_id = request.headers.get("x-request-id") or str(uuid4())
        request.state.request_id = request_id
        started_at = time.perf_counter()
        logger.info(
            "request_started request_id=%s method=%s path=%s",
            request_id,
            request.method,
            request.url.path,
        )
        try:
            response = await call_next(request)
        except Exception:  # noqa: BLE001
            elapsed_ms = int((time.perf_counter() - started_at) * 1000)
            logger.exception(
                "request_failed request_id=%s method=%s path=%s duration_ms=%s",
                request_id,
                request.method,
                request.url.path,
                elapsed_ms,
            )
            raise

        elapsed_ms = int((time.perf_counter() - started_at) * 1000)
        response.headers["X-Request-ID"] = request_id
        logger.info(
            "request_finished request_id=%s method=%s path=%s status=%s duration_ms=%s",
            request_id,
            request.method,
            request.url.path,
            response.status_code,
            elapsed_ms,
        )
        return response

    async def get_current_session(
        request: Request,
        credentials: HTTPAuthorizationCredentials | None = Depends(security),
    ) -> AuthSession:
        request_id = getattr(request.state, "request_id", None)
        if credentials is None or credentials.scheme.lower() != "bearer":
            logger.warning(
                "auth_token_missing request_id=%s path=%s",
                request_id,
                request.url.path,
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or invalid bearer token.",
            )

        session = request.app.state.token_manager.validate_token(credentials.credentials)
        if not session:
            logger.warning(
                "auth_token_invalid request_id=%s path=%s",
                request_id,
                request.url.path,
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token.",
            )
        logger.info(
            "auth_token_valid request_id=%s customer_id=%s",
            request_id,
            session.customer_id,
        )
        return session

    @app.get("/health")
    async def healthcheck() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/auth/login", response_model=LoginResponse)
    async def login(payload: LoginRequest, request: Request) -> LoginResponse:
        request_id = getattr(request.state, "request_id", None)
        service: AuthServiceProtocol = request.app.state.auth_service
        logger.info(
            "login_started request_id=%s email=%s",
            request_id,
            str(payload.email).lower(),
        )
        try:
            customer = await service.verify_customer_pin(
                email=str(payload.email),
                pin=payload.pin,
                request_id=request_id,
            )
        except AuthServiceError:
            logger.exception(
                "login_backend_error request_id=%s email=%s",
                request_id,
                str(payload.email).lower(),
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Authentication service is unavailable. Please try again.",
            ) from None

        if not customer:
            logger.warning(
                "login_denied request_id=%s email=%s",
                request_id,
                str(payload.email).lower(),
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or PIN.",
            )

        token = request.app.state.token_manager.issue_token(
            email=customer.email,
            customer_id=customer.customer_id,
        )
        logger.info(
            "login_success request_id=%s email=%s customer_id=%s",
            request_id,
            customer.email,
            customer.customer_id,
        )
        return LoginResponse(access_token=token)

    @app.post("/chat", response_model=ChatResponse)
    async def chat(
        payload: ChatRequest,
        request: Request,
        session: AuthSession = Depends(get_current_session),
        stream: bool = Query(default=False),
    ) -> ChatResponse | StreamingResponse:
        request_id = getattr(request.state, "request_id", None)
        service: ChatServiceProtocol = request.app.state.chat_service
        logger.info(
            "chat_started request_id=%s customer_id=%s message_chars=%s",
            request_id,
            session.customer_id,
            len(payload.message),
        )
        if stream:
            async def event_stream():
                try:
                    async for chunk in service.stream_reply(
                        customer_email=session.email,
                        customer_id=session.customer_id,
                        message=payload.message,
                        request_id=request_id,
                    ):
                        yield f"data: {json.dumps({'delta': chunk})}\n\n"
                    yield "event: done\ndata: [DONE]\n\n"
                except InputGuardrailViolationError as exc:
                    logger.warning(
                        "chat_stream_rejected request_id=%s customer_id=%s reason=%s",
                        request_id,
                        session.customer_id,
                        str(exc),
                    )
                    yield f"event: error\ndata: {json.dumps({'error': str(exc)})}\n\n"
                except AgentServiceError:
                    logger.exception(
                        "chat_stream_failed request_id=%s customer_id=%s",
                        request_id,
                        session.customer_id,
                    )
                    yield (
                        "event: error\ndata: "
                        + json.dumps({"error": "Support agent is unavailable. Please try again."})
                        + "\n\n"
                    )

            return StreamingResponse(event_stream(), media_type="text/event-stream")

        try:
            reply = await service.get_reply(
                customer_email=session.email,
                customer_id=session.customer_id,
                message=payload.message,
                request_id=request_id,
            )
        except InputGuardrailViolationError as exc:
            logger.warning(
                "chat_rejected request_id=%s customer_id=%s reason=%s",
                request_id,
                session.customer_id,
                str(exc),
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=str(exc),
            ) from None
        except AgentServiceError:
            logger.exception(
                "chat_failed request_id=%s customer_id=%s",
                request_id,
                session.customer_id,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Support agent is unavailable. Please try again.",
            ) from None
        logger.info(
            "chat_success request_id=%s customer_id=%s response_chars=%s",
            request_id,
            session.customer_id,
            len(reply),
        )
        return ChatResponse(reply=reply)

    @app.get("/conversations/me", response_model=ConversationHistoryResponse)
    async def get_my_conversation_history(
        request: Request,
        session: AuthSession = Depends(get_current_session),
        limit: int | None = Query(default=None, ge=1),
    ) -> ConversationHistoryResponse:
        store: ConversationStoreProtocol | None = request.app.state.conversation_store
        if store is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Conversation history store is unavailable.",
            )

        messages = await store.get_recent_messages(customer_id=session.customer_id, limit=limit)
        return ConversationHistoryResponse(
            messages=[
                ConversationMessageResponse(
                    role=msg.role,
                    content=msg.content,
                    created_at=msg.created_at,
                )
                for msg in messages
            ]
        )

    return app


app = create_app()
