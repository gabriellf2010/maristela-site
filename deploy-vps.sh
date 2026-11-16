#!/usr/bin/env bash
# Deploy isolado: maristelabarbosa.kaenghub.com.br
# Stack proprio (/opt/maristela-site), container proprio, porta 127.0.0.1:8081.
# Nao toca em waha, creative-hub nem em outros vhosts.
set -euo pipefail

DOMAIN="maristelabarbosa.kaenghub.com.br"
DIR="/opt/maristela-site"
PORT=8081
REPO="https://github.com/gabriellf2010/maristela-site.git"

command -v docker >/dev/null || { echo "ERRO: docker nao instalado"; exit 1; }

if ss -ltn "sport = :$PORT" | grep -q LISTEN && ! docker ps --format '{{.Names}}' | grep -qx maristela-site; then
  echo "ERRO: porta $PORT ocupada por outro servico. Edite PORT no script."; exit 1
fi

echo "== Arquivos"
command -v git >/dev/null || apt-get install -y git
mkdir -p "$DIR"
if [ -d "$DIR/repo/.git" ]; then git -C "$DIR/repo" pull --ff-only; else git clone --depth 1 "$REPO" "$DIR/repo"; fi
[ -f "$DIR/repo/site/server.js" ] || { echo "ERRO: server.js ausente"; exit 1; }

echo "== Compose"
cat > "$DIR/compose.yaml" <<EOF
name: maristela-site
services:
  web:
    container_name: maristela-site
    image: node:22-alpine
    working_dir: /app
    command: ["node", "server.js", "--no-open", "--port", "3000"]
    environment:
      HOST: "0.0.0.0"
    volumes:
      - ./repo/site:/app:ro
    ports:
      - "127.0.0.1:${PORT}:3000"
    restart: unless-stopped
    mem_limit: 256m
EOF
docker compose -f "$DIR/compose.yaml" up -d
sleep 3
curl -fsS -o /dev/null -w "container HTTP %{http_code}\n" "http://127.0.0.1:$PORT/" \
  || { docker logs --tail 30 maristela-site; exit 1; }

echo "== Quem escuta 80/443 hoje"
ss -ltnp | grep -E ':(80|443)\s' || echo "(ninguem)"

if systemctl is-active --quiet nginx; then
  echo "== nginx do host detectado: criando vhost"
  [ -d /etc/nginx/conf.d ] || { echo "sem /etc/nginx/conf.d"; exit 1; }
  cat > /etc/nginx/conf.d/maristelabarbosa.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  nginx -t && systemctl reload nginx
  command -v certbot >/dev/null || apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect
  nginx -t && systemctl reload nginx
  curl -fsSI "https://$DOMAIN/" | head -n 1
  echo "PRONTO: https://$DOMAIN"
else
  echo
  echo "PAROU antes do proxy: nginx do host NAO esta ativo."
  echo "O container ja responde em 127.0.0.1:$PORT. Cole a saida acima de 'Quem escuta 80/443' no chat."
fi
