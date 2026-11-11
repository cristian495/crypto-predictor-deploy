#!/usr/bin/env bash
# Setup idempotente del stack predictor (worker + web) en un VPS.
# TODO lo variable vive en .env — este script no hardcodea.
# Clona/actualiza engine y ui en repos/, y renderiza el server block de Nginx del host.
# NO levanta el stack (eso lo hace `make deploy`).
set -euo pipefail

# ── 1. .env obligatorio ──────────────────────────────────────────────────────
if [ ! -f .env ]; then
  echo "ERROR: falta .env. Créalo y edítalo antes de correr bootstrap:" >&2
  echo "  cp .env.example .env && nano .env" >&2
  exit 1
fi

# ── 2. Cargar el .env al entorno del shell (envsubst lo ve) ──────────────────
set -a; source ./.env; set +a

# ── 3. Validar lo obligatorio ────────────────────────────────────────────────
: "${ENGINE_REPO:?falta ENGINE_REPO en .env}"
: "${ENGINE_BRANCH:?falta ENGINE_BRANCH en .env}"
: "${UI_REPO:?falta UI_REPO en .env}"
: "${UI_BRANCH:?falta UI_BRANCH en .env}"
: "${COMPOSE_PROJECT_NAME:?falta COMPOSE_PROJECT_NAME en .env}"
: "${DOMAIN:?falta DOMAIN en .env}"
: "${APP_HOST:?falta APP_HOST en .env}"
: "${WEB_PORT:?falta WEB_PORT en .env}"

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "→ (aviso) DISCORD_WEBHOOK_URL vacío: el worker registrará señales pero NO alertará."
fi

# ── 4. Clonar / actualizar repos en repos/ (carpetas cortas = servicios del compose) ──
mkdir -p repos
clone() {  # $1=carpeta  $2=url  $3=rama
  if [ -d "repos/$1/.git" ]; then
    echo "→ Actualizando repos/$1 (rama $3)"
    git -C "repos/$1" fetch origin --quiet
    git -C "repos/$1" checkout "$3" --quiet
    git -C "repos/$1" pull --ff-only --quiet
  else
    echo "→ Clonando $1 ($3)"
    git clone -b "$3" "$2" "repos/$1"
  fi
}
clone engine "$ENGINE_REPO" "$ENGINE_BRANCH"
clone ui     "$UI_REPO"     "$UI_BRANCH"

# ── 5. Nginx del host: snippets compartidos + server block RENDERIZADO ────────
# Precondición: el snippet SSL de la zona debe existir (el template hace `include ssl-${DOMAIN}.conf`).
if [ ! -f "nginx/snippets/ssl-${DOMAIN}.conf" ]; then
  echo "ERROR: falta nginx/snippets/ssl-${DOMAIN}.conf para DOMAIN=${DOMAIN}." >&2
  echo "  Crea ese snippet + su Origin cert en /etc/ssl/cloudflare/${DOMAIN}/ (igual que en BooLend)." >&2
  exit 1
fi
sudo mkdir -p /etc/nginx/snippets
sudo cp nginx/snippets/*.conf /etc/nginx/snippets/
envsubst '${APP_HOST} ${DOMAIN} ${WEB_PORT}' \
  < nginx/site.conf.template \
  | sudo tee "/etc/nginx/sites-available/${COMPOSE_PROJECT_NAME}.conf" >/dev/null
sudo ln -sf "/etc/nginx/sites-available/${COMPOSE_PROJECT_NAME}.conf" "/etc/nginx/sites-enabled/${COMPOSE_PROJECT_NAME}.conf"
sudo nginx -t && sudo systemctl reload nginx

echo "✓ Bootstrap listo — ${COMPOSE_PROJECT_NAME}"
echo "  engine: $(git -C repos/engine rev-parse --short HEAD) (${ENGINE_BRANCH})"
echo "  ui:     $(git -C repos/ui rev-parse --short HEAD) (${UI_BRANCH})"
echo "  web:    https://${APP_HOST}"
echo "  Siguiente:  make deploy"
