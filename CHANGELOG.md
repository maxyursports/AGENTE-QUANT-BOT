# Changelog del Superagente Quant

Registro de cambios de estrategia y sistema (ver DISCIPLINA.md, punto 34).
Formato: fecha, que cambio, por que.

## 2026-08-29

- **Se agrega elo_model.py**: motor de Elo propio con ajuste de
  localia, decaimiento temporal y backtesting walk-forward con Brier
  score. Motivo: puntos 8, 9, 11, 13, 14, 15 de la lista de 40 ideas.
  Estado: implementado y probado con datos sinteticos. PENDIENTE:
  necesita un historial real de resultados (resultados_historicos.csv)
  para entrenarse -- ver limitacion documentada en el propio archivo.

- **Se agrega valor_prepartido.py + valor_prepartido.yml**: segundo
  proceso automatico permanente (antes se hacia manualmente con
  scripts temporales) que busca valor pre-partido por comparacion
  contra el consenso de mercado (devig), detecta arbitraje entre
  casas, calcula el stake sugerido con Kelly fraccionado, y guarda
  historial de cuotas para poder medir Closing Line Value mas
  adelante. Motivo: puntos 4, 16, 17, 18, 24, 29 de la lista de 40
  ideas. Estado: implementado, probado con datos simulados. Programado
  para correr 3 veces al dia via GitHub Actions.

- **Se agrega DISCIPLINA.md**: reglas formales de circuit breaker,
  no-ajuste-en-caliente y anti-fabricacion. Motivo: puntos 35, 37, 38.
  Estado: documentado, pendiente de automatizar la deteccion de
  drawdown (requiere que el registro de banca este conectado
  digitalmente, no solo en el Excel manual).

- **Umbral inicial de valor pre-partido**: UMBRAL_EV_MINIMO = 2%.
  Conservador a proposito para la primera version del bot; se revisara
  con datos reales acumulados segun la regla de revision mensual
  (DISCIPLINA.md punto 4), nunca en caliente tras un resultado
  individual.

## Pendientes explicitos (no fabricar que ya estan resueltos)

- Fuente de datos de xG y estadisticas de forma (punto 10): no
  integrada todavia -- necesita elegir y conectar una fuente adicional
  (ej. API-Football).
- Datos de lesiones/alineaciones (puntos 6, 12): no automatizados,
  hoy no hay fuente conectada.
- Dashboard/panel de estado (punto 31): no construido todavia.
- Exchanges tipo Betfair (punto 40): no evaluado, requiere cuenta y
  API propia del exchange.
- Extension a otros deportes como tenis (punto 39): sport_key
  disponibles en The Odds API, pero no verificados ni agregados
  todavia a LIGAS_A_REVISAR.

## 2026-08-29 (mismo dia, correccion tras primera corrida real)

- **Primera corrida real de valor_prepartido.py (manual)**: encontro 23 "hallazgos" de valor (umbral EV>=2%) y 5 de arbitraje. Cantidad sospechosamente alta comparada con el analisis manual del mismo dia (que con un metodo mas estricto no encontro nada). Diagnostico: comparar la MEJOR cuota (maximo entre 5-8 casas) contra un PROMEDIO que incluye esa misma cuota tiene sesgo de seleccion -- el maximo de varias muestras con ruido casi siempre supera el promedio, aunque el mercado sea eficiente.
- **Correccion aplicada**: cuota_justa_por_devig() ahora usa la MEDIANA en vez del promedio (mas robusta a outliers), y UMBRAL_EV_MINIMO subio de 2% a 5%.
- **Segunda corrida real (tras la correccion)**: bajo de 23 a 15 hallazgos de valor. Los 5 de arbitraje se mantuvieron igual (logico, ese calculo no depende del umbral ni del devig). 15 sigue siendo una tasa alta y no confiable.
- **DECISION (circuit breaker, ver DISCIPLINA.md)**: se pausa el cron automatico de valor_prepartido.yml (dejando solo ejecucion manual) hasta validar el metodo con mas rigor. NO se debe reactivar el cron hasta:
  1. Correr un backtest o periodo de prueba en modo "solo registro" (sin enviar a Telegram) para medir cuantos de estos hallazgos realmente se sostienen en el cierre de linea (Closing Line Value, punto 17).
  2. Considerar excluir la propia cuota outlier del calculo de la mediana de referencia (leave-one-out), que es la forma tecnicamente correcta de evitar el sesgo de seleccion por completo.
  3. Idealmente, cruzar contra el modelo Elo propio (elo_model.py) una vez tenga historial de resultados reales, en vez de depender solo de comparar casas entre si.
- **Leccion aplicada del proyecto**: se prefirio pausar el sistema y reportar el problema honestamente en vez de dejarlo mandando alertas no validadas -- consistente con la regla anti-fabricacion (DISCIPLINA.md punto 1).
