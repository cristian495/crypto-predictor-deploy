# Worker de señales en vivo (paper trading) para Buy-the-Dip.
# Contenedor EFÍMERO: se levanta, ejecuta UNA tarea (scan|resolve|export) y se apaga.
# El horario lo pone el cron del VPS (ver COMMANDS.md), NO cron dentro del contenedor.
# Contexto de build: la carpeta `worker/`.
#
#   docker compose run --rm worker scan      # un escaneo
#   docker compose run --rm worker export     # regenerar los JSON de la UI
FROM python:3.12-slim-bookworm

# ca-certificates para HTTPS (ccxt/Binance, Discord). tzdata para la hora en logs.
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencias minimas del worker (NO las de ML: el worker solo escanea + alerta).
COPY requirements-worker.txt ./
RUN pip install --no-cache-dir -r requirements-worker.txt

# Un unico script: traduce la tarea (scan|resolve|export) al comando Python.
COPY run-task.sh /app/run-task.sh
RUN chmod +x /app/run-task.sh

# El engine se monta aqui (volumen de solo lectura desde repos/engine).
ENV ENGINE_DIR=/engine
# Donde persiste el log de señales / JSON (volumen nombrado del compose).
ENV DATA_DIR=/data

# La tarea se pasa como argumento:  docker compose run --rm worker <scan|resolve|export>
ENTRYPOINT ["/app/run-task.sh"]
