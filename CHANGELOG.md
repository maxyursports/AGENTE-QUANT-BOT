# Changelog del Superagente Quant

Registro de cambios de estrategia y sistema (ver DISCIPLINA.md, punto 34).
Formato: fecha, que cambio, por que.

## 2026-08-30 (mismo dia, ampliacion de mercados y deportes)

- **Se amplia valor_prepartido.py de un solo mercado (h2h) y un solo
  deporte (futbol) a multiples mercados y multiples deportes**. Pedido
  explicito del usuario: "Si, quiero que agregues todos los mercados
  que te envie del futbol y que agregues los otros deportes que te
  dije. Recuerda que tu trabajo es buscarme las mejores apuestas que
  puedo hacer."

  Cambios concretos:
  1. Futbol ya no se evalua solo en el mercado h2h (1x2). Ahora se
     piden tambien: totals (total de goles over/under), spreads
     (handicap asiatico/europeo), btts (ambos anotan), draw_no_bet
     (sin empate) y double_chance (doble oportunidad). Son los
     mercados que The Odds API efectivamente soporta para futbol --
     ver LIMITACION HONESTA abajo para lo que NO cubre.
  2. Se agregan otros deportes pedidos explicitamente por el usuario:
     baloncesto (NBA, NCAAB, Euroleague), hockey sobre hielo (NHL),
     beisbol (MLB) y eSports (League of Legends, CS:GO, Dota 2,
     Valorant), cada uno con los mercados que The Odds API soporta
     para ese deporte (h2h siempre; spreads/totals donde aplica).
  3. Tenis se agrega de forma DINAMICA: en vez de hardcodear torneos
     (que cambian constantemente -- Wimbledon, US Open, Roland
     Garros, etc. solo existen como sport_key mientras el torneo esta
     activo), el bot consulta el endpoint /v4/sports de The Odds API
     (esta consulta NO consume creditos segun la documentacion
     oficial) y toma los torneos ATP/WTA activos en ese momento,
     hasta un maximo de MAX_TORNEOS_TENIS=8 para no disparar el
     consumo de creditos.
  4. Cada resultado ahora se etiqueta con el nombre del mercado (ej.
     "Total de goles/puntos (2.5)", "Handicap (-1.5)") para que el
     usuario sepa exactamente que tipo de apuesta es, no solo el
     resultado 1x2.
  5. El calculo de probabilidad implicita (devig) se hace POR
     SEPARADO dentro de cada (mercado, linea) -- nunca se mezclan las
     probabilidades de mercados distintos en el mismo calculo de
     overround, para no distorsionar el margen propio de 1xBet.
  6. UMBRAL_CREDITOS_SEGURIDAD sube de 15 a 50: al pedir varios
     mercados por llamada el costo en creditos por llamada sube (The
     Odds API cobra aproximadamente 1 credito por mercado solicitado,
     por region, no por partido). Antes cada llamada de futbol
     costaba ~1 credito; ahora puede costar hasta 6 (un credito por
     cada uno de los 6 mercados pedidos). Se sube el freno de
     seguridad de creditos para compensar y nunca quedarse sin
     creditos a mitad de mes.

  LIMITACION HONESTA QUE SIGUE VIGENTE: The Odds API no cubre toda la
  granularidad que el usuario pidio originalmente (corners por
  minuto, tarjetas, marcador exacto, mercados de jugador, mercados en
  vivo detallados). Esta es una limitacion de la fuente de datos
  actual, no del diseno del bot -- cubrir esos mercados requeriria
  evaluar una fuente de datos adicional (ver investigacion de
  API-Football / Sportmonks, aun no contratada). Ademas, la
  probabilidad que calcula el bot sigue siendo la probabilidad
  IMPLICITA en las cuotas de 1xBet, no una probabilidad calculada con
  datos reales del deporte (lesionados, alineaciones, forma, etc.).

  Estado: implementado, verificado con ast.parse, pendiente de
  correr contra la API real para medir el consumo real de creditos
  con el nuevo volumen de mercados/deportes.

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

## 2026-08-30 (mismo dia, ampliacion de ligas + decision sobre datos reales de futbol)

- **Contexto**: tras la corrida real #5 (0 hallazgos con el filtro probabilidad-dominante), el usuario cuestiono el metodo de fondo: no le interesa comparar la cuota de 1xBet contra otras casas (leave-one-out), porque 1xBet ya maneja buenas cuotas por si solo. Lo que pide es probabilidad de ganar basada en futbol real -- lesionados, alineaciones, formaciones, remates al arco, forma de jugadores.
- **Explicacion honesta dada al usuario**: hoy el sistema NO tiene ninguna fuente de datos de futbol real conectada (lesionados, alineaciones, estadisticas de jugador). La unica "probabilidad" que calcula el bot viene de comparar cuotas entre casas de apuestas (consenso de mercado), no de analizar el partido en si. El motor Elo (elo_model.py) existe en el codigo pero nunca se conecto a un historial de resultados reales.
- **Decision del usuario (dos partes)**:
  1. Investigar y cotizar una fuente de datos deportivos paga (lesionados, alineaciones, estadisticas de jugador) antes de contratar nada -- pendiente de reportar opciones concretas al usuario para su aprobacion.
  2. Mientras tanto, ampliar la cobertura de ligas/partidos revisados (en vez de bajar el umbral de 65% de probabilidad) para tener mas oportunidades de encontrar un favorito claro dentro de la ventana de 6 horas.
- **Cambio aplicado (parte 2, ya en produccion)**: se agregaron 10 ligas nuevas a LIGAS_A_REVISAR en valor_prepartido.py: soccer_spl (Escocia), soccer_norway_eliteserien, soccer_sweden_allsvenskan, soccer_japan_j_league, soccer_korea_kleague1, soccer_england_league1, soccer_england_league2, soccer_france_ligue_two, soccer_italy_serie_b, soccer_brazil_serie_b. Total: 35 ligas revisadas (antes 25). El umbral UMBRAL_PROBABILIDAD_MINIMA se mantiene en 0.65, sin cambios.
- **Investigacion de proveedores de datos (para decidir en una proxima conversacion)**: se investigaron dos opciones con datos de lesionados, alineaciones y estadisticas de jugador incluidos en todos sus planes:
  - **API-Football (api-sports.io)**: Free $0 (100 req/dia), Pro $19/mes (7,500 req/dia), Ultra $29/mes (75,000 req/dia), Mega $39/mes (150,000 req/dia). Todos los planes incluyen lesionados, alineaciones y estadisticas de jugador, y "todas las competiciones y endpoints".
  - **Sportmonks**: Starter EUR 29/mes (5 ligas, 2,000 llamadas/hora), Growth EUR 99/mes (30 ligas), Pro EUR 249/mes (120 ligas), Enterprise a medida (2,300+ ligas). Tambien incluye lesionados/suspensiones, alineaciones (incluso "alineaciones esperadas" antes de la confirmacion oficial) y estadisticas de jugador en todos los planes, pero el precio sube segun cuantas ligas se necesiten.
  - **Comparacion honesta**: API-Football es notablemente mas barato para cobertura amplia de ligas (todas las competiciones incluidas desde el plan Pro de $19/mes), mientras que en Sportmonks el precio escala fuerte segun el numero de ligas cubiertas. Para el caso de este proyecto (35+ ligas de futbol en varios continentes), API-Football parece la opcion mas costo-efectiva a primera vista, pero esto no se ha contratado ni decidido todavia -- pendiente de que el usuario apruebe el gasto adicional.
- **No fabricado**: los precios y features fueron obtenidos de las paginas oficiales de pricing de cada proveedor (api-football.com/pricing y sportmonks.com/football-api/plans-pricing) el mismo dia. No se ha contratado ningun servicio nuevo todavia -- ninguna tarjeta ni pago fue autorizado ni ejecutado.

## 2026-08-30 (mismo dia, cambio de metodo: se elimina la comparacion con otras casas, umbral baja a 55%, respuesta directa)

- **Contexto**: tras la entrada anterior (ampliacion de ligas, 0 hallazgos con el metodo leave-one-out), el usuario fue explicito y tajante: "el hecho de que compares las cuotas con otras casas no me interesa x b, uno x b siempre maneja unas buenas cuotas... bajale a un cincuenta y cinco por ciento a ver que nos vota, y omite lo de comparar las casas de apuestas con un x bet, lo que la cuota que de un x bet, esa sera la que juguemos. Necesito es que me digas cual es la apuesta que yo debo hacer."
- **Decision del usuario (tres partes, todas aplicadas)**:
  1. Eliminar por completo la comparacion de la cuota de 1xBet contra la mediana de otras casas (el metodo leave-one-out introducido el 2026-08-29).
  2. Bajar `UMBRAL_PROBABILIDAD_MINIMA` de 0.65 a **0.55**.
  3. En vez de solo listar hallazgos o reportar "0 resultados", identificar y comunicar de forma directa y prominente cual es LA apuesta recomendada.
- **Cambios en valor_prepartido.py**:
  1. Se elimina la funcion `cuota_justa_leave_one_out()` y la constante `MINIMO_CASAS_REFERENCIA` -- ya no hay comparacion contra otras casas de apuestas.
  2. Nueva funcion `probabilidad_propia_1xbet()`: calcula la probabilidad implicita **unicamente** con las cuotas que 1xBet ofrece para ese partido (1/cuota, devigged dividiendo por la suma de las implicitas del propio partido en 1xBet). No involucra a ninguna otra casa.
  3. `UMBRAL_PROBABILIDAD_MINIMA` baja de 0.65 a **0.55**.
  4. `ejecutar_ronda()` ya no filtra por numero de casas de referencia (eliminado por completo).
  5. Nuevas funciones de formato: `formatear_recomendacion_principal()` (mensaje destacado "LA APUESTA QUE DEBES HACER", enviado primero, para la senal de mayor probabilidad) y `formatear_alternativa()` (para el resto de senales, si las hay, en orden descendente de probabilidad).
- **Limitacion honesta que sigue vigente**: la "probabilidad" que calcula el bot sigue siendo la probabilidad implicita en las propias cuotas de 1xBet (que tan favorito es un resultado segun la casa), NO un analisis de lesionados, alineaciones, formaciones o forma de jugadores -- esa fuente de datos de futbol real aun no esta conectada al sistema (ver entrada anterior sobre API-Football/Sportmonks, todavia sin contratar).
- **Pendiente**: correr el workflow manualmente contra la API real con este nuevo metodo y reportar el resultado real al usuario -- incluyendo, si corresponde, la recomendacion directa de apuesta, o una explicacion honesta si tampoco hay ninguna senal que llegue al 55%.
- **No fabricado**: este cambio de diseno responde directamente a una instruccion explicita y verbatim del usuario, no a una decision unilateral del asistente. El codigo fue verificado por sintaxis (ast.parse) antes de publicarse y el contenido publicado fue verificado byte a byte via curl contra el archivo raw de GitHub tras el commit.
