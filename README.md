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

## Deploy to AWS App Runner (single container)

This repo now includes a simple single-container deployment setup for:

- Next.js frontend
- FastAPI backend
- PostgreSQL database (inside the same container)

### Important limitation

Because PostgreSQL runs inside the App Runner container, data is ephemeral and can be lost on replacement/redeploy events. This is suitable for demos/POCs, not durable production data.

### Files added for deployment

- `Dockerfile`
- `scripts/apprunner-start.sh`
- `infra/apprunner/*.tf` (Terraform for ECR + App Runner)
- `.github/workflows/terraform-apprunner.yml`
- `.github/workflows/deploy-apprunner.yml`

### 1) Provision infrastructure with Terraform

```bash
cd infra/apprunner
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars (set openai_api_key at minimum)
terraform init
# first bootstrap pass (creates ECR + IAM role used by App Runner)
terraform apply -target=aws_ecr_repository.app -target=aws_iam_role.apprunner_access_role -target=aws_iam_role_policy_attachment.apprunner_ecr_access
```

Push a bootstrap image before creating the App Runner service:

```bash
ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "${ECR_REPOSITORY_URL%/*}"
docker build -t "$ECR_REPOSITORY_URL:latest" ../..
docker push "$ECR_REPOSITORY_URL:latest"
terraform apply
```

Save outputs:

- `ecr_repository_url`
- `apprunner_service_arn`
- `apprunner_service_url`

### 2) Configure GitHub repository secrets

Set these secrets in your GitHub repo:

- `AWS_ROLE_TO_ASSUME` (OIDC role for GitHub Actions)
- `AWS_REGION` (e.g. `us-east-1`)
- `ECR_REPOSITORY` (repository name, e.g. `meridian-support-chatbot-app`)
- `APP_RUNNER_SERVICE_ARN` (from Terraform output)
- `OPENAI_API_KEY` (used by Terraform workflow)

### 3) Deploy flow

- Run `Terraform App Runner` workflow once (or whenever infra changes).
- Push to `main` (or trigger `Deploy App Runner` workflow manually).
- Workflow builds/pushes Docker image to ECR and triggers `start-deployment` on App Runner.

### 4) Destroy infrastructure

- Run `Terraform Destroy App Runner` workflow manually.
- In the workflow input, set `confirm_destroy` to `DESTROY`.
- This tears down App Runner + ECR resources managed by `infra/apprunner`.
