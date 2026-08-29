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
