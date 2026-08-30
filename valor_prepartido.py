"""
Bot de Valor Pre-Partido -- Superagente Quant MAXYURSPORTS
============================================================
Segundo proceso permanente del sistema (distinto del bot de cobertura
en vivo de telegram_alert_bot.py). Este corre ANTES de que empiecen los
partidos y busca apuestas EJECUTABLES EN 1XBET, que es la unica casa
que usa el usuario.

AJUSTE 2026-08-30 (pedido explicito del usuario, cambio de metodo):
  El usuario fue explicito: "el hecho de que compares las cuotas con
  otras casas no me interesa x b, uno x b siempre maneja unas buenas
  cuotas... omite lo de comparar las casas de apuestas con un x bet,
  lo que la cuota que de un x bet, esa sera la que juguemos."

  Esto significa que se ELIMINA POR COMPLETO el metodo anterior
  (leave-one-out contra la mediana de otras casas). Ya NO se compara
  a 1xBet contra nadie. La probabilidad "justa" de un resultado se
  calcula EXCLUSIVAMENTE con las cuotas que ofrece 1xBet para ese
  mismo partido (implicita = 1/cuota, devigged dividiendo por la suma
  de todas las implicitas de 1xBet DENTRO DEL MISMO MERCADO). El
  umbral minimo de probabilidad es 0.55.

AJUSTE 2026-08-30 (mismo dia, ampliacion de mercados y deportes,
pedido explicito del usuario): "Sí, quiero que agregues todos los
mercados que te envié del fútbol y que agregues los otros deportes
que te dije. Recuerda que tu trabajo es buscarme las mejores apuestas
que puedo hacer."

  Cambios:
    1. Futbol ya no se evalua solo en el mercado h2h (1x2). Ahora se
       piden tambien: totals (total de goles over/under), spreads
       (hándicap asiatico/europeo), btts (ambos anotan), draw_no_bet
       (sin empate) y double_chance (doble oportunidad). Estos son
       los mercados que The Odds API efectivamente soporta para
       futbol -- ver LIMITACION HONESTA abajo para lo que NO cubre.
    2. Se agregan otros deportes que el usuario pidio explicitamente:
       baloncesto (NBA, NCAAB, Euroleague), hockey sobre hielo (NHL),
       beisbol (MLB) y eSports (League of Legends, CS:GO, Dota 2,
       Valorant), cada uno con los mercados que The Odds API soporta
       para ese deporte (h2h siempre; spreads/totals donde aplica).
    3. Tenis se agrega de forma DINAMICA: en vez de hardcodear
       torneos (que cambian constantemente -- Wimbledon, US Open,
       Roland Garros, etc. solo existen como sport_key mientras el
       torneo esta activo), el bot consulta el endpoint /v4/sports
       de The Odds API (esta consulta NO consume creditos segun la
       documentacion oficial) y toma los torneos ATP/WTA activos en
       este momento, hasta un maximo de MAX_TORNEOS_TENIS para no
       disparar el consumo de creditos.
    4. Cada resultado ahora se etiqueta con el nombre del mercado
       (ej. "Total de goles/puntos (2.5)", "Hándicap (-1.5)") para
       que el usuario sepa exactamente que tipo de apuesta es, no
       solo el resultado 1x2.

  LIMITACION HONESTA: The Odds API no cubre toda la granularidad que
  el usuario pidio originalmente (corners por minuto, tarjetas,
  marcador exacto, mercados de jugador, mercados en vivo detallados).
  Esta es una limitacion de la fuente de datos actual, no del diseno
  del bot -- cubrir esos mercados requeriria evaluar una fuente de
  datos adicional.

  IMPACTO EN CONSUMO DE CREDITOS: pedir varios mercados a la vez
  cuesta mas creditos por llamada (The Odds API cobra por
  mercados x regiones solicitados, no por partido). Antes cada
  llamada de futbol costaba ~1 credito; ahora puede costar hasta 6
  (un credito por cada uno de los 6 mercados pedidos). Se sube el
  freno de seguridad de creditos (UMBRAL_CREDITOS_SEGURIDAD) de 15 a
  50 para compensar, y se sigue deteniendo la ronda si el saldo baja
  demasiado, para nunca dejar la cuenta en 0 a mitad de mes.

LIMITACION HONESTA QUE SIGUE VIGENTE: la probabilidad que calcula este
bot sigue siendo la probabilidad IMPLICITA en las cuotas de 1xBet
(cuanto cree la propia casa que un resultado va a pasar), NO una
probabilidad calculada con datos reales de futbol/deporte (lesionados,
alineaciones, forma, remates al arco, etc.). Esa fuente de datos aun
NO esta conectada al sistema -- requiere contratar una API paga (ej.
API-Football, ver CHANGELOG 2026-08-30).

Variables de entorno requeridas (las mismas que ya usa el bot de
cobertura en vivo):
    TELEGRAM_BOT_TOKEN
    TELEGRAM_CHAT_ID
    ODDS_API_KEY

Se ejecuta via GitHub Actions (.github/workflows/valor_prepartido.yml).
"""

import json
import os
import pathlib
from datetime import datetime, timezone, timedelta

import requests

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
ODDS_API_KEY = os.environ.get("ODDS_API_KEY", "")

ODDS_API_BASE = "https://api.the-odds-api.com/v4"

# La unica casa que usa el usuario. Todo el analisis gira en torno a
# esta casa -- no tiene sentido para el usuario que el bot le muestre
# valor en una casa donde no tiene cuenta.
CASA_UNICA = "1xBet"

# ----------------------------------------------------------------------
# LIGAS DE FUTBOL (estaticas, curadas -- igual que antes del 2026-08-30)
# ----------------------------------------------------------------------
LIGAS_FUTBOL = [
    "soccer_epl",
    "soccer_spain_la_liga",
    "soccer_uefa_champs_league",
    "soccer_uefa_europa_league",
    "soccer_uefa_europa_conference_league",
    "soccer_germany_bundesliga",
    "soccer_italy_serie_a",
    "soccer_france_ligue_one",
    "soccer_brazil_campeonato",
    "soccer_argentina_primera_division",
    "soccer_mexico_ligamx",
    "soccer_usa_mls",
    "soccer_chile_campeonato",
    "soccer_netherlands_eredivisie",
    "soccer_portugal_primeira_liga",
    "soccer_turkey_super_league",
    "soccer_efl_champ",
    "soccer_saudi_arabia_pro_league",
    "soccer_germany_bundesliga2",
    "soccer_spain_segunda_division",
    "soccer_belgium_first_div",
    "soccer_austria_bundesliga",
    "soccer_switzerland_superleague",
    "soccer_denmark_superliga",
    "soccer_conmebol_copa_libertadores",
    "soccer_spl",                      # Escocia
    "soccer_norway_eliteserien",
    "soccer_sweden_allsvenskan",
    "soccer_japan_j_league",
    "soccer_korea_kleague1",
    "soccer_england_league1",
    "soccer_england_league2",
    "soccer_france_ligue_two",
    "soccer_italy_serie_b",
    "soccer_brazil_serie_b",
]

# Otros deportes pedidos explicitamente por el usuario (2026-08-30):
# baloncesto, hockey sobre hielo, beisbol, eSports. Claves estables de
# The Odds API (no cambian temporada a temporada como los torneos de
# tenis).
LIGAS_BALONCESTO = ["basketball_nba", "basketball_ncaab", "basketball_euroleague"]
LIGAS_HOCKEY = ["icehockey_nhl"]
LIGAS_BEISBOL = ["baseball_mlb"]
# AJUSTE 2026-08-30 (fix critico post-ronda real): las claves fijas
# "esports_csgo", "esports_dota2", "esports_valorant" dieron 404 Not
# Found en la ronda real -- no son claves validas de The Odds API tal
# como estaban escritas (los nombres exactos de eSports cambian mas
# de lo esperado). Se agregan de forma DINAMICA igual que el tenis,
# consultando /v4/sports (gratis) y tomando lo que empiece con
# "esports_" y este activo, en vez de arriesgarnos a adivinar mal el
# nombre de nuevo.
MAX_LIGAS_ESPORTS = 6

# Tenis se agrega de forma dinamica (ver obtener_torneos_tenis_activos)
# porque los sport_key de The Odds API son por torneo especifico y
# cambian segun el calendario (Wimbledon, US Open, Roland Garros...).
MAX_TORNEOS_TENIS = 8

# Mercados a solicitar por grupo de deporte. h2h = ganador del
# partido/set; totals = total de goles/puntos/juegos; spreads =
# hándicap; btts = ambos anotan (solo futbol); draw_no_bet = sin
# empate (solo futbol); double_chance = doble oportunidad (solo
# futbol). Estos son los mercados que The Odds API efectivamente
# soporta -- no cubre corners, tarjetas, marcador exacto, ni mercados
# de jugador (ver LIMITACION HONESTA en el docstring del modulo).
MERCADOS_POR_GRUPO = {
    "soccer": "h2h,totals,spreads,btts,draw_no_bet,double_chance",
    "basketball": "h2h,spreads,totals",
    "icehockey": "h2h,spreads,totals",
    "baseball": "h2h,spreads,totals",
    "tennis": "h2h,spreads,totals",
    "esports": "h2h",
}

# Nombres legibles en español para cada mercado, usados en los
# mensajes de Telegram.
NOMBRES_MERCADO = {
    "h2h": "Ganador del partido",
    "totals": "Total de goles/puntos",
    "spreads": "Hándicap",
    "btts": "Ambos anotan",
    "draw_no_bet": "Sin empate (DNB)",
    "double_chance": "Doble oportunidad",
}

# Ventana hacia adelante en la que buscamos partidos (horas).
VENTANA_HORAS = 6

# AJUSTE 2026-08-30 (pedido explicito del usuario -- ver docstring del
# modulo): probabilidad minima para considerar una senal. Ya no se
# compara contra otras casas -- esta probabilidad es la implicita en
# las propias cuotas de 1xBet, devigged dentro de cada mercado.
UMBRAL_PROBABILIDAD_MINIMA = 0.55

# AJUSTE 2026-08-30 (ampliacion de mercados): al pedir varios mercados
# por llamada el costo en creditos por llamada sube (The Odds API
# cobra aprox. 1 credito por mercado solicitado, por region). Se sube
# el freno de seguridad de 15 a 50 para no arriesgar quedarse sin
# creditos a mitad de ronda.
UMBRAL_CREDITOS_SEGURIDAD = 50

# --- Kelly fraccionado (protocolo existente del Excel, punto 24) ---
KELLY_FRACCION = 0.10
KELLY_TOPE_MAXIMO = 0.03  # 3% de la banca, tope duro


ESTADO_DIR = pathlib.Path(__file__).parent / "estado"
HISTORIAL_CUOTAS_PATH = ESTADO_DIR / "historial_cuotas.jsonl"


# ----------------------------------------------------------------------
# THE ODDS API
# ----------------------------------------------------------------------

def _creditos_restantes(resp: requests.Response) -> int:
    try:
        return int(resp.headers.get("x-requests-remaining", "-1"))
    except (TypeError, ValueError):
        return -1


def grupo_de_sport_key(sport_key: str) -> str:
    """Determina el grupo de deporte (para saber que mercados pedir)."""
    prefijos = [
        ("soccer_", "soccer"),
        ("basketball_", "basketball"),
        ("icehockey_", "icehockey"),
        ("baseball_", "baseball"),
        ("tennis_", "tennis"),
        ("esports_", "esports"),
    ]
    for prefijo, grupo in prefijos:
        if sport_key.startswith(prefijo):
            return grupo
    return "soccer"  # fallback conservador


def obtener_torneos_tenis_activos() -> list:
    """
    Consulta /v4/sports para obtener los torneos de tenis ATP/WTA
    activos ahora mismo. Esta consulta NO consume creditos de la
    cuota mensual segun la documentacion de The Odds API. Devuelve
    una lista de sport_key, limitada a MAX_TORNEOS_TENIS para no
    disparar el consumo de creditos en las llamadas de /odds que
    vienen despues.
    """
    if not ODDS_API_KEY:
        return []
    url = f"{ODDS_API_BASE}/sports"
    try:
        resp = requests.get(url, params={"apiKey": ODDS_API_KEY, "all": "false"}, timeout=20)
        resp.raise_for_status()
        deportes = resp.json()
    except (requests.RequestException, ValueError) as e:
        print(f"[ERROR] no se pudo consultar /v4/sports para tenis: {e}")
        return []
    torneos = [
        d["key"] for d in deportes
        if isinstance(d, dict) and d.get("key", "").startswith("tennis_") and d.get("active")
    ]
    return torneos[:MAX_TORNEOS_TENIS]


def obtener_ligas_esports_activas() -> list:
    """
    Igual que obtener_torneos_tenis_activos pero para eSports: consulta
    /v4/sports (gratis) y toma las claves activas que empiecen con
    "esports_", en vez de hardcodear nombres que resultaron invalidos
    (ver AJUSTE 2026-08-30 arriba).
    """
    if not ODDS_API_KEY:
        return []
    url = f"{ODDS_API_BASE}/sports"
    try:
        resp = requests.get(url, params={"apiKey": ODDS_API_KEY, "all": "false"}, timeout=20)
        resp.raise_for_status()
        deportes = resp.json()
    except (requests.RequestException, ValueError) as e:
        print(f"[ERROR] no se pudo consultar /v4/sports para eSports: {e}")
        return []
    ligas = [
        d["key"] for d in deportes
        if isinstance(d, dict) and d.get("key", "").startswith("esports_") and d.get("active")
    ]
    return ligas[:MAX_LIGAS_ESPORTS]


def _pedir_odds(sport_key: str, markets: str):
    url = f"{ODDS_API_BASE}/sports/{sport_key}/odds/"
    resp = requests.get(
        url,
        params={
            "apiKey": ODDS_API_KEY,
            # Solo region "eu" -- ahi aparece 1xBet, y no pagamos
            # creditos de mas por regiones (uk, us) que el usuario
            # nunca va a poder usar.
            "regions": "eu",
            "markets": markets,
            "oddsFormat": "decimal",
        },
        timeout=20,
    )
    resp.raise_for_status()
    return resp


# AJUSTE 2026-08-30 (fix critico post-ronda real): pedir los 6
# mercados de futbol juntos (h2h,totals,spreads,btts,draw_no_bet,
# double_chance) devolvio 422 "Unprocessable Entity" en las 32 ligas
# de futbol en la ronda real de las 09:14 UTC -- The Odds API rechazo
# la combinacion completa (probablemente btts/draw_no_bet/
# double_chance no son validos juntos con el resto en la region "eu"
# para muchas ligas). Resultado real: 0 partidos de futbol analizados
# esa ronda, el deporte principal del usuario quedo sin cobertura.
# Fallback: si la peticion con todos los mercados falla, se reintenta
# SOLO con el combo basico h2h,totals,spreads (probado, funciona --
# ver logs reales de basketball/hockey/baseball/tenis en esa misma
# ronda). Esto prioriza tener datos reales de futbol sobre tener
# todos los mercados; los mercados adicionales (btts, draw_no_bet,
# double_chance) quedan pendientes de una investigacion mas
# cuidadosa de que combinaciones acepta la API por region/liga.
MERCADOS_BASICOS_FALLBACK = "h2h,totals,spreads"


def obtener_cuotas(sport_key: str, markets: str):
    if not ODDS_API_KEY:
        return [], -1
    try:
        resp = _pedir_odds(sport_key, markets)
    except requests.RequestException as e:
        status = getattr(getattr(e, "response", None), "status_code", None)
        if status == 422 and markets != MERCADOS_BASICOS_FALLBACK:
            print(f"[INFO] {sport_key}: 422 con mercados={markets}, "
                  f"reintentando con fallback basico ({MERCADOS_BASICOS_FALLBACK})")
            try:
                resp = _pedir_odds(sport_key, MERCADOS_BASICOS_FALLBACK)
            except requests.RequestException as e2:
                print(f"[ERROR] odds {sport_key} (fallback tambien fallo): {e2}")
                return [], -1
        else:
            print(f"[ERROR] odds {sport_key}: {e}")
            return [], -1
    return resp.json(), _creditos_restantes(resp)


# ----------------------------------------------------------------------
# ANALISIS: probabilidad implicita en las PROPIAS cuotas de 1xBet,
# por mercado (sin comparar contra ninguna otra casa -- pedido
# explicito del usuario, 2026-08-30)
# ----------------------------------------------------------------------

def cuotas_por_mercado(partido: dict) -> dict:
    """
    { (market_key, point): { resultado: {casa: cuota} } }

    'point' es None para mercados sin linea (h2h, btts, draw_no_bet,
    double_chance) y el valor numerico de la linea para mercados con
    linea (totals, spreads) -- por ejemplo (totals, 2.5) agrupa el
    Over/Under de la linea 2.5 goles, separado de otras lineas.
    """
    tabla = {}
    for bookmaker in partido.get("bookmakers", []):
        casa = bookmaker["title"]
        for market in bookmaker.get("markets", []):
            mkey = market.get("key")
            for outcome in market.get("outcomes", []):
                nombre = outcome["name"]
                precio = outcome["price"]
                punto = outcome.get("point")
                clave = (mkey, punto)
                tabla.setdefault(clave, {}).setdefault(nombre, {})[casa] = precio
    return tabla


def cuotas_1xbet_por_mercado(tabla_mercados: dict) -> dict:
    """{ (market_key, point): {resultado: cuota} } solo de 1xBet."""
    resultado = {}
    for clave, outcomes in tabla_mercados.items():
        propias = {}
        for nombre, precios in outcomes.items():
            if CASA_UNICA in precios:
                propias[nombre] = precios[CASA_UNICA]
        if propias:
            resultado[clave] = propias
    return resultado


def probabilidad_propia_1xbet(cuotas_propias: dict) -> dict:
    """
    Probabilidad "justa" calculada UNICAMENTE con las cuotas que 1xBet
    ofrece para ESTE mercado especifico -- sin mirar ninguna otra
    casa, y sin mezclar mercados distintos entre si (cada mercado se
    devigea por separado, para no inflar ni distorsionar el margen).

    Se toma la probabilidad implicita de cada resultado (1/cuota) y se
    "devigea" dividiendo por la suma de todas las implicitas del
    mercado (el overround/margen propio de 1xBet).
    """
    # AJUSTE 2026-08-30 (fix critico): si 1xBet solo trae UN resultado
    # cotizado para este mercado (por ejemplo solo un lado de un
    # handicap), no hay nada que devigear -- la formula anterior
    # devolvia 100% de probabilidad siempre en ese caso (implicita
    # dividida entre si misma), lo cual es un artefacto matematico,
    # NO una probabilidad real. Se detecto en la ronda real del
    # 2026-08-30 09:14 UTC: 23 de 24 "hallazgos" enviados a Telegram
    # eran falsos 100% por este bug. Ahora se exige minimo 2
    # resultados cotizados por 1xBet en el mismo mercado para poder
    # calcular una probabilidad valida.
    if not cuotas_propias or len(cuotas_propias) < 2:
        return {}
    implicita = {r: 1 / c for r, c in cuotas_propias.items() if c and c > 0}
    if len(implicita) < 2:
        return {}
    overround = sum(implicita.values())
    if overround <= 0:
        return {}
    return {r: implicita[r] / overround for r in implicita}


def etiqueta_mercado(market_key: str, punto) -> str:
    base = NOMBRES_MERCADO.get(market_key, market_key)
    if punto is not None:
        return f"{base} ({punto})"
    return base


def kelly_fraccionado(prob: float, cuota: float) -> float:
    """
    Kelly fraccionado 0.10 con tope duro de 3% (protocolo del Excel,
    punto 24). Devuelve fraccion de banca sugerida (0.0 a 0.03).
    """
    b = cuota - 1
    if b <= 0:
        return 0.0
    kelly_completo = ((b * prob) - (1 - prob)) / b
    kelly_completo = max(kelly_completo, 0.0)
    fraccion = kelly_completo * KELLY_FRACCION
    return round(min(fraccion, KELLY_TOPE_MAXIMO), 4)


# ----------------------------------------------------------------------
# HISTORIAL DE CUOTAS (para CLV y steam moves -- puntos 4, 17, 18)
# ----------------------------------------------------------------------

def guardar_en_historial(evento_id: str, partido: str, deporte: str, momento: str, tabla_mercados: dict) -> None:
    ESTADO_DIR.mkdir(parents=True, exist_ok=True)
    # Las claves de tabla_mercados son tuplas (market_key, point), que
    # no son serializables directamente a JSON -- se convierten a
    # texto "market_key|point".
    cuotas_serializables = {
        f"{mkey}|{punto}": outcomes for (mkey, punto), outcomes in tabla_mercados.items()
    }
    registro = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "evento_id": evento_id,
        "partido": partido,
        "deporte": deporte,
        "momento_consulta": momento,
        "cuotas": cuotas_serializables,
    }
    with HISTORIAL_CUOTAS_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(registro, ensure_ascii=False) + "\n")


# ----------------------------------------------------------------------
# TELEGRAM
# ----------------------------------------------------------------------

def enviar_telegram(mensaje: str) -> bool:
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("[ERROR] Falta TELEGRAM_BOT_TOKEN o TELEGRAM_CHAT_ID.")
        return False
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    resp = requests.post(
        url,
        data={"chat_id": TELEGRAM_CHAT_ID, "text": mensaje, "parse_mode": "HTML"},
        timeout=15,
    )
    if resp.status_code != 200:
        print(f"[ERROR] Telegram respondio {resp.status_code}: {resp.text}")
        return False
    return True


def formatear_recomendacion_principal(partido_nombre: str, deporte: str, mercado: str, inicio: str,
                                       resultado: str, prob: float, cuota: float) -> str:
    stake = kelly_fraccionado(prob, cuota)
    return (
        f"✅ <b>LA APUESTA QUE DEBES HACER</b>\n"
        f"{partido_nombre} ({deporte})\n"
        f"Inicio: {inicio}\n\n"
        f"Mercado: <b>{mercado}</b>\n"
        f"Juega: <b>{resultado}</b>\n"
        f"Cuota en 1xBet: <b>{cuota}</b>\n"
        f"Probabilidad segun 1xBet: <b>{prob*100:.1f}%</b>\n"
        f"Stake sugerido (Kelly 0.10, tope 3%): {stake*100:.2f}% de banca\n\n"
        f"⚠️ Esta probabilidad viene de la propia cuota de 1xBet (no de "
        f"analisis de lesionados/alineaciones -- eso todavia no esta "
        f"conectado). Aun asi, aproximadamente {round((1-prob)*100)} de "
        f"cada 100 veces esta apuesta se pierde. Verifica el precio "
        f"actual en la app antes de apostar."
    )


def formatear_alternativa(partido_nombre: str, deporte: str, mercado: str, inicio: str,
                           resultado: str, prob: float, cuota: float) -> str:
    stake = kelly_fraccionado(prob, cuota)
    return (
        f"➕ <b>Otra opcion con {prob*100:.1f}% de probabilidad</b>\n"
        f"{partido_nombre} ({deporte})\n"
        f"Inicio: {inicio}\n"
        f"Mercado: {mercado} | Resultado: <b>{resultado}</b> | Cuota 1xBet: {cuota} | "
        f"Stake sugerido: {stake*100:.2f}% de banca"
    )


# ----------------------------------------------------------------------
# RONDA PRINCIPAL
# ----------------------------------------------------------------------

def ejecutar_ronda() -> None:
    ahora = datetime.now(timezone.utc)
    limite = ahora + timedelta(hours=VENTANA_HORAS)
    hallazgos = []
    partidos_sin_1xbet = 0

    torneos_tenis = obtener_torneos_tenis_activos()
    print(f"[INFO] Torneos de tenis activos detectados (max {MAX_TORNEOS_TENIS}): {torneos_tenis}")

    ligas_esports = obtener_ligas_esports_activas()
    print(f"[INFO] Ligas de eSports activas detectadas (max {MAX_LIGAS_ESPORTS}): {ligas_esports}")

    deportes_a_revisar = (
        LIGAS_FUTBOL + LIGAS_BALONCESTO + LIGAS_HOCKEY + LIGAS_BEISBOL + torneos_tenis + ligas_esports
    )

    for sport_key in deportes_a_revisar:
        grupo = grupo_de_sport_key(sport_key)
        markets = MERCADOS_POR_GRUPO.get(grupo, "h2h")
        partidos, restantes = obtener_cuotas(sport_key, markets)
        print(f"[INFO] {sport_key} ({grupo}, mercados={markets}): {len(partidos)} partidos, creditos restantes: {restantes}")

        if restantes != -1 and restantes < UMBRAL_CREDITOS_SEGURIDAD:
            print("[INFO] Pocos creditos restantes este mes -- deteniendo la ronda por seguridad.")
            break

        for partido in partidos:
            inicio = datetime.fromisoformat(partido["commence_time"].replace("Z", "+00:00"))
            if not (ahora <= inicio <= limite):
                continue

            tabla_mercados = cuotas_por_mercado(partido)
            if not tabla_mercados:
                continue

            propias_por_mercado = cuotas_1xbet_por_mercado(tabla_mercados)
            if not propias_por_mercado:
                partidos_sin_1xbet += 1
                continue  # 1xBet no cubre este partido en ningun mercado pedido

            nombre_partido = f"{partido['home_team']} vs {partido['away_team']}"
            guardar_en_historial(partido["id"], nombre_partido, sport_key, "pre_partido", tabla_mercados)

            # AJUSTE 2026-08-30: probabilidad calculada SOLO con las
            # cuotas propias de 1xBet, por mercado -- ya no se compara
            # contra otras casas (pedido explicito del usuario).
            for (mkey, punto), propias in propias_por_mercado.items():
                probs = probabilidad_propia_1xbet(propias)
                mercado_legible = etiqueta_mercado(mkey, punto)

                for resultado, cuota in propias.items():
                    prob = probs.get(resultado)
                    if prob is None:
                        continue
                    if prob < UMBRAL_PROBABILIDAD_MINIMA:
                        continue
                    print(
                        f"[DETALLE] {nombre_partido} ({sport_key}) | mercado={mercado_legible} | "
                        f"resultado={resultado} | cuota_1xbet={cuota} | prob_1xbet={prob*100:.1f}%"
                    )
                    hallazgos.append(
                        (nombre_partido, sport_key, mercado_legible, inicio.isoformat(), resultado, prob, cuota)
                    )

    # La de MAYOR probabilidad va primero -- esa es LA recomendacion.
    hallazgos.sort(key=lambda h: h[5], reverse=True)

    print(f"[INFO] Hallazgos con probabilidad >= {UMBRAL_PROBABILIDAD_MINIMA*100:.0f}% en 1xBet: {len(hallazgos)}")
    print(f"[INFO] Partidos saltados por no estar en 1xBet: {partidos_sin_1xbet}")

    if not hallazgos:
        print("[INFO] Ronda completada. Ninguna cuota de 1xBet llega al "
              f"{UMBRAL_PROBABILIDAD_MINIMA*100:.0f}% de probabilidad implicita en esta ventana de tiempo, "
              "en ningun mercado ni deporte revisado.")
        return

    # La primera (mayor probabilidad) se manda como LA recomendacion
    # principal -- respuesta directa a "cual es la apuesta que debo
    # hacer". El resto (si hay) se manda como alternativas, en orden.
    principal = hallazgos[0]
    msg_principal = formatear_recomendacion_principal(
        principal[0], principal[1], principal[2], principal[3], principal[4], principal[5], principal[6]
    )
    if enviar_telegram(msg_principal):
        print(f"Recomendacion principal enviada: {principal[0]} | {principal[2]} | {principal[4]} | prob={principal[5]*100:.1f}%")

    for nombre, deporte, mercado, inicio, resultado, prob, cuota in hallazgos[1:]:
        msg = formatear_alternativa(nombre, deporte, mercado, inicio, resultado, prob, cuota)
        if enviar_telegram(msg):
            print(f"Alternativa enviada: {nombre} | {mercado} | {resultado} | prob={prob*100:.1f}%")


if __name__ == "__main__":
    ejecutar_ronda()
