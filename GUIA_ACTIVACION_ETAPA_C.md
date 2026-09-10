# Guía de activación — Etapa C (conectar Supabase real al bot en producción)

Este documento no ejecuta nada. Es la hoja de ruta para el día en que
decidas autorizar, punto por punto, que el bot real empiece a escribir en
un proyecto Supabase real. Ninguno de estos pasos se ha hecho todavía.

## Requisito previo, no negociable

Antes de este paso: re-validar la suite de pgTAP contra **PostgreSQL 17**
real (no 16), como se explica en `HALLAZGO_postgresql_16_vs_17.md`. Todo lo
demás en esta guía asume que esa validación ya se hizo y salió bien.

## Paso 1 — Decidir qué escribe el bot, y cuándo (decisión tuya, no técnica)

`supabase_adapter.py` (Etapa A, ya construido y probado) sabe registrar una
llamada a la API en `raw.api_requests` / `raw.payloads`. Antes de conectarlo
al bot real hace falta que decidas:

- ¿Se registra **cada** llamada a The Odds API (gasta ciclos de escritura
  por cada corrida de 15 minutos), o sólo un muestreo?
- ¿Qué pasa si Supabase está caído o lento en el momento en que el bot
  necesita mandar la alerta de Telegram? La alerta a Telegram **no puede
  depender de que Supabase responda** — el registro debe ser "best effort"
  y nunca bloquear ni retrasar una alerta real.

## Paso 2 — Crear el proyecto Supabase real (o confirmar el que ya existe)

Ya confirmaste que existe un proyecto real, "saq-staging". Antes de
conectar nada:

1. Confirmar que las 15 migraciones reales de `supabase/migrations/`
   (más el parche de fixtures y, si se autoriza, el borrador de Etapa B)
   están aplicadas ahí — con `supabase db push` apuntando a ese proyecto,
   nunca escribiendo SQL a mano contra la base real.
2. Confirmar que `cfg.projects` tiene la fila `agente-quant-bot` y que
   `cfg.data_sources` tiene la fila `the_odds_api` — el adaptador de
   Etapa A los requiere y nunca los crea por sí mismo (a propósito, para
   no fabricar identidad de proyecto/fuente silenciosamente).

## Paso 3 — Secrets nuevos (nombres, nunca valores, en este documento)

En el mismo lugar donde ya existen `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`
y `ODDS_API_KEY`:

- `SUPABASE_DB_URL` (o las tres piezas por separado: host, password,
  service role key — según cómo se prefiera conectar `psycopg2` desde el
  workflow).

Nadie en esta auditoría ha visto ni va a pedir ver el valor real de estas
llaves.

## Paso 4 — El único cambio real en código: dónde, no cómo

El único lugar que se tocaría en `telegram_alert_bot.py` es el punto donde
ya se recibe la respuesta de The Odds API — ahí, después de procesar la
respuesta para la alerta de Telegram (nunca antes, nunca bloqueando esa
ruta), se añadiría una llamada a `registrar_llamada_api(...)` envuelta en
su propio `try/except` que sólo registra el error sin detener el bot.

Este cambio no se ha hecho. Se haría en un PR aparte, pequeño, revisable
línea por línea, y sólo con tu autorización explícita para ese PR
específico — igual que PR #1 y PR #2 de Fase 1.

## Paso 5 — Probar en modo sombra antes de confiar en ello

Antes de asumir que el registro funciona en producción: dejar correr el
bot real con el cambio del Paso 4 durante un número de corridas que definas
tú (por ejemplo, un día completo = ~96 corridas de 15 minutos), y comparar
manualmente cuántas llamadas reales a Telegram hubo contra cuántas filas
nuevas aparecieron en `raw.api_requests` — deberían coincidir uno a uno.

## Paso 6 — Reversión

Si algo sale mal: el cambio del Paso 4 es aditivo y aislado (una llamada
envuelta en `try/except` que nunca puede detener el flujo de Telegram), así
que revertirlo es quitar esas líneas y volver a desplegar — el bot vuelve
exactamente al comportamiento actual, sin ningún dato perdido en Telegram.

## Lo que esta guía no resuelve por ti

No decide si vale la pena hacer esto ahora, ni qué política de consenso
multi-casa (la fila DRAFT `MC-POWER-LOGPOOL-V1.0` ya sembrada, que no
coincide con el método real de una sola casa) debería reemplazarse por una
que sí describa el método real — eso también sigue pendiente de tu
decisión.
