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
  a 1xBet contra nadie. Los cambios concretos:

    1. La probabilidad "justa" de un resultado ahora se calcula
       EXCLUSIVAMENTE con las cuotas que ofrece 1xBet para ese mismo
       partido (implicita = 1/cuota, luego devigged dividiendo por la
       suma de todas las implicitas de 1xBet en ese partido -- esto
       quita el margen/overround propio de la casa, pero NO involucra
       a ninguna otra casa de apuestas).
    2. Se elimina MINIMO_CASAS_REFERENCIA y toda la logica de
       "casas de referencia" -- ya no aplica, porque no hay
       comparacion con otras casas.
    3. UMBRAL_PROBABILIDAD_MINIMA baja de 0.65 a 0.55, pedido
       explicito del usuario ("bajale a un cincuenta y cinco por
       ciento a ver que nos vota").
    4. El usuario pidio una respuesta directa: "necesito es que me
       digas cual es la apuesta que yo debo hacer" -- no solo una
       lista filtrada. Por eso, ademas de listar (si hay mas de una)
       todas las que pasan el filtro, el bot ahora identifica y marca
       explicitamente a LA MEJOR (mayor probabilidad) como la
       recomendacion principal, y esa es la que se manda primero y de
       forma mas prominente por Telegram.

LIMITACION HONESTA QUE SIGUE VIGENTE: la probabilidad que calcula este
bot sigue siendo la probabilidad IMPLICITA en las cuotas de 1xBet
(cuanto cree el mercado/la casa que un resultado va a pasar), NO una
probabilidad calculada con datos reales de futbol (lesionados,
alineaciones, forma, remates al arco, etc.). Esa fuente de datos aun
NO esta conectada al sistema -- requiere contratar una API paga (ej.
API-Football, ver CHANGELOG 2026-08-30). Mientras esa fuente no este
conectada, "probabilidad" en este bot quiere decir "que tan favorito
es este resultado segun la propia casa 1xBet", no un analisis de
lesionados/alineaciones/jugadores.

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

# Mismas ligas que ya usa el bot de cobertura en vivo, mas la
# ampliacion del 2026-08-30.
LIGAS_A_REVISAR = [
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

# Ventana hacia adelante en la que buscamos partidos (horas).
VENTANA_HORAS = 6

# AJUSTE 2026-08-30 (pedido explicito del usuario -- ver docstring del
# modulo): probabilidad minima para considerar una senal. Bajado de
# 0.65 a 0.55. Ya no se compara contra otras casas -- esta probabilidad
# es la implicita en las propias cuotas de 1xBet, devigged.
UMBRAL_PROBABILIDAD_MINIMA = 0.55

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


def obtener_cuotas(sport_key: str):
    if not ODDS_API_KEY:
        return [], -1
    url = f"{ODDS_API_BASE}/sports/{sport_key}/odds/"
    try:
        resp = requests.get(
            url,
            params={
                "apiKey": ODDS_API_KEY,
                # Solo region "eu" -- ahi aparece 1xBet, y no pagamos
                # creditos de mas por regiones (uk, us) que el usuario
                # nunca va a poder usar.
                "regions": "eu",
                "markets": "h2h",
                "oddsFormat": "decimal",
            },
            timeout=20,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"[ERROR] odds {sport_key}: {e}")
        return [], -1
    return resp.json(), _creditos_restantes(resp)


# ----------------------------------------------------------------------
# ANALISIS: probabilidad implicita en las PROPIAS cuotas de 1xBet
# (sin comparar contra ninguna otra casa -- pedido explicito del
# usuario, 2026-08-30)
# ----------------------------------------------------------------------

def cuotas_por_resultado(partido: dict) -> dict:
    """{resultado: {casa: cuota}} para el mercado h2h de un partido."""
    tabla = {}
    for bookmaker in partido.get("bookmakers", []):
        for market in bookmaker.get("markets", []):
            if market.get("key") != "h2h":
                continue
            for outcome in market.get("outcomes", []):
                nombre, precio = outcome["name"], outcome["price"]
                tabla.setdefault(nombre, {})[bookmaker["title"]] = precio
    return tabla


def cuotas_1xbet(tabla_cuotas: dict) -> dict:
    """{resultado: cuota} solo de 1xBet, o {} si no cubre el partido."""
    resultado = {}
    for r, precios in tabla_cuotas.items():
        if CASA_UNICA in precios:
            resultado[r] = precios[CASA_UNICA]
    return resultado


def probabilidad_propia_1xbet(cuotas_propias: dict) -> dict:
    """
    Probabilidad "justa" calculada UNICAMENTE con las cuotas que 1xBet
    ofrece para este partido -- sin mirar ninguna otra casa.

    Se toma la probabilidad implicita de cada resultado (1/cuota) y se
    "devigea" dividiendo por la suma de todas las implicitas del
    partido (el overround/margen propio de 1xBet). Esto no cambia el
    orden relativo de favoritismo que ya tiene 1xBet -- solo lo
    normaliza para que sume 100%, en vez de sumar el ~105-110% tipico
    del margen de la casa.
    """
    if not cuotas_propias:
        return {}
    implicita = {r: 1 / c for r, c in cuotas_propias.items() if c and c > 0}
    overround = sum(implicita.values())
    if overround <= 0:
        return {}
    return {r: implicita[r] / overround for r in implicita}


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

def guardar_en_historial(evento_id: str, partido: str, liga: str, momento: str, tabla_cuotas: dict) -> None:
    ESTADO_DIR.mkdir(parents=True, exist_ok=True)
    registro = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "evento_id": evento_id,
        "partido": partido,
        "liga": liga,
        "momento_consulta": momento,
        "cuotas": tabla_cuotas,
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


def formatear_recomendacion_principal(partido_nombre: str, liga: str, inicio: str, resultado: str,
                                       prob: float, cuota: float) -> str:
    stake = kelly_fraccionado(prob, cuota)
    return (
        f"✅ <b>LA APUESTA QUE DEBES HACER</b>\n"
        f"{partido_nombre} ({liga})\n"
        f"Inicio: {inicio}\n\n"
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


def formatear_alternativa(partido_nombre: str, liga: str, inicio: str, resultado: str,
                           prob: float, cuota: float) -> str:
    stake = kelly_fraccionado(prob, cuota)
    return (
        f"➕ <b>Otra opcion con {prob*100:.1f}% de probabilidad</b>\n"
        f"{partido_nombre} ({liga})\n"
        f"Inicio: {inicio}\n"
        f"Resultado: <b>{resultado}</b> | Cuota 1xBet: {cuota} | "
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

    for liga in LIGAS_A_REVISAR:
        partidos, restantes = obtener_cuotas(liga)
        print(f"[INFO] {liga}: {len(partidos)} partidos, creditos restantes: {restantes}")

        if restantes != -1 and restantes < 15:
            print("[INFO] Pocos creditos restantes este mes -- deteniendo la ronda por seguridad.")
            break

        for partido in partidos:
            inicio = datetime.fromisoformat(partido["commence_time"].replace("Z", "+00:00"))
            if not (ahora <= inicio <= limite):
                continue

            tabla = cuotas_por_resultado(partido)
            if len(tabla) < 2:
                continue

            propias = cuotas_1xbet(tabla)
            if not propias:
                partidos_sin_1xbet += 1
                continue  # 1xBet no cubre este partido -- no se puede ejecutar

            nombre_partido = f"{partido['home_team']} vs {partido['away_team']}"
            guardar_en_historial(partido["id"], nombre_partido, liga, "pre_partido", tabla)

            # AJUSTE 2026-08-30: probabilidad calculada SOLO con las
            # cuotas propias de 1xBet -- ya no se compara contra otras
            # casas (pedido explicito del usuario).
            probs = probabilidad_propia_1xbet(propias)

            for resultado, cuota in propias.items():
                prob = probs.get(resultado)
                if prob is None:
                    continue
                if prob < UMBRAL_PROBABILIDAD_MINIMA:
                    continue
                print(
                    f"[DETALLE] {nombre_partido} ({liga}) | resultado={resultado} | "
                    f"cuota_1xbet={cuota} | prob_1xbet={prob*100:.1f}%"
                )
                hallazgos.append(
                    (nombre_partido, liga, inicio.isoformat(), resultado, prob, cuota)
                )

    # La de MAYOR probabilidad va primero -- esa es LA recomendacion.
    hallazgos.sort(key=lambda h: h[4], reverse=True)

    print(f"[INFO] Hallazgos con probabilidad >= {UMBRAL_PROBABILIDAD_MINIMA*100:.0f}% en 1xBet: {len(hallazgos)}")
    print(f"[INFO] Partidos saltados por no estar en 1xBet: {partidos_sin_1xbet}")

    if not hallazgos:
        print("[INFO] Ronda completada. Ninguna cuota de 1xBet llega al "
              f"{UMBRAL_PROBABILIDAD_MINIMA*100:.0f}% de probabilidad implicita en esta ventana de tiempo.")
        return

    # La primera (mayor probabilidad) se manda como LA recomendacion
    # principal -- respuesta directa a "cual es la apuesta que debo
    # hacer". El resto (si hay) se manda como alternativas, en orden.
    principal = hallazgos[0]
    msg_principal = formatear_recomendacion_principal(
        principal[0], principal[1], principal[2], principal[3], principal[4], principal[5]
    )
    if enviar_telegram(msg_principal):
        print(f"Recomendacion principal enviada: {principal[0]} ({principal[3]}) | prob={principal[4]*100:.1f}%")

    for nombre, liga, inicio, resultado, prob, cuota in hallazgos[1:]:
        msg = formatear_alternativa(nombre, liga, inicio, resultado, prob, cuota)
        if enviar_telegram(msg):
            print(f"Alternativa enviada: {nombre} ({resultado}) | prob={prob*100:.1f}%")


if __name__ == "__main__":
    ejecutar_ronda()
