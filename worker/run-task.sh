#!/usr/bin/env bash
# Ejecuta UNA tarea del worker (scan | resolve | export) y termina.
# Es el ENTRYPOINT del contenedor: se invoca con `docker compose run --rm worker <tarea>`
# desde el cron del VPS. La config viene del entorno (inyectado por el compose desde el .env).
set -euo pipefail

ENGINE_DIR="${ENGINE_DIR:-/engine}"
DATA_DIR="${DATA_DIR:-/data}"
LOG_PATH="${DATA_DIR}/live_signals.jsonl"
RESULTS_PATH="${DATA_DIR}/live_results.jsonl"
SUMMARY_PATH="${DATA_DIR}/live_summary.json"
BACKTEST_JSON="${DATA_DIR}/buy_the_dip/backtest.latest.json"   # opcional (comparar vivo-vs-backtest)

mkdir -p "${DATA_DIR}"
cd "${ENGINE_DIR}/buy_the_dip"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

case "${1:-}" in
  scan)
    echo "[$(ts)] scan: live_signals"
    python live_signals.py --log-path "${LOG_PATH}"
    ;;
  resolve)
    echo "[$(ts)] resolve: resolve_signals"
    ARGS=(--log-path "${LOG_PATH}" --results-path "${RESULTS_PATH}" --summary-path "${SUMMARY_PATH}")
    [ -f "${BACKTEST_JSON}" ] && ARGS+=(--backtest-json "${BACKTEST_JSON}")
    python resolve_signals.py "${ARGS[@]}"
    ;;
  export)
    # Genera backtest/signals/portfolio JSON al volumen compartido (los sirve la UI).
    # La UI los pide en /data/buy_the_dip/*.json, asi que escribimos en esa subcarpeta.
    # Pesado (baja OHLCV+funding de toda la cesta): se corre 1x/dia, no cada hora.
    echo "[$(ts)] export: export_frontend_data -> ${DATA_DIR}/buy_the_dip"
    python export_frontend_data.py --out-dir "${DATA_DIR}/buy_the_dip"
    ;;
  *)
    echo "uso: run-task.sh {scan|resolve|export}" >&2
    exit 2
    ;;
esac
