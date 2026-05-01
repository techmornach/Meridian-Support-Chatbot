# Meridian Support Chatbot Backend

FastAPI backend prototype for Meridian Electronics customer support chatbot.

## Stack

- FastAPI for API endpoints
- OpenAI Agents SDK for model + tool orchestration
- MCP server integration over Streamable HTTP
- `uv` for dependency and task management

## Features

- `POST /auth/login` authenticates customer with email + 4-digit PIN via MCP `verify_customer_pin`
- `POST /chat` requires bearer token from login
- Chat requests are executed by an OpenAI Agent connected to MCP tools
- Model-based input guardrails screen prompts before chat processing
- Customer conversation history is stored in Postgres per customer ID
- Last 30 messages are automatically included as context in each chat turn
- Agent exposes `fetch_conversation_history` tool for history retrieval
- OpenAI traces are emitted for auth verification and chat runs
- Detailed request/auth/chat logs are emitted with request IDs
- Test coverage for token auth and auth-gated chat flow

## Environment

Copy `.env.example` to `.env` and fill values:

```bash
cp .env.example .env
```

Required:

- `OPENAI_API_KEY`
- `MCP_SERVER_URL` (defaults to assignment URL if unset)
- `DATABASE_URL` (defaults to local Docker Postgres)

Optional:

- `LOG_LEVEL` (`INFO` by default)
- `ENABLE_OPENAI_TRACING` (`true` by default)
- `CORS_ALLOWED_ORIGINS` (comma-separated; defaults to `http://localhost:3000`)
- `GUARDRAIL_MODEL` (`gpt-4o-mini` by default)
- `MAX_INPUT_CHARS` (`4000` by default)
- `HISTORY_CONTEXT_LIMIT` (`30` by default)

## Postgres for local testing

Start Postgres with Docker Compose:

```bash
docker compose up -d postgres
```

On startup, the app performs a lightweight dev bootstrap:
- Ensures the configured PostgreSQL database exists
- Creates required tables if they are missing

Stop it:

```bash
docker compose down
```

## Run locally

```bash
uv sync
uv run uvicorn app.main:app --reload --port 8000
```

## Run tests

```bash
uv run pytest
```

Run only unit tests:

```bash
uv run pytest -m unit
```

Run only integration tests (live MCP calls):

```bash
uv run pytest -m integration
```

## API usage

1) Authenticate

```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"donaldgarcia@example.net","pin":"7912"}'
```

2) Call chat

```bash
curl -X POST http://localhost:8000/chat \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message":"Can you check if the MX-27 monitor is in stock?"}'
```

2b) Stream chat response (SSE)

```bash
curl -N -X POST "http://localhost:8000/chat?stream=true" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"message":"Can you check my latest order?"}'
```

3) Fetch conversation history for authenticated customer

```bash
curl -X GET "http://localhost:8000/conversations/me" \
  -H "Authorization: Bearer <TOKEN>"
```

Optionally pass `limit` to fetch only recent messages:

```bash
curl -X GET "http://localhost:8000/conversations/me?limit=30" \
  -H "Authorization: Bearer <TOKEN>"
```

## Fast EC2 deployment (no Docker)

For fastest stakeholder sharing, use native EC2 services (no containers):

- PostgreSQL on EC2
- FastAPI backend as `systemd` service
- Next.js frontend as `systemd` service
- Nginx reverse proxy
- Optional Let's Encrypt HTTPS when domains are provided

### One-command bootstrap (recommended)

1) Create your deploy config:

```bash
cp deploy/.env.example deploy/.env
```

2) Edit `deploy/.env`:

- Set required values:
  - `SSH_PRIVATE_KEY_PATH`
  - `OPENAI_API_KEY`
- Choose one routing mode:
  - **Domain + HTTPS mode**
    - Set `FRONTEND_DOMAIN` and `BACKEND_DOMAIN`
    - Set `CREATE_ROUTE53_RECORDS=true` and `HOSTED_ZONE_NAME` if Terraform should create Route53 records
  - **IP + HTTP mode**
    - Leave `FRONTEND_DOMAIN` and `BACKEND_DOMAIN` empty
    - Set `CREATE_ROUTE53_RECORDS=false`

3) Run bootstrap:

```bash
./scripts/bootstrap-deploy.sh
```

This command:

- runs `terraform init/apply` in `infra/ec2`
- reads instance IP outputs
- deploys backend + frontend over SSH
- configures domains/HTTPS only when domains are provided
- falls back to IP-based HTTP URLs when domains are omitted
- runs smoke checks and prints final URLs

### Notes

- Domain mode requires DNS to resolve to the instance IPs before TLS can be issued.
- If DNS is not ready yet, deployment still succeeds on HTTP and you can rerun bootstrap later to enable HTTPS.

### Optional GitHub workflow deploy mode

The `Deploy EC2` workflow also supports both routing modes:

- Domain + HTTPS mode:
  - set `FRONTEND_APP_DOMAIN` and `BACKEND_APP_DOMAIN` secrets
- IP + HTTP mode:
  - leave `FRONTEND_APP_DOMAIN` and `BACKEND_APP_DOMAIN` empty
  - workflow falls back to `http://<EC2_HOST>` automatically

Required deploy secrets include:

- `EC2_FRONTEND_HOST`, `EC2_BACKEND_HOST`, `EC2_USER`, `EC2_SSH_PRIVATE_KEY`
- `OPENAI_API_KEY`, `MCP_SERVER_URL`, `POSTGRES_PASSWORD`
- optional: `LETSENCRYPT_EMAIL`, `CORS_ALLOWED_ORIGINS`
