#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-${ROOT_DIR}/deploy/.env}"
TF_DIR="${ROOT_DIR}/infra/ec2"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Config file not found: ${ENV_FILE}"
  echo "Create it from deploy/.env.example"
  exit 1
fi

for cmd in terraform ssh scp curl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    exit 1
  fi
done

set -a
source "${ENV_FILE}"
set +a

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is required in ${ENV_FILE}"
  exit 1
fi

if [ -z "${SSH_PRIVATE_KEY_PATH:-}" ]; then
  echo "SSH_PRIVATE_KEY_PATH is required in ${ENV_FILE}"
  exit 1
fi

if [ ! -f "${SSH_PRIVATE_KEY_PATH}" ]; then
  echo "SSH private key not found: ${SSH_PRIVATE_KEY_PATH}"
  exit 1
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-meridian-support-chatbot}"
FRONTEND_INSTANCE_TYPE="${FRONTEND_INSTANCE_TYPE:-t3.small}"
BACKEND_INSTANCE_TYPE="${BACKEND_INSTANCE_TYPE:-t3.small}"
SSH_KEY_NAME="${SSH_KEY_NAME:-}"
ALLOWED_SSH_CIDR="${ALLOWED_SSH_CIDR:-0.0.0.0/0}"
AVAILABILITY_ZONE="${AVAILABILITY_ZONE:-us-east-1a}"

CREATE_ROUTE53_RECORDS="${CREATE_ROUTE53_RECORDS:-false}"
HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-}"
FRONTEND_SUBDOMAIN="${FRONTEND_SUBDOMAIN:-meridian}"
BACKEND_SUBDOMAIN="${BACKEND_SUBDOMAIN:-api}"
FRONTEND_DOMAIN="${FRONTEND_DOMAIN:-}"
BACKEND_DOMAIN="${BACKEND_DOMAIN:-}"

EC2_USER="${EC2_USER:-ubuntu}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@home.jaraflytech.com}"

OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
GUARDRAIL_MODEL="${GUARDRAIL_MODEL:-gpt-4o-mini}"
MCP_SERVER_URL="${MCP_SERVER_URL:-https://order-mcp-74afyau24q-uc.a.run.app/mcp}"
POSTGRES_DB="${POSTGRES_DB:-meridian_chatbot}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
AUTH_TOKEN_TTL_SECONDS="${AUTH_TOKEN_TTL_SECONDS:-3600}"
MAX_INPUT_CHARS="${MAX_INPUT_CHARS:-4000}"
HISTORY_CONTEXT_LIMIT="${HISTORY_CONTEXT_LIMIT:-30}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
ENABLE_OPENAI_TRACING="${ENABLE_OPENAI_TRACING:-true}"

tfvars_file="$(mktemp)"
cleanup() {
  rm -f "${tfvars_file}"
}
trap cleanup EXIT

cat > "${tfvars_file}" <<EOF
aws_region              = "${AWS_REGION}"
project_name            = "${PROJECT_NAME}"
frontend_instance_type  = "${FRONTEND_INSTANCE_TYPE}"
backend_instance_type   = "${BACKEND_INSTANCE_TYPE}"
ssh_key_name            = "${SSH_KEY_NAME}"
allowed_ssh_cidr        = "${ALLOWED_SSH_CIDR}"
availability_zone       = "${AVAILABILITY_ZONE}"
create_route53_records  = ${CREATE_ROUTE53_RECORDS}
hosted_zone_name        = "${HOSTED_ZONE_NAME}"
frontend_subdomain      = "${FRONTEND_SUBDOMAIN}"
backend_subdomain       = "${BACKEND_SUBDOMAIN}"
frontend_domain         = "${FRONTEND_DOMAIN}"
backend_domain          = "${BACKEND_DOMAIN}"
EOF

echo "Applying Terraform in ${TF_DIR}..."
terraform -chdir="${TF_DIR}" init
terraform -chdir="${TF_DIR}" apply -auto-approve -var-file="${tfvars_file}"

FRONTEND_IP="$(terraform -chdir="${TF_DIR}" output -raw frontend_public_ip)"
BACKEND_IP="$(terraform -chdir="${TF_DIR}" output -raw backend_public_ip)"

if [ -n "${FRONTEND_DOMAIN}" ]; then
  FRONTEND_PUBLIC_URL="https://${FRONTEND_DOMAIN}"
else
  FRONTEND_PUBLIC_URL="http://${FRONTEND_IP}"
fi

if [ -n "${BACKEND_DOMAIN}" ]; then
  BACKEND_PUBLIC_URL="https://${BACKEND_DOMAIN}"
else
  BACKEND_PUBLIC_URL="http://${BACKEND_IP}"
fi

if [ -z "${CORS_ALLOWED_ORIGINS:-}" ]; then
  CORS_ALLOWED_ORIGINS="${FRONTEND_PUBLIC_URL}"
fi

ssh_opts=(-i "${SSH_PRIVATE_KEY_PATH}" -o StrictHostKeyChecking=no)

wait_for_ssh() {
  local host="$1"
  for attempt in $(seq 1 40); do
    if ssh "${ssh_opts[@]}" "${EC2_USER}@${host}" "echo ready" >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
    echo "Waiting for SSH (${attempt}/40) on ${host}..."
  done
  return 1
}

echo "Waiting for EC2 instances to accept SSH..."
wait_for_ssh "${BACKEND_IP}"
wait_for_ssh "${FRONTEND_IP}"

echo "Deploying backend..."
scp "${ssh_opts[@]}" "${ROOT_DIR}/scripts/ec2-deploy-backend.sh" "${EC2_USER}@${BACKEND_IP}:/tmp/ec2-deploy-backend.sh"
ssh "${ssh_opts[@]}" "${EC2_USER}@${BACKEND_IP}" "\
  chmod +x /tmp/ec2-deploy-backend.sh && \
  APP_DOMAIN='${BACKEND_DOMAIN}' \
  APP_PUBLIC_IP='${BACKEND_IP}' \
  FRONTEND_PUBLIC_ORIGIN='${FRONTEND_PUBLIC_URL}' \
  CORS_ALLOWED_ORIGINS='${CORS_ALLOWED_ORIGINS}' \
  OPENAI_API_KEY='${OPENAI_API_KEY}' \
  OPENAI_MODEL='${OPENAI_MODEL}' \
  GUARDRAIL_MODEL='${GUARDRAIL_MODEL}' \
  MCP_SERVER_URL='${MCP_SERVER_URL}' \
  POSTGRES_DB='${POSTGRES_DB}' \
  POSTGRES_USER='${POSTGRES_USER}' \
  POSTGRES_PASSWORD='${POSTGRES_PASSWORD}' \
  AUTH_TOKEN_TTL_SECONDS='${AUTH_TOKEN_TTL_SECONDS}' \
  MAX_INPUT_CHARS='${MAX_INPUT_CHARS}' \
  HISTORY_CONTEXT_LIMIT='${HISTORY_CONTEXT_LIMIT}' \
  LOG_LEVEL='${LOG_LEVEL}' \
  ENABLE_OPENAI_TRACING='${ENABLE_OPENAI_TRACING}' \
  LETSENCRYPT_EMAIL='${LETSENCRYPT_EMAIL}' \
  /tmp/ec2-deploy-backend.sh"

echo "Deploying frontend..."
scp "${ssh_opts[@]}" "${ROOT_DIR}/scripts/ec2-deploy-frontend.sh" "${EC2_USER}@${FRONTEND_IP}:/tmp/ec2-deploy-frontend.sh"
ssh "${ssh_opts[@]}" "${EC2_USER}@${FRONTEND_IP}" "\
  chmod +x /tmp/ec2-deploy-frontend.sh && \
  APP_DOMAIN='${FRONTEND_DOMAIN}' \
  APP_PUBLIC_IP='${FRONTEND_IP}' \
  BACKEND_PUBLIC_URL='${BACKEND_PUBLIC_URL}' \
  LETSENCRYPT_EMAIL='${LETSENCRYPT_EMAIL}' \
  /tmp/ec2-deploy-frontend.sh"

echo "Running smoke checks..."
curl --max-time 30 -fsS "${BACKEND_PUBLIC_URL}/health" >/dev/null
curl --max-time 30 -fsS "${FRONTEND_PUBLIC_URL}" >/dev/null

echo
echo "Deployment complete."
echo "Frontend URL: ${FRONTEND_PUBLIC_URL}"
echo "Backend URL:  ${BACKEND_PUBLIC_URL}"
echo "Backend health: ${BACKEND_PUBLIC_URL}/health"
