# Worker de señales en vivo (paper trading) para Buy-the-Dip.
# Contexto de build: la carpeta `worker/` del repo predictor-deploy.
# El CODIGO del engine se monta en runtime desde repos/engine (volumen del compose),
# asi que `make deploy-worker` + git pull del engine basta para actualizar sin rebuild.
#
#   docker build -t predictor-worker ./worker
FROM python:3.12-slim-bookworm

# cron para la planificacion horaria; tzdata para la hora local; ca-certificates para HTTPS (ccxt/discord).
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends cron tzdata ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencias minimas del worker (NO las de ML: el worker solo escanea + alerta).
COPY requirements-worker.txt ./
RUN pip install --no-cache-dir -r requirements-worker.txt

# Scripts de planificacion y arranque.
COPY entrypoint.sh /app/entrypoint.sh
COPY crontab /app/crontab
COPY run-task.sh /app/run-task.sh
RUN chmod +x /app/entrypoint.sh /app/run-task.sh

# El engine se monta aqui (volumen de solo lectura desde repos/engine).
ENV ENGINE_DIR=/engine
# Donde persiste el log de señales (volumen nombrado del compose).
ENV DATA_DIR=/data

ENTRYPOINT ["/app/entrypoint.sh"]
