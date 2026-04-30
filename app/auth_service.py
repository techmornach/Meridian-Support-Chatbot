import re
import logging
from dataclasses import dataclass

from agents import custom_span, trace
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

from app.config import Settings


class AuthServiceError(RuntimeError):
    """This would be whenever the MCP auth service is unavailable."""


@dataclass(frozen=True)
class AuthenticatedCustomer:
    email: str
    customer_id: str


class MCPAuthService:
    CUSTOMER_ID_RE = re.compile(r"Customer ID:\s*([0-9a-fA-F-]{36})")

    def __init__(self, settings: Settings) -> None:
        self._mcp_url = str(settings.mcp_server_url)
        self._enable_tracing = settings.enable_openai_tracing
        self._logger = logging.getLogger(__name__)

    async def verify_customer_pin(
        self,
        email: str,
        pin: str,
        request_id: str | None = None,
    ) -> AuthenticatedCustomer | None:
        normalized_email = email.lower()
        self._logger.info(
            "auth_verify_started request_id=%s email=%s pin_length=%s",
            request_id,
            normalized_email,
            len(pin),
        )

        with trace(
            "mcp_verify_customer_pin",
            group_id=request_id,
            metadata={"email": normalized_email},
            disabled=not self._enable_tracing,
        ):
            try:
                with custom_span(
                    "mcp_call_verify_customer_pin",
                    data={"email": normalized_email},
                ):
                    async with streamable_http_client(self._mcp_url) as streams:
                        read_stream, write_stream, _ = streams
                        async with ClientSession(read_stream, write_stream) as session:
                            await session.initialize()
                            result = await session.call_tool(
                                "verify_customer_pin",
                                {"email": normalized_email, "pin": pin},
                            )
            except Exception as exc:  # noqa: BLE001
                self._logger.exception(
                    "auth_verify_transport_error request_id=%s email=%s",
                    request_id,
                    normalized_email,
                )
                raise AuthServiceError("Failed to verify customer via MCP.") from exc

        if result.isError:
            self._logger.warning(
                "auth_verify_failed request_id=%s email=%s reason=invalid_credentials",
                request_id,
                normalized_email,
            )
            return None

        tool_text = ""
        if result.structuredContent and isinstance(result.structuredContent, dict):
            tool_text = str(result.structuredContent.get("result", ""))

        if not tool_text and result.content:
            text_chunk = getattr(result.content[0], "text", "")
            tool_text = str(text_chunk)

        match = self.CUSTOMER_ID_RE.search(tool_text)
        if not match:
            self._logger.error(
                "auth_verify_parse_error request_id=%s email=%s",
                request_id,
                normalized_email,
            )
            raise AuthServiceError("MCP auth response did not include customer ID.")

        customer_id = match.group(1)
        self._logger.info(
            "auth_verify_success request_id=%s email=%s customer_id=%s",
            request_id,
            normalized_email,
            customer_id,
        )
        return AuthenticatedCustomer(email=normalized_email, customer_id=customer_id)
