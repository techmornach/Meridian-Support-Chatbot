FROM node:20-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/root/.local/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    curl \
    ca-certificates \
    postgresql \
    postgresql-contrib \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY app ./app
COPY scripts ./scripts

COPY frontend/package*.json ./frontend/
RUN npm --prefix frontend ci
COPY frontend ./frontend
RUN npm --prefix frontend run build

RUN chmod +x /app/scripts/apprunner-start.sh && mkdir -p /var/lib/postgresql/data

ENV PORT=3000 \
    BACKEND_PORT=8000 \
    POSTGRES_DB=meridian_chatbot \
    POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres \
    DATABASE_URL=postgresql+asyncpg://postgres:postgres@127.0.0.1:5432/meridian_chatbot \
    BACKEND_API_URL=http://127.0.0.1:8000 \
    CORS_ALLOWED_ORIGINS=* \
    PGDATA=/var/lib/postgresql/data

EXPOSE 3000

ENTRYPOINT ["tini", "--"]
CMD ["/app/scripts/apprunner-start.sh"]
