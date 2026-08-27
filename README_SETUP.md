# Bot de Alertas en Vivo — Guía de instalación (cero costo)

Este bot corre solo, sin que tú ni yo estemos pendientes, y te manda una
alerta a Telegram apenas detecta que un favorito va perdiendo o
empatando en un partido de las ligas permitidas — con el cálculo de
cobertura ya hecho, listo para decidir.

No necesitas saber programar para instalarlo: son 5 pasos, todos con
cuentas gratuitas.

## Paso 1 — Crear tu bot de Telegram (2 minutos)

1. Abre Telegram y busca el usuario **@BotFather**.
2. Envíale `/newbot`.
3. Ponle un nombre (el que quieras) y un usuario terminado en `bot`
   (ej. `maxyursports_alertas_bot`).
4. Te va a dar un **token** — algo como
   `123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ`. Guárdalo, es la llave B del
   paso 4.

## Paso 2 — Obtener tu Chat ID

1. Búscate a ti mismo en Telegram y envíale cualquier mensaje a tu
   bot recién creado (ej. "hola").
2. Abre en el navegador:
   `https://api.telegram.org/bot<TU_TOKEN>/getUpdates`
   (reemplaza `<TU_TOKEN>` por el token del paso 1).
3. Busca en la respuesta el número que aparece en `"chat":{"id": ...}`.
   Ese número es tu Chat ID.

## Paso 3 — Crear tu cuenta gratuita de datos de cuotas

1. Regístrate en el proveedor de cuotas que elijamos (por ejemplo
   odds-api.io, plan gratuito: 100 consultas/hora, cuotas en vivo).
2. Te dan una **API key** — guárdala, es la llave C.

## Paso 4 — Crear tu repositorio en GitHub (gratis)

1. Crea una cuenta en github.com si no tienes.
2. Crea un repositorio nuevo (público, para que las 100,000+ minutos de
   Actions sean gratis e ilimitados — el código es visible, pero tus
   alertas y tus llaves NO).
3. Sube estos archivos tal cual están: `hedge_calculator.py`,
   `telegram_alert_bot.py`, `requirements.txt`, y la carpeta
   `.github/workflows/monitor_partidos.yml`.

## Paso 5 — Configurar tus llaves como "Secrets" (nunca en el código)

1. En tu repositorio: **Settings → Secrets and variables → Actions →
   New repository secret**.
2. Crea tres secrets:
   - `TELEGRAM_BOT_TOKEN` → la llave del Paso 1
   - `TELEGRAM_CHAT_ID` → el número del Paso 2
   - `ODDS_API_KEY` → la llave del Paso 3
3. Ve a la pestaña **Actions** de tu repositorio y actívalas si te lo
   pide.
4. Listo — el bot va a correr solo cada 15 minutos, gratis, para siempre.

## Lo que falta antes de que funcione de verdad

El archivo `telegram_alert_bot.py` trae la conexión a Telegram y la
calculadora de cobertura ya completas y probadas. La función
`obtener_partidos_en_vivo()` está dejada como ejemplo — necesitamos
completarla juntos una vez confirmes qué proveedor de datos usamos,
porque cada uno tiene su propio formato de respuesta. Ese es
exactamente el siguiente paso cuando retomemos esto.

## Lo que este bot NO hace (y por qué)

- No decide si una cuota "tiene valor real" — solo detecta el cambio y
  calcula la cobertura. El análisis de probabilidad real (para saber si
  de verdad hay +EV o el mercado solo se ajustó justo) sigue siendo
  parte de la conversación conmigo.
- No cubre "todas las ligas del mundo" — se queda en el mismo alcance
  disciplinado que ya definimos. Con el plan gratuito de datos
  (100 consultas/hora) no alcanza para monitorear miles de partidos
  simultáneos del planeta entero, así que el límite técnico refuerza la
  misma decisión que ya habías tomado ("pocas pero muy investigadas").
- No apuesta por ti. Solo avisa y calcula — la decisión y el clic
  siempre son tuyos.
