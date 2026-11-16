#!/usr/bin/env bash
# Deploy isolado: maristelabarbosa.kaenghub.com.br
# Stack Swarm proprio "maristela", roteado pelo Traefik ja existente (labels).
# Nao toca em nenhum outro servico.
set -euo pipefail

DOMAIN="maristelabarbosa.kaenghub.com.br"
DIR="/opt/maristela-site"
REPO="https://github.com/gabriellf2010/maristela-site.git"
NET="network_swarm_public"

docker network inspect "$NET" >/dev/null 2>&1 || { echo "ERRO: rede $NET nao existe"; exit 1; }
docker service ls --format '{{.Name}}' | grep -q '^traefik_traefik$' || { echo "ERRO: servico traefik_traefik nao encontrado"; exit 1; }

echo "== Arquivos"
command -v git >/dev/null || apt-get install -y git
mkdir -p "$DIR"
if [ -d "$DIR/repo/.git" ]; then git -C "$DIR/repo" pull --ff-only; else git clone --depth 1 "$REPO" "$DIR/repo"; fi
[ -f "$DIR/repo/site/server.js" ] || { echo "ERRO: server.js ausente"; exit 1; }

echo "== Remove teste standalone (se existir)"
if [ -f "$DIR/compose.yaml" ]; then docker compose -f "$DIR/compose.yaml" down || true; rm -f "$DIR/compose.yaml"; fi

echo "== Stack swarm"
cat > "$DIR/stack.yaml" <<EOF
version: "3.8"
services:
  web:
    image: node:22-alpine
    working_dir: /app
    command: ["node", "server.js", "--no-open", "--port", "3000"]
    environment:
      HOST: "0.0.0.0"
    volumes:
      - $DIR/repo/site:/app:ro
    networks:
      - $NET
    deploy:
      replicas: 1
      restart_policy:
        condition: any
      resources:
        limits:
          memory: 256M
      labels:
        - traefik.enable=true
        - traefik.docker.network=$NET
        - traefik.http.routers.maristela.rule=Host(\`$DOMAIN\`)
        - traefik.http.routers.maristela.entrypoints=websecure
        - traefik.http.routers.maristela.tls=true
        - traefik.http.routers.maristela.tls.certresolver=letsencryptresolver
        - traefik.http.services.maristela.loadbalancer.server.port=3000
networks:
  $NET:
    external: true
EOF
docker stack deploy -c "$DIR/stack.yaml" maristela

echo "== Aguardando (ate ~2 min) HTTPS"
for i in $(seq 1 24); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$DOMAIN/" || true)
  echo "tentativa $i: HTTP $code"
  [ "$code" = "200" ] && { echo "PRONTO: https://$DOMAIN"; exit 0; }
  sleep 5
done
echo "Ainda sem 200. Diagnostico:"
docker service ps maristela_web --no-trunc | head -5
docker service logs --tail 15 maristela_web 2>&1 | tail -15
