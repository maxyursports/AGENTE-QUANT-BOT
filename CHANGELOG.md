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

## 2026-08-29 (mismo dia, rediseno para 1xBet como unica casa)

- **Contexto**: el usuario confirmo que solo tiene cuenta en UNA casa de apuestas (1xBet). Todo el diseno anterior (mejor cuota entre varias casas, arbitraje entre casas) es inejecutable en la practica -- no se puede apostar en una casa que no se tiene cuenta, y el arbitraje entre casas requiere cuentas simultaneas en todas ellas.
- **Cambios en valor_prepartido.py**:
  1. Se elimino por completo la deteccion de arbitraje (detectar_arbitraje, UMBRAL_ARBITRAJE, formatear_hallazgo_arbitraje) -- ya no aplica con una sola casa.
  2. Se elimino mejor_cuota_por_resultado() (ya no se compara "la mejor cuota entre casas": la cuota ejecutable siempre es la de 1xBet).
  3. Nueva funcion cuotas_1xbet(): extrae exclusivamente las cuotas de 1xBet por partido. Si 1xBet no cubre un partido, se salta (contador partidos_sin_1xbet).
  4. Nueva funcion cuota_justa_leave_one_out(): calcula la probabilidad justa con la MEDIANA de todas las casas EXCEPTO 1xBet (leave-one-out real), corrigiendo el sesgo de seleccion documentado en la entrada anterior de este changelog (que antes solo se habia mitigado parcialmente con mediana simple). Se exige un minimo de MINIMO_CASAS_REFERENCIA = 3 casas de referencia; si no se cumple, se salta el partido (contador partidos_sin_referencia_suficiente).
  5. ejecutar_ronda() reescrito: EV se calcula como prob_justa * cuota_1xbet - 1, usando siempre el precio real y ejecutable de 1xBet.
  6. Parametro regions de la API reducido de "eu,uk,us" a "eu" (1xBet cotiza en la region eu de The Odds API) -- reduce el consumo de creditos por request al pedir menos casas innecesarias.
- **Cambios en telegram_alert_bot.py (bot de cobertura en vivo)**: promedio_cuotas_h2h() (promediaba entre todas las casas) reemplazada por cuotas_h2h_de_una_casa(), que toma exclusivamente las cuotas de 1xBet. Si 1xBet no cubre el partido, se salta (return None). Los mensajes de alerta ahora dicen explicitamente "en 1xBet" en vez de referirse a un promedio de mercado. Ya usaba regions="eu" (no requirio cambio adicional).
- **Motivo de leave-one-out en vez de solo mediana**: quedaba pendiente desde la entrada anterior (punto 2 de la decision de pausar el cron). Es la forma tecnicamente correcta de estimar la probabilidad justa sin sesgo, porque nunca compara la cuota de 1xBet contra una mediana que la incluya a ella misma.
- **Estado del cron**: valor_prepartido.yml se mantiene en workflow_dispatch (solo manual) -- el circuit breaker de la entrada anterior sigue vigente. Aun con leave-one-out corregido, falta: (a) correr el workflow manualmente contra la API real para ver si la tasa de hallazgos baja a un nivel creible, (b) medir Closing Line Value en el tiempo, (c) cruzar contra elo_model.py cuando haya historial real. No se reactiva el cron automatico hasta cumplir eso (ver DISCIPLINA.md).
- **No fabricado**: esta entrada documenta cambios de codigo verificados por sintaxis (ast.parse) y por 3 casos de prueba sinteticos (valor encontrado, partido sin 1xBet, casas de referencia insuficientes). NO se ha vuelto a correr el workflow contra datos reales todavia con esta version -- pendiente antes de confiar en sus resultados para dinero real.

## 2026-08-29 (mismo dia, ajuste post-corrida real: MINIMO_CASAS_REFERENCIA)

- **Contexto**: con autorizacion explicita del usuario ("SI ES PARA MI BENEFICIO SI"), se corrio manualmente el workflow valor_prepartido.yml contra la API real por primera vez con el diseno de 1xBet como unica casa (leave-one-out). Resultado de la corrida #3: 6 "hallazgos" de valor, los 6 en el mismo mercado (Empate) y la misma liga (soccer_usa_mls).
- **Hipotesis inicial (descartada despues)**: se penso que era ruido por poca muestra, ya que MINIMO_CASAS_REFERENCIA estaba en 3 -- con solo 3 casas de referencia la mediana tiene mucha varianza, especialmente en un mercado menos liquido como el empate.
- **Cambio aplicado**: se subio MINIMO_CASAS_REFERENCIA de 3 a 5 en valor_prepartido.py, y se agrego logging detallado por cada hallazgo (linea `[DETALLE]` con partido, liga, cuota, probabilidad justa, numero de casas de referencia y EV) para poder auditar cada senal sin depender solo del mensaje final de Telegram.
- **Resultado de la corrida #4 (con MINIMO_CASAS_REFERENCIA=5)**: el patron NO desaparecio. Se encontraron nuevamente 4 hallazgos, todos Empate/MLS, esta vez con num_casas_ref=22 -- una muestra grande y estadisticamente robusta. Esto **descarta la hipotesis de "poca muestra"**: el patron persiste incluso con 22 casas de referencia.
- **Interpretacion honesta (sin fabricar conclusiones)**: el patron Empate/MLS repetido con muestra grande puede deberse a (a) una ineficiencia real y estructural en como 1xBet cotiza el empate en la MLS, (b) un artefacto de los datos de la API para esa liga especifica, o (c) un patron real pero dificil de aprovechar en la practica (ej. si 1xBet ajusta la cuota rapido al recibir apuestas). Este patron **no ha sido explicado ni validado independientemente** -- se le advirtio al usuario explicitamente que no confie en estos hallazgos sin verificar la cuota real en la app de 1xBet antes de apostar. Queda como un hallazgo abierto para investigar mas adelante (posiblemente cruzando con Closing Line Value o revisando si soccer_usa_mls tiene menos casas cotizando en general).
- **No fabricado**: los numeros (6 hallazgos con num_casas_ref bajo, luego 4 hallazgos con num_casas_ref=22) provienen de corridas reales del workflow contra la API real, no de simulacion.

## 2026-08-30 (filtro hibrido: probabilidad domina sobre EV)

- **Contexto**: tras revisar los hallazgos de la entrada anterior, el usuario cuestiono directamente por que el bot le enviaba apuestas de Empate (probabilidad tipicamente baja, ~20-25%) solo porque tenian EV positivo. Se le explico la diferencia entre EV (valor matematico esperado a largo plazo, comparando la cuota de 1xBet contra el consenso de mercado) y probabilidad de ganar una apuesta individual: un resultado con baja probabilidad puede tener EV positivo y aun asi ser, la mayoria de las veces, la opcion que NO ocurre.
- **Decision explicita del usuario**: "quiero que domine la mayor probabilidad de que pase, no importa que sean cuotas bajas, uno veinte, uno treinta y cinco, no importa... necesito es que tenga mayor probabilidad de ser ganadas, no importa que las cuotas sean bajas." Se pidio un filtro hibrido donde la probabilidad de ganar sea el criterio DOMINANTE y el EV pase a ser secundario.
- **Cambios en valor_prepartido.py**:
  1. Nueva constante `UMBRAL_PROBABILIDAD_MINIMA = 0.65` -- filtro PRINCIPAL. Si la probabilidad justa (consenso de mercado, leave-one-out, sin incluir 1xBet) de un resultado no llega a este minimo, se descarta sin mirar el EV, sin importar que tan buena sea la cuota.
  2. `UMBRAL_EV_MINIMO` se baja de 0.05 a **0.0** -- ya no es el filtro principal, solo un chequeo de sanidad: que 1xBet no pague peor que el resto del mercado.
  3. `ejecutar_ronda()`: el filtro de probabilidad se evalua ANTES que el de EV (si `prob < UMBRAL_PROBABILIDAD_MINIMA`, se descarta inmediatamente).
  4. Los hallazgos ahora se ordenan por probabilidad descendente (`hallazgos_valor.sort(key=lambda h: h[4], reverse=True)`), no por EV.
  5. `formatear_hallazgo_valor()` reescrito: el mensaje de Telegram ahora se titula "Alta probabilidad en 1xBet" (antes "Valor detectado"), destaca primero la probabilidad estimada, y agrega una advertencia explicita: aunque la probabilidad sea alta, no es garantia -- se calcula y muestra cuantas de cada 100 veces esa apuesta se pierde en promedio (redondeado desde 1 - probabilidad).
- **Efecto esperado**: las alertas ahora deberian ser mayoritariamente favoritos claros (locales o visitantes fuertes) a cuotas bajas (ej. 1.20-1.50), en vez de empates de cuota alta como en las corridas #3 y #4. Esto es consistente con lo que el usuario pidio explicitamente.
- **Pendiente**: correr el workflow manualmente contra la API real con este filtro nuevo para confirmar que efectivamente deja de mandar empates de baja probabilidad y reportar los resultados reales al usuario (con honestidad total, incluyendo si no se encuentra ningun hallazgo).
- **No fabricado**: este cambio de diseno responde directamente a una instruccion explicita del usuario, no a una decision unilateral del asistente. El codigo fue verificado por sintaxis (ast.parse) antes de publicarse.
