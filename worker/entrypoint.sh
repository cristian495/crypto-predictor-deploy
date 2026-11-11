#!/usr/bin/env bash
# Arranque del worker: prepara el entorno para cron, instala el crontab y corre cron en foreground.
set -euo pipefail

echo "[entrypoint] Buy-the-Dip live signals worker"
echo "[entrypoint] ENGINE_DIR=${ENGINE_DIR:-/engine}  DATA_DIR=${DATA_DIR:-/data}  TZ=${TZ:-UTC}"

# cron no hereda el entorno del contenedor. Volcamos las variables relevantes a /etc/environment,
# de donde el crontab hace `source`. Filtramos ruido y escapamos comillas.
{
  echo "ENGINE_DIR=${ENGINE_DIR:-/engine}"
  echo "DATA_DIR=${DATA_DIR:-/data}"
  echo "PYTHONUNBUFFERED=1"
  # Solo exportamos DISCORD_WEBHOOK_URL si viene definido (secreto, desde el .env del compose).
  if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
    echo "DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL}"
  fi
} > /etc/environment

# Validacion basica: el engine debe estar montado.
if [ ! -f "${ENGINE_DIR:-/engine}/buy_the_dip/live_signals.py" ]; then
  echo "[entrypoint] ERROR: no encuentro el engine en ${ENGINE_DIR:-/engine}/buy_the_dip/." >&2
  echo "[entrypoint]        ¿Esta clonado repos/engine y montado como volumen?" >&2
  exit 1
fi

mkdir -p "${DATA_DIR:-/data}"

# Instala el crontab.
crontab /app/crontab
echo "[entrypoint] crontab instalado:"
crontab -l | sed 's/^/[entrypoint]   /'

# Corrida inicial inmediata (no esperamos a la primera hora) para validar el despliegue.
# Si no hay señal, simplemente registra que escaneo; no falla el arranque si hay error de red.
echo "[entrypoint] corrida inicial de scan..."
. /etc/environment; /app/run-task.sh scan || echo "[entrypoint] (aviso) la corrida inicial fallo; cron reintentara cada hora"

# Export inicial en BACKGROUND (es pesado: baja OHLCV+funding de la cesta). Asi la UI
# tiene datos desde el primer arranque sin bloquear el inicio del worker.
# Solo si aun no existe el backtest.latest.json en el volumen (no repetir en cada reinicio).
if [ ! -f "${DATA_DIR:-/data}/buy_the_dip/backtest.latest.json" ]; then
  echo "[entrypoint] lanzando export inicial en background (para la UI)..."
  ( . /etc/environment; /app/run-task.sh export \
      && echo "[entrypoint] export inicial listo" \
      || echo "[entrypoint] (aviso) export inicial fallo; el cron de las 03:30 lo reintenta" ) &
fi

echo "[entrypoint] arrancando cron en foreground..."
# -f foreground, -L 2 loglevel moderado. cron se queda como PID 1.
exec cron -f -L 2
