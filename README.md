# predictor-deploy — Worker de señales + UI web

Despliega el stack de **Buy-the-Dip** (paper trading, no ejecuta órdenes):

- **worker**: escanea la cesta cada hora (vela 1H), registra señales, alerta por
  **Discord** y genera los JSON (backtest/señales/cartera) para la UI.
- **web**: sirve la UI (Vite + Nginx) y esos JSON desde un **volumen compartido**
  con el worker, siempre frescos.

Misma metodología que `boolend-deploy`: Docker + Makefile + `COMPOSE_PROJECT_NAME`,
Nginx en el **host** (la web se publica solo en `127.0.0.1:<WEB_PORT>`), secretos en `.env`.

## Qué corre

| Tarea | Cuándo | Qué hace |
|---|---|---|
| `scan` | cada hora, min 2 | señales nuevas → `live_signals.jsonl` + alerta Discord |
| `resolve` | cada 6 h, min 20 | resultado real (TP/SL/timeout) → `live_results.jsonl` + `live_summary.json` |
| `export` | 1×/día, 03:30 | backtest/señales/cartera JSON → `buy_the_dip/` (para la UI) |

Datos en volumen Docker (`predictor_<env>_signaldata`), sobreviven a redeploys.

## Requisitos en el VPS

- Docker + Docker Compose v2 (ya lo tienes por BooLend).
- Git.
- Webhook de Discord.
- **Subdominio** (ej. `predictor.tudominio.com`) con registro DNS al VPS.
- **SSL del dominio ya instalado en el host** (infra compartida): el snippet
  `/etc/nginx/snippets/ssl-<dominio>.conf` + el Origin cert en
  `/etc/ssl/cloudflare/<dominio>/`. Si ya tienes otro proyecto en ese dominio
  (p.ej. BooLend), esto ya existe y se reutiliza. bootstrap solo lo verifica.
- Los **dos repos en GitHub**: engine (ya existe) y UI (crearlo, ver abajo).

## Antes de desplegar: subir la UI a GitHub (una sola vez)

La UI vive en `predictor-ui/` y aún no tiene remote. En tu Mac:

```bash
cd /Users/cristiancruzbenel/Proyectos/Predictor/predictor-ui
# Crea un repo VACÍO en GitHub (ej. crypto-predictor-ui) y copia su URL.
git add -A && git commit -m "UI buy-the-dip: futures reality + portfolio + deploy"
git remote add origin https://github.com/<tu-user>/crypto-predictor-ui.git
git push -u origin main
```

(El `.gitignore` ya excluye `node_modules/`, `dist/`, `.env` y los JSON de datos.)

## Despliegue (primera vez)

```bash
# 1. Carpeta del entorno
mkdir -p ~/deploys/predictor/production && cd ~/deploys/predictor/production

# 2. Traer este repo deploy aquí (clonar o copiar su contenido).

# 3. Configurar
cp .env.example .env && nano .env
#    - ENGINE_REPO / ENGINE_BRANCH  (rama feature hasta mergear el PR; luego 'main')
#    - UI_REPO / UI_BRANCH          (el repo que acabas de crear)
#    - COMPOSE_PROJECT_NAME=predictor_production
#    - WEB_PORT (loopback, ej. 3020)  ·  DOMAIN  ·  APP_HOST=predictor.${DOMAIN}
#    - DISCORD_WEBHOOK_URL=<tu webhook>

# 4. Clonar repos + renderizar el server block de Nginx del host
#    (el SSL del dominio es infra COMPARTIDA: debe existir ya en
#     /etc/nginx/snippets/ssl-<dominio>.conf — lo instala el primer proyecto del
#     dominio. bootstrap solo lo VERIFICA, no lo toca.)
./bootstrap.sh

# 5. Construir y levantar worker + web
docker compose up -d --build
```

Al arrancar, el worker hace un **scan inicial** + un **export inicial en background**
(para que la UI tenga datos ya). La web queda en `https://${APP_HOST}`.

## Verificar

```bash
docker compose ps                       # worker y web "Up"
docker compose logs -f --tail=100       # actividad (scan + export)
```

Abre `https://predictor.crelaris.com` → debe cargar con "Fuente activa: JSON real".

## Comandos de operación

**Todos los comandos (desplegar, actualizar, logs, tareas, parar) están en
[`COMMANDS.md`](COMMANDS.md)** — copia-pega el que necesites, sin scripts que
oculten lógica. Resumen de los más usados:

```bash
# actualizar código
git -C repos/engine pull --ff-only && git -C repos/ui pull --ff-only
docker compose up -d --build

# ver / operar
docker compose ps
docker compose logs -f --tail=100
docker compose down          # parar (SIN -v → conserva datos)
```

Cuando mergees cambios a `main`, basta con el `git ... pull` + `up -d --build` de arriba.

## Notas

- **Paper trading:** nunca ejecuta órdenes. Solo detecta, registra, avisa y visualiza.
- **Secretos:** `DISCORD_WEBHOOK_URL` solo en `.env` (gitignored). Vacío = sin alertas.
- **Datos UI:** worker y web comparten el volumen; la UI los lee en `/data/buy_the_dip/`.
  Antes del primer export, la UI cae a su fallback mock (normal).
- **Validación:** deja acumular señales **varias semanas** antes de concluir; 3-4 no dicen nada.
