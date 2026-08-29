# Reglas de disciplina del Superagente Quant

Este documento aplica los puntos 35, 37 y 38 de la lista de 40 ideas.
No es opcional: son las reglas que evitan que el sistema (o quien lo
opera) tome decisiones emocionales o fabrique senales que no existen.

## 1. Regla anti-fabricacion (punto 37)

El sistema, y cualquiera que reporte sus resultados, **nunca** presenta
una apuesta de valor, una alerta o un hallazgo que no este respaldado
por datos reales y verificables de The Odds API (o de la fuente de
datos que corresponda). Si una ronda no encuentra nada, se reporta
honestamente que no encontro nada. Esta regla ya se ha aplicado varias
veces en el proyecto (por ejemplo, la corrida del 29-ago-2026 que no
encontro valor real) y queda formalizada aqui como no negociable.

## 2. No ajustar el modelo en caliente (punto 35)

Prohibido cambiar umbrales (UMBRAL_EV_MINIMO, factor_k del Elo,
ventaja de localia, etc.) inmediatamente despues de ganar o perder una
apuesta individual. Los ajustes de parametros solo se hacen:

- Con base en metricas agregadas (ROI acumulado, Brier score,
  Closing Line Value promedio) sobre un numero de apuestas
  estadisticamente relevante (minimo ~30-50 apuestas).
- Documentando el cambio y el motivo en CHANGELOG.md antes de
  aplicarlo.

## 3. Circuit breaker (punto 38) -- criterios objetivos para pausar el sistema

El sistema (o el operador) debe pausar las apuestas y forzar una
revision manual si ocurre CUALQUIERA de estas condiciones:

- **Drawdown de banca >= 20%** desde el ultimo maximo registrado.
- **Racha de 10 apuestas consecutivas con EV positivo estimado que
  terminan en perdida neta acumulada**, sin que el ROI se acerque al
  EV esperado por el modelo (senal de que el modelo puede estar mal
  calibrado, no solo de mala suerte puntual).
- **El Brier score del modelo Elo (ver elo_model.py) empeora de forma
  sostenida** en el backtesting mensual comparado con el mes anterior.
- **Los creditos de The Odds API caen por debajo del colchon minimo**
  (ya implementado como COLCHON_MINIMO_CREDITOS en el bot de cobertura
  en vivo; el mismo criterio aplica al bot de valor pre-partido).

Cuando se activa el circuit breaker, el sistema debe:
1. Dejar de enviar nuevas alertas de "apostar" (puede seguir
   registrando datos e historial).
2. Notificar por Telegram que el sistema esta en pausa y por que.
3. Esperar revision manual antes de reanudar.

## 4. Revision periodica (punto 36)

Cada mes, revisar con metricas objetivas:
- ROI real del registro de apuestas (Excel) vs. ROI esperado segun el
  EV estimado de cada apuesta.
- Brier score y accuracy del modelo Elo (backtest_walk_forward).
- Cuantas alertas de valor/arbitraje se enviaron y cuantas eran
  genuinas vs. ruido.
- Creditos de API usados vs. presupuesto mensual.

## 5. Version control de la estrategia (punto 34)

Todo cambio de estrategia (nuevas ligas, nuevos mercados, cambios de
umbral, cambios al modelo Elo) se documenta en CHANGELOG.md con fecha
y motivo, para poder entender despues que funciono y que no.
