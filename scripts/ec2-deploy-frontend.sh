#!/usr/bin/env bash

set -euo pipefail

if [ -z "${APP_DOMAIN:-}" ]; then
  echo "APP_DOMAIN is required."
  exit 1
fi

if [ -z "${BACKEND_PUBLIC_URL:-}" ]; then
  echo "BACKEND_PUBLIC_URL is required."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y ca-certificates curl git nginx certbot python3-certbot-nginx

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

sudo mkdir -p /opt/meridian
sudo chown -R "$USER:$USER" /opt/meridian

if [ ! -d /opt/meridian/.git ]; then
  git clone https://github.com/techmornach/Meridian-Support-Chatbot.git /opt/meridian
fi

cd /opt/meridian
if [ "${SKIP_GIT_PULL:-0}" != "1" ]; then
  git fetch --all
  git reset --hard origin/main
fi

LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-admin@home.jaraflytech.com}"

cat > /opt/meridian/.frontend.env <<EOF
BACKEND_API_URL=${BACKEND_PUBLIC_URL}
NEXT_PUBLIC_BACKEND_API_URL=
EOF

if [ -f frontend/package-lock.json ]; then
  npm --prefix frontend ci
else
  npm --prefix frontend install
fi
npm --prefix frontend run build

sudo tee /etc/systemd/system/meridian-frontend.service >/dev/null <<'EOF'
[Unit]
Description=Meridian Next.js frontend
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/meridian
EnvironmentFile=/opt/meridian/.frontend.env
ExecStart=/usr/bin/npm --prefix frontend run start -- --hostname 127.0.0.1 --port 3000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/nginx/sites-available/meridian-frontend.conf >/dev/null <<EOF
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
sudo ln -sf /etc/nginx/sites-available/meridian-frontend.conf /etc/nginx/sites-enabled/meridian-frontend.conf

sudo systemctl daemon-reload
sudo systemctl enable meridian-frontend nginx
sudo systemctl restart meridian-frontend
sudo systemctl restart nginx

if getent hosts "${APP_DOMAIN}" >/dev/null 2>&1; then
  sudo certbot --nginx -d "${APP_DOMAIN}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}" --redirect || true
fi

echo "Frontend deployed: https://${APP_DOMAIN}/"
