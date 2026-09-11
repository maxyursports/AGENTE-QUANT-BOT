# AGENTE-QUANT-BOT — estado real del sistema (borrador de corrección)

**Este archivo es un borrador que NO ha sido aplicado al repositorio real.**
Reemplaza en contenido a `README_SETUP.md`, que describe una versión antigua
del proyecto (menciona `hedge_calculator.py`, que ya no existe, y un
proveedor de cuotas gratuito que ya no se usa). Todo lo escrito aquí fue
verificado directamente contra el código y los workflows reales en
`origin/main` el 2026-09-09.

## Qué corre hoy, de verdad, y con qué frecuencia

Hay dos procesos automáticos independientes, ambos en GitHub Actions, ambos
usando las mismas tres llaves (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`,
`ODDS_API_KEY`) guardadas como *Secrets* del repositorio:

- **`monitor_partidos.yml` → `telegram_alert_bot.py`** — corre **cada 15
  minutos, automáticamente**, sin que nadie lo dispare. Es el bot en vivo.
- **`valor_prepartido.yml` → `valor_prepartido.py`** — **pausado en
  automático desde el 2026-08-29** (circuit breaker, ver `DISCIPLINA.md` y
  `CHANGELOG.md`). Hoy sólo corre si alguien lo dispara manualmente desde la
  pestaña Actions (`workflow_dispatch`). Los motivos reales de la pausa:
  las dos primeras corridas reales encontraron 23 y luego 15 "hallazgos" de
  valor — una tasa demasiado alta para ser creíble como ventaja real — y la
  regla de disciplina del proyecto exige no confiar en un método así hasta
  validarlo con más rigor (backtest / Closing Line Value, o cruzarlo con el
  modelo Elo propio).

## La fuente de datos ya no es gratuita

El proveedor real es **The Odds API**, plan de pago "20K" — **USD $30/mes,
20,000 créditos/mes**, activo desde agosto de 2026 (no el plan gratuito de
100 consultas/hora descrito en la versión anterior de este documento). El
propio bot se detiene solo si en algún momento del mes quedan pocos créditos
disponibles.

## El alcance real hoy

- **Una sola casa de apuestas ejecutable: 1xBet.** No hay comparación entre
  casas ni arbitraje — se eliminó deliberadamente cuando se confirmó que el
  usuario sólo tiene cuenta en esa casa.
- **Fútbol** con múltiples mercados (`h2h`, `totals`, `spreads`, `btts`,
  `draw_no_bet`, `double_chance`), más **baloncesto, hockey sobre hielo,
  béisbol, eSports y tenis** (tenis y eSports se descubren de forma
  dinámica vía `/v4/sports`, no con claves fijas).
- La probabilidad que calcula el bot es la probabilidad **implícita** en las
  cuotas de 1xBet (devig), no una probabilidad basada en datos reales del
  deporte (lesiones, alineaciones, forma). Esa es una limitación reconocida
  del proyecto, no un defecto oculto.

## Archivos reales del sistema (más allá de lo ya conocido)

- **`elo_model.py`** — motor de Elo propio (ajuste de localía, decaimiento
  temporal, backtesting walk-forward con Brier score). Implementado y
  probado con datos sintéticos; pendiente de un historial real de
  resultados (`resultados_historicos.csv`, que todavía no existe) para
  entrenarse de verdad.
- **`DISCIPLINA.md`** — reglas formales de circuit breaker, no-ajuste-en-
  caliente y anti-fabricación. Es el documento que obliga, por ejemplo, a
  no reactivar `valor_prepartido.yml` sin antes documentar la corrección en
  `CHANGELOG.md`.
- **`CHANGELOG.md`** — registro real de cada cambio de estrategia, con
  fecha y motivo. Es la fuente más confiable para saber "qué es cierto hoy"
  del sistema — más que cualquier README, incluido este.

## Lo que sigue pendiente (tomado directamente de CHANGELOG.md, no inventado)

- Fuente de datos de xG y estadísticas de forma: no integrada.
- Datos de lesiones/alineaciones: no automatizados.
- Panel/dashboard de estado del propio bot: no construido (más allá de la
  bitácora de auditoría de Fase 1/2, que es un proyecto aparte).
- Exchanges tipo Betfair: no evaluado.
- Capa de infraestructura Supabase (Fase 1/2 de este mismo esfuerzo de
  auditoría): validada de forma aislada, no conectada todavía al bot real.

## Configurar las llaves (esto sí sigue igual)

En **Settings → Secrets and variables → Actions → New repository secret**,
tres secrets: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `ODDS_API_KEY`. Sin
esto, ninguno de los dos workflows puede correr.

