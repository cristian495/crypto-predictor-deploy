#!/usr/bin/env bash
# Ejecuta UNA tarea del worker (scan | resolve | export) y termina.
# Es el ENTRYPOINT del contenedor: se invoca con `docker compose run --rm worker <tarea>`
# desde el cron del VPS. La config viene del entorno (inyectado por el compose desde el .env).
#
# MULTI-ESTRATEGIA: la estrategia es un parametro (STRATEGY, default buy_the_dip).
# El worker es GENERICO: corre cualquier estrategia del engine que exponga los scripts
# live_signals.py / resolve_signals.py / export_frontend_data.py. Cada estrategia
# guarda sus datos en su propia subcarpeta /data/<STRATEGY>/ para no colisionar.
#   docker compose run --rm worker scan                       # buy_the_dip (default)
#   docker compose run --rm -e STRATEGY=mean_reversion worker scan
set -euo pipefail

STRATEGY="${STRATEGY:-buy_the_dip}"
ENGINE_DIR="${ENGINE_DIR:-/engine}"
DATA_DIR="${DATA_DIR:-/data}"

STRAT_DIR="${ENGINE_DIR}/${STRATEGY}"
STRAT_DATA="${DATA_DIR}/${STRATEGY}"
LOG_PATH="${STRAT_DATA}/live_signals.jsonl"
RESULTS_PATH="${STRAT_DATA}/live_results.jsonl"
SUMMARY_PATH="${STRAT_DATA}/live_summary.json"
BACKTEST_JSON="${STRAT_DATA}/backtest.latest.json"   # opcional (comparar vivo-vs-backtest)

if [ ! -d "${STRAT_DIR}" ]; then
  echo "ERROR: no existe la estrategia '${STRATEGY}' en ${ENGINE_DIR}/." >&2
  exit 1
fi

mkdir -p "${STRAT_DATA}"
cd "${STRAT_DIR}"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

case "${1:-}" in
  scan)
    echo "[$(ts)] [${STRATEGY}] scan: live_signals"
    python live_signals.py --log-path "${LOG_PATH}"
    ;;
  resolve)
    echo "[$(ts)] [${STRATEGY}] resolve: resolve_signals"
    ARGS=(--log-path "${LOG_PATH}" --results-path "${RESULTS_PATH}" --summary-path "${SUMMARY_PATH}")
    [ -f "${BACKTEST_JSON}" ] && ARGS+=(--backtest-json "${BACKTEST_JSON}")
    python resolve_signals.py "${ARGS[@]}"
    ;;
  export)
    # Genera backtest/signals/portfolio JSON al volumen compartido (los sirve la UI).
    # La UI los pide en /data/<STRATEGY>/*.json. Pesado: se corre 1x/dia, no cada hora.
    echo "[$(ts)] [${STRATEGY}] export: export_frontend_data -> ${STRAT_DATA}"
    python export_frontend_data.py --out-dir "${STRAT_DATA}"
    ;;
  *)
    echo "uso: run-task.sh {scan|resolve|export}   (estrategia via STRATEGY=<nombre>)" >&2
    exit 2
    ;;
esac
