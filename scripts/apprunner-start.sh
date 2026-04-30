#!/usr/bin/env bash

set -euo pipefail

POSTGRES_DB="${POSTGRES_DB:-meridian_chatbot}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
PGDATA="${PGDATA:-/var/lib/postgresql/data}"
PORT="${PORT:-3000}"
BACKEND_PORT="${BACKEND_PORT:-8000}"

mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  su -s /bin/bash postgres -c "/usr/lib/postgresql/15/bin/initdb -D '$PGDATA'"
fi

if ! su -s /bin/bash postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D '$PGDATA' status" >/dev/null 2>&1; then
  su -s /bin/bash postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D '$PGDATA' -o \"-c listen_addresses='127.0.0.1' -p 5432\" -w start"
fi

su -s /bin/bash postgres -c "psql -d postgres -v ON_ERROR_STOP=1 -c \"ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\""
su -s /bin/bash postgres -c "psql -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'\" | grep -q 1 || psql -d postgres -c \"CREATE DATABASE ${POSTGRES_DB};\""

export DATABASE_URL="${DATABASE_URL:-postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:5432/${POSTGRES_DB}}"
export BACKEND_API_URL="${BACKEND_API_URL:-http://127.0.0.1:${BACKEND_PORT}}"
export NEXT_PUBLIC_BACKEND_API_URL="${NEXT_PUBLIC_BACKEND_API_URL:-}"
export CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:-*}"

uv run uvicorn app.main:app --host 127.0.0.1 --port "${BACKEND_PORT}" &
BACKEND_PID=$!

cleanup() {
  kill "$BACKEND_PID" >/dev/null 2>&1 || true
  su -s /bin/bash postgres -c "/usr/lib/postgresql/15/bin/pg_ctl -D '$PGDATA' -m fast stop" >/dev/null 2>&1 || true
}
trap cleanup EXIT

npm --prefix frontend run start -- --hostname 0.0.0.0 --port "${PORT}"
