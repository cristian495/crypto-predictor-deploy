# Deploy del stack predictor (worker + web) — comandos por entorno.
# Correr desde ~/deploys/predictor/<env>. `make help` lista todo.

.DEFAULT_GOAL := help
.PHONY: help deploy pull up deploy-worker deploy-web logs logs-web ps restart down \
        scan resolve export test-alert tail-log

help:  ## lista los comandos
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

deploy: pull up  ## git pull de engine+ui + rebuild + up

pull:  ## actualiza engine y ui (fast-forward en las ramas del .env)
	@EB=$$(grep '^ENGINE_BRANCH=' .env | cut -d= -f2); \
	 UB=$$(grep '^UI_BRANCH=' .env | cut -d= -f2); \
	 echo ">> engine ($$EB)"; \
	 git -C repos/engine fetch origin --quiet && git -C repos/engine checkout $$EB --quiet && git -C repos/engine pull --ff-only; \
	 echo ">> ui ($$UB)"; \
	 git -C repos/ui fetch origin --quiet && git -C repos/ui checkout $$UB --quiet && git -C repos/ui pull --ff-only

up:  ## rebuild + levantar todo (conserva el volumen de datos)
	docker compose up -d --build

deploy-worker:  ## git pull del engine + rebuild SOLO del worker
	git -C repos/engine pull --ff-only && docker compose up -d --build worker

deploy-web:  ## git pull de la ui + rebuild SOLO de la web
	git -C repos/ui pull --ff-only && docker compose up -d --build web

logs:      ; docker compose logs -f --tail=100          ## seguir logs de todo
logs-web:  ; docker compose logs -f --tail=100 web       ## solo logs de la web
ps:        ; docker compose ps                           ## estado de contenedores
restart:   ; docker compose restart                      ## reiniciar todo
down:      ; docker compose down                         ## bajar (SIN -v, conserva datos)

scan:  ## correr un scan AHORA (manual)
	docker compose exec worker /app/run-task.sh scan

resolve:  ## resolver resultados AHORA (manual)
	docker compose exec worker /app/run-task.sh resolve

export:  ## regenerar backtest/signals/portfolio JSON AHORA (para la UI)
	docker compose exec worker /app/run-task.sh export

test-alert:  ## enviar una alerta de prueba a Discord
	docker compose exec worker sh -c 'cd $$ENGINE_DIR/buy_the_dip && . /etc/environment && python live_signals.py --test-alert'

tail-log:  ## ver las ultimas señales registradas
	docker compose exec worker sh -c 'tail -n 20 /data/live_signals.jsonl 2>/dev/null || echo "(aun no hay señales)"'
