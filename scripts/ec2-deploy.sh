#!/usr/bin/env bash

set -euo pipefail

if [ -z "${APP_DOMAIN:-}" ]; then
  echo "APP_DOMAIN is required."
  exit 1
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is required."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

sudo rm -f /etc/apt/sources.list.d/caddy-stable.list
sudo rm -f /etc/apt/keyrings/caddy-stable-archive-keyring.gpg

sudo apt-get update
sudo apt-get install -y ca-certificates curl git postgresql postgresql-contrib python3 python3-pip nginx certbot python3-certbot-nginx

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

export PATH="$HOME/.local/bin:$PATH"

sudo mkdir -p /opt/meridian
sudo chown -R "$USER:$USER" /opt/meridian

cd /opt/meridian
if [ "${SKIP_GIT_PULL:-0}" != "1" ]; then
  if [ ! -d /opt/meridian/.git ]; then
    git clone https://github.com/techmornach/Meridian-Support-Chatbot.git /opt/meridian
  fi
  git fetch --all
  git reset --hard origin/main
fi

POSTGRES_DB="${POSTGRES_DB:-meridian_chatbot}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
GUARDRAIL_MODEL="${GUARDRAIL_MODEL:-gpt-4o-mini}"
MCP_SERVER_URL="${MCP_SERVER_URL:-https://order-mcp-74afyau24q-uc.a.run.app/mcp}"
AUTH_TOKEN_TTL_SECONDS="${AUTH_TOKEN_TTL_SECONDS:-3600}"
MAX_INPUT_CHARS="${MAX_INPUT_CHARS:-4000}"
HISTORY_CONTEXT_LIMIT="${HISTORY_CONTEXT_LIMIT:-30}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
ENABLE_OPENAI_TRACING="${ENABLE_OPENAI_TRACING:-true}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@home.jaraflytech.com}"
DATABASE_URL="postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:5432/${POSTGRES_DB}"

sudo systemctl enable postgresql
sudo systemctl restart postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';" postgres
sudo -u postgres psql -v ON_ERROR_STOP=1 -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'" | grep -q 1 || sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${POSTGRES_DB};" postgres

cat > /opt/meridian/.env <<EOF
OPENAI_API_KEY=${OPENAI_API_KEY}
OPENAI_MODEL=${OPENAI_MODEL}
GUARDRAIL_MODEL=${GUARDRAIL_MODEL}
MCP_SERVER_URL=${MCP_SERVER_URL}
DATABASE_URL=${DATABASE_URL}
AUTH_TOKEN_TTL_SECONDS=${AUTH_TOKEN_TTL_SECONDS}
MAX_INPUT_CHARS=${MAX_INPUT_CHARS}
HISTORY_CONTEXT_LIMIT=${HISTORY_CONTEXT_LIMIT}
LOG_LEVEL=${LOG_LEVEL}
ENABLE_OPENAI_TRACING=${ENABLE_OPENAI_TRACING}
CORS_ALLOWED_ORIGINS=https://${APP_DOMAIN}
BACKEND_API_URL=http://127.0.0.1:8000
NEXT_PUBLIC_BACKEND_API_URL=
EOF

uv sync --frozen --no-dev
if [ -f frontend/package-lock.json ]; then
  npm --prefix frontend ci
else
  npm --prefix frontend install
fi
npm --prefix frontend run build

sudo tee /etc/systemd/system/meridian-backend.service >/dev/null <<'EOF'
[Unit]
Description=Meridian FastAPI backend
After=network.target postgresql.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/meridian
EnvironmentFile=/opt/meridian/.env
ExecStart=/home/ubuntu/.local/bin/uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/meridian-frontend.service >/dev/null <<'EOF'
[Unit]
Description=Meridian Next.js frontend
After=network.target meridian-backend.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/meridian
EnvironmentFile=/opt/meridian/.env
ExecStart=/usr/bin/npm --prefix frontend run start -- --hostname 127.0.0.1 --port 3000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/nginx/sites-available/meridian.conf >/dev/null <<EOF
server {
  listen 80;
  server_name ${APP_DOMAIN};

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/meridian.conf /etc/nginx/sites-enabled/meridian.conf

sudo systemctl daemon-reload
sudo systemctl enable meridian-backend meridian-frontend nginx
sudo systemctl restart meridian-backend
sudo systemctl restart meridian-frontend
sudo systemctl restart nginx

sudo certbot --nginx -d "${APP_DOMAIN}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}" --redirect

echo "Deployment completed: https://${APP_DOMAIN}/"
