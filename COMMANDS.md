# Comandos del deploy — predictor (worker + web)

Copia-pega el comando que necesites. Todos son transparentes: no hay scripts que
oculten lógica. Corre siempre **desde la carpeta del entorno** (ej. `~/deploys/predictor`).

Antes de empezar: `cd ~/deploys/predictor`

---

## 1. Primer despliegue (una vez)

```bash
# Config del entorno (crea el .env con tus valores y el secreto de Discord)
cp .env.example .env
nano .env

# Clona engine + ui y configura el nginx del host (verifica el SSL, no lo pisa)
./bootstrap.sh

# Construye y levanta worker + web
docker compose up -d --build
```

---

## 2. Actualizar código (tras un nuevo commit en GitHub)

```bash
# Traer el último código. Si cambiaste de rama en el .env, ajústala en el checkout.
git -C repos/engine pull --ff-only
git -C repos/ui     pull --ff-only

# Reconstruir y levantar todo (conserva el volumen de datos)
docker compose up -d --build
```

Solo un servicio (más rápido si solo cambió uno):

```bash
# Solo el worker (cambió el engine)
git -C repos/engine pull --ff-only && docker compose up -d --build worker

# Solo la web (cambió la UI)
git -C repos/ui pull --ff-only && docker compose up -d --build web
```

Si actualizas el PROPIO deploy (este repo: compose, nginx, etc.):

```bash
git pull                 # trae los cambios del deploy
./bootstrap.sh           # re-renderiza el nginx del host si cambió el template
docker compose up -d --build
```

---

## 3. Ver estado y logs

```bash
docker compose ps                          # worker y web: ¿Up?
docker compose logs -f --tail=100          # logs de todo (Ctrl-C para salir)
docker compose logs -f --tail=100 web      # solo la web
docker compose logs -f --tail=100 worker   # solo el worker (scans, exports)
```

---

## 4. Tareas manuales del worker (forzar algo sin esperar al cron)

```bash
# Escanear señales AHORA (registra nuevas + alerta Discord)
docker compose exec worker /app/run-task.sh scan

# Resolver resultados AHORA (TP/SL/timeout de señales que maduraron)
docker compose exec worker /app/run-task.sh resolve

# Regenerar los JSON de la UI AHORA (backtest/señales/cartera)
docker compose exec worker /app/run-task.sh export
```

---

## 5. Comprobar que Discord funciona

```bash
docker compose exec worker sh -c '. /etc/environment && cd "$ENGINE_DIR/buy_the_dip" && python live_signals.py --test-alert'
```

Debe imprimir `sent ✅` y llegar un mensaje a tu canal.

---

## 6. Ver las señales acumuladas (paper trading)

```bash
# Últimas señales registradas
docker compose exec worker sh -c 'tail -n 20 /data/live_signals.jsonl'

# Resumen (win rate vivo vs backtest) — tras el primer resolve
docker compose exec worker sh -c 'cat /data/live_summary.json'
```

---

## 7. Parar / arrancar / reiniciar

```bash
docker compose restart          # reiniciar (no re-lee el .env)
docker compose down             # parar (SIN -v → CONSERVA el log de señales)
docker compose up -d            # arrancar de nuevo (sin rebuild)
```

> ⚠️ **Nunca** `docker compose down -v`: la `-v` borra el volumen con TODO el
> historial de señales acumuladas (paper trading). Sin `-v` los datos se conservan.

---

## Referencia rápida de `.env`

| Variable | Qué es |
|---|---|
| `COMPOSE_PROJECT_NAME` | aísla este stack (`predictor_production`); nombra el volumen |
| `WEB_PORT` | puerto loopback del host → nginx del host hace proxy aquí |
| `DOMAIN` / `APP_HOST` | dominio y subdominio (nginx + SSL del host) |
| `DISCORD_WEBHOOK_URL` | **secreto** para alertas. Vacío = registra pero no alerta |
| `ENGINE_BRANCH` / `UI_BRANCH` | rama que se despliega de cada repo |
