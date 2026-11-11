# Comandos del deploy — predictor (worker + web)

Copia-pega el comando que necesites. Todo es transparente, sin scripts que oculten
lógica. Corre siempre **desde la carpeta del entorno**: `cd ~/deploys/predictor`

**Modelo:** la **web** corre 24/7 en Docker. El **worker** es EFÍMERO: no corre
permanente; se lanza, hace una tarea (scan/resolve/export) y se apaga. El **horario
lo pone el cron del VPS** (sección 4), no un cron dentro del contenedor.

---

## 1. Primer despliegue (una vez)

```bash
# Config del entorno (crea el .env con tus valores y el secreto de Discord)
cp .env.example .env
nano .env

# Clona engine + ui y configura el nginx del host (verifica el SSL, no lo pisa)
./bootstrap.sh

# Levanta la WEB (24/7)
docker compose up -d --build web

# Genera los JSON para la UI por primera vez (sino la UI arranca en modo mock)
docker compose run --rm worker export

# Comprueba que Discord funciona
docker compose run --rm worker scan
```

Luego programa el cron del VPS (sección 4).

---

## 2. Actualizar código (tras un commit en GitHub)

```bash
# Traer el último código
git -C repos/engine pull --ff-only
git -C repos/ui     pull --ff-only

# Reconstruir la web (el worker se reconstruye solo la próxima vez que se invoque,
# pero fuerza el rebuild si cambió el worker):
docker compose up -d --build web
docker compose build worker
```

Si actualizas el PROPIO deploy (este repo):

```bash
git pull
./bootstrap.sh                 # re-renderiza el nginx si cambió el template
docker compose up -d --build web
```

---

## 3. Tareas del worker manualmente (forzar algo ahora)

```bash
# Escanear señales AHORA (registra nuevas + alerta Discord)
docker compose run --rm worker scan

# Resolver resultados AHORA (TP/SL/timeout de señales que maduraron)
docker compose run --rm worker resolve

# Regenerar los JSON de la UI AHORA (backtest/señales/cartera)
docker compose run --rm worker export
```

`--rm` = el contenedor se borra al terminar (no deja basura). Cada tarea imprime su
salida directamente en tu terminal.

**Multi-estrategia:** el worker es genérico. Por defecto corre `buy_the_dip`; para
otra estrategia del engine pásala con `-e STRATEGY=<nombre>`. Cada una guarda sus
datos en `/data/<nombre>/` sin colisionar.

```bash
docker compose run --rm -e STRATEGY=mean_reversion worker scan
```

---

## 4. Programar el horario (cron del VPS) — la clave

Abre el crontab del VPS:

```bash
crontab -e
```

Y pega estas 3 líneas (ajusta la ruta si tu carpeta es otra). **Son transparentes:
cada línea dice exactamente qué contenedor se lanza y cuándo.**

```cron
# --- predictor: señales Buy-the-Dip (paper trading) ---
# scan: cada hora al minuto 2 (tras cerrar la vela 1H)
2 * * * * cd ~/deploys/predictor && docker compose run --rm worker scan >> ~/deploys/predictor/cron.log 2>&1

# resolve: cada 6 horas al minuto 20
20 */6 * * * cd ~/deploys/predictor && docker compose run --rm worker resolve >> ~/deploys/predictor/cron.log 2>&1

# export (JSON de la UI): 1 vez al día a las 03:30
30 3 * * * cd ~/deploys/predictor && docker compose run --rm worker export >> ~/deploys/predictor/cron.log 2>&1
```

- `>> cron.log 2>&1` guarda la salida en un archivo para que puedas revisarla.
- Para ver ese log: `tail -f ~/deploys/predictor/cron.log`
- Para quitar las tareas: `crontab -e` y borra las líneas.

---

## 5. Ver estado y logs

```bash
docker compose ps                          # ¿la web está Up?
docker compose logs -f --tail=100 web      # logs de la web
tail -f ~/deploys/predictor/cron.log       # salida de las tareas del worker (cron)
```

---

## 6. Comprobar Discord

```bash
docker compose run --rm worker scan
# o un mensaje de prueba directo:
docker compose run --rm --entrypoint sh worker -c \
  'cd "$ENGINE_DIR/buy_the_dip" && python live_signals.py --test-alert'
```

---

## 7. Ver señales acumuladas (paper trading)

```bash
# Últimas señales registradas (desde la web, que monta el volumen)
docker compose exec web sh -c 'tail -n 20 /usr/share/nginx/html/data/live_signals.jsonl'

# Resumen vivo vs backtest (tras el primer resolve)
docker compose exec web sh -c 'cat /usr/share/nginx/html/data/live_summary.json'
```

---

## 8. Parar / arrancar la web

```bash
docker compose restart web      # reiniciar la web
docker compose down             # parar la web (SIN -v → CONSERVA los datos)
docker compose up -d web        # arrancar la web de nuevo
```

> ⚠️ **Nunca** `docker compose down -v`: la `-v` borra el volumen con TODO el
> historial de señales. Sin `-v`, los datos se conservan.

---

## Referencia rápida de `.env`

| Variable | Qué es |
|---|---|
| `COMPOSE_PROJECT_NAME` | aísla este stack (`predictor_production`); nombra el volumen |
| `WEB_PORT` | puerto loopback del host → nginx del host hace proxy aquí |
| `DOMAIN` / `APP_HOST` | dominio y subdominio (nginx + SSL del host) |
| `DISCORD_WEBHOOK_URL` | **secreto** para alertas. Vacío = registra pero no alerta |
| `ENGINE_BRANCH` / `UI_BRANCH` | rama que se despliega de cada repo |
