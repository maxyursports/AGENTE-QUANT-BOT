"""
Bot de Alertas en Vivo — Superagente Quant MAXYURSPORTS
=========================================================
Revisa los partidos EN CURSO de las ligas permitidas, detecta cuándo el
favorito (según la cuota promedio en vivo) va perdiendo o empatando, y
calcula la cobertura exacta (hedge_calculator.py) antes de mandar la
alerta a Telegram.

Corre solo, sin supervisión, vía GitHub Actions (ver
.github/workflows/monitor_partidos.yml) — gratis, sin depender de que
tu computador esté prendido ni de una conversación activa.

FUENTE DE DATOS: The Odds API (https://the-odds-api.com), plan de pago
"20K" (USD $30/mes, 20,000 créditos/mes).

=====================================================================
NOTA — PRESUPUESTO DE CRÉDITOS (plan de pago activo desde ago-2026)
=====================================================================
Con 20,000 créditos/mes hay margen de sobra para revisar 25 ligas
del catálogo en cada corrida, incluso con el cron corriendo cada
15-30 minutos (revisar 25 ligas cuesta ~25-50 créditos por
corrida; a una corrida cada 15 min eso son ~2,400-4,800 créditos/día
en el peor caso, muy por debajo del tope mensual). Por eso:
  1) USAR_SOLO_PRIORITARIAS quedó en False — se revisan las 25 ligas
     completas (LIGAS_TODAS) en cada corrida.
  2) El cron en monitor_partidos.yml corre cada 15-30 minutos.
  3) El freno de seguridad por créditos bajos (COLCHON_MINIMO_CREDITOS)
     se deja activo igual, como respaldo ante cualquier imprevisto.

La lista de 25 ligas (LIGAS_TODAS más abajo) se verificó contra el
endpoint real /v4/sports de The Odds API (script list_sports.py) antes
de agregarla, para confirmar que cada sport_key existe de verdad.

Si algún mes se agotan los créditos antes de tiempo, el script se
detiene solo (ver ejecutar_ronda) y no genera errores ni cobros
adicionales — el plan no hace auto-upgrade a mayor consumo.
=====================================================================

Variables de entorno requeridas:
    TELEGRAM_BOT_TOKEN   -> el token que dio @BotFather
    TELEGRAM_CHAT_ID     -> el chat id del usuario
    ODDS_API_KEY         -> la llave de the-odds-api.com (plan de pago 20K)
"""

import json
import os
import pathlib
from datetime import datetime, timezone

import requests

from hedge_calculator import analizar_cobertura

# ---------------------------------------------------------------------
# CONFIGURACIÓN
# ---------------------------------------------------------------------

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
ODDS_API_KEY = os.environ.get("ODDS_API_KEY", "")

ODDS_API_BASE = "https://api.the-odds-api.com/v4"

# Las 25 mejores ligas de fútbol para el proyecto, elegidas por liquidez
# (muchas casas de apuestas cubriéndolas -> promedio de cuotas confiable),
# volumen de partidos por semana y profundidad de mercados. Verificadas
# una por una contra /v4/sports antes de agregarlas (ver list_sports.py).
# OJO: Liga BetPlay (Colombia) y Primera División de Uruguay NO aparecen
# en el catálogo de este proveedor — no es un descarte nuestro, es que
# esta fuente de datos no las tiene.
LIGAS_TODAS = [
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
]

# Subconjunto reducido, útil solo si en algún momento se quiere volver
# a limitar el consumo de créditos (por ejemplo, si se baja de plan).
# Con el plan de pago activo, USAR_SOLO_PRIORITARIAS = False y se usan
# las 25 ligas completas (LIGAS_TODAS).
USAR_SOLO_PRIORITARIAS = False
LIGAS_PRIORITARIAS = [
    "soccer_epl",
    "soccer_spain_la_liga",
    "soccer_uefa_champs_league",
    "soccer_brazil_campeonato",
    "soccer_mexico_ligamx",
]
LIGAS_A_REVISAR = LIGAS_PRIORITARIAS if USAR_SOLO_PRIORITARIAS else LIGAS_TODAS

# No alertar en los primeros minutos (un gol tempranero no es señal
# fuerte todavía) ni en el descuento final (ya no da tiempo real para
# que la cobertura tenga sentido).
MINUTO_MINIMO_ALERTA = 30
MINUTO_MAXIMO_ALERTA = 88

# Cuota mínima de la opción "contraria" para que valga la pena avisar.
UMBRAL_CUOTA_MINIMA_ALERTA = 2.2

# Frena la ronda si quedan menos de este número de créditos en el mes,
# para nunca dejar la cuenta en cero sin darnos cuenta.
COLCHON_MINIMO_CREDITOS = 15

ESTADO_PATH = pathlib.Path(__file__).parent / "estado" / "alertas_enviadas.json"


# ---------------------------------------------------------------------
# ESTADO (para no repetir la misma alerta en cada corrida)
# ---------------------------------------------------------------------

def cargar_alertas_enviadas() -> set:
    if not ESTADO_PATH.exists():
        return set()
    try:
        data = json.loads(ESTADO_PATH.read_text())
        return set(data.get("event_ids", []))
    except Exception:
        return set()


def guardar_alertas_enviadas(ids: set) -> None:
    ESTADO_PATH.parent.mkdir(parents=True, exist_ok=True)
    ESTADO_PATH.write_text(json.dumps({"event_ids": sorted(ids)}, indent=2))


# ---------------------------------------------------------------------
# TELEGRAM
# ---------------------------------------------------------------------

def enviar_alerta_telegram(mensaje: str) -> bool:
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("[ERROR] Falta TELEGRAM_BOT_TOKEN o TELEGRAM_CHAT_ID en el entorno.")
        return False
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    resp = requests.post(
        url,
        data={"chat_id": TELEGRAM_CHAT_ID, "text": mensaje, "parse_mode": "HTML"},
        timeout=15,
    )
    if resp.status_code != 200:
        print(f"[ERROR] Telegram respondió {resp.status_code}: {resp.text}")
        return False
    return True


# ---------------------------------------------------------------------
# THE ODDS API
# ---------------------------------------------------------------------

def _creditos_restantes(resp: requests.Response):
    try:
        return int(resp.headers.get("x-requests-remaining", "-1"))
    except (TypeError, ValueError):
        return -1


def obtener_marcadores_en_vivo(sport_key: str):
    """Partidos EN CURSO (ya empezaron, no han terminado) de una liga."""
    if not ODDS_API_KEY:
        return [], -1
    url = f"{ODDS_API_BASE}/sports/{sport_key}/scores/"
    try:
        resp = requests.get(url, params={"apiKey": ODDS_API_KEY}, timeout=20)
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"[ERROR] scores {sport_key}: {e}")
        return [], -1
    restantes = _creditos_restantes(resp)
    partidos = resp.json()
    en_curso = [p for p in partidos if not p.get("completed") and p.get("scores")]
    return en_curso, restantes


def obtener_cuotas_actuales(sport_key: str):
    """Cuotas h2h (1X2) actuales, indexadas por id de partido."""
    if not ODDS_API_KEY:
        return {}, -1
    url = f"{ODDS_API_BASE}/sports/{sport_key}/odds/"
    try:
        resp = requests.get(
            url,
            params={
                "apiKey": ODDS_API_KEY,
                "regions": "eu",
                "markets": "h2h",
                "oddsFormat": "decimal",
            },
            timeout=20,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"[ERROR] odds {sport_key}: {e}")
        return {}, -1
    restantes = _creditos_restantes(resp)
    return {p["id"]: p for p in resp.json()}, restantes


def promedio_cuotas_h2h(partido_odds: dict) -> dict:
    """Promedia la cuota h2h entre todas las casas para no depender de
    una sola. Devuelve {nombre_equipo_o_'Draw': cuota_promedio}."""
    acumulado, conteo = {}, {}
    for bookmaker in partido_odds.get("bookmakers", []):
        for market in bookmaker.get("markets", []):
            if market.get("key") != "h2h":
                continue
            for outcome in market.get("outcomes", []):
                nombre, precio = outcome["name"], outcome["price"]
                acumulado[nombre] = acumulado.get(nombre, 0) + precio
                conteo[nombre] = conteo.get(nombre, 0) + 1
    return {n: acumulado[n] / conteo[n] for n in acumulado}


def minutos_transcurridos(commence_time_iso: str) -> float:
    inicio = datetime.fromisoformat(commence_time_iso.replace("Z", "+00:00"))
    ahora = datetime.now(timezone.utc)
    return (ahora - inicio).total_seconds() / 60


# ---------------------------------------------------------------------
# LÓGICA PRINCIPAL
# ---------------------------------------------------------------------

def evaluar_partido(marcador: dict, cuotas_por_id: dict):
    """Devuelve la info de la alerta si el favorito va perdiendo o
    empatando dentro de la ventana de minutos permitida, o None."""
    event_id = marcador["id"]
    partido_odds = cuotas_por_id.get(event_id)
    if not partido_odds:
        return None

    minuto = minutos_transcurridos(marcador["commence_time"])
    if minuto < MINUTO_MINIMO_ALERTA or minuto > MINUTO_MAXIMO_ALERTA:
        return None

    cuotas = promedio_cuotas_h2h(partido_odds)
    home, away = marcador["home_team"], marcador["away_team"]
    equipos_sin_empate = {k: v for k, v in cuotas.items() if k in (home, away)}
    if len(equipos_sin_empate) < 2:
        return None

    scores = {
        s["name"]: int(s["score"])
        for s in marcador.get("scores", [])
        if s.get("score") is not None
    }
    if home not in scores or away not in scores:
        return None

    favorito = min(equipos_sin_empate, key=equipos_sin_empate.get)
    rival = away if favorito == home else home

    if scores[favorito] > scores[rival]:
        return None  # el favorito va ganando, nada que avisar

    cuota_favorito = equipos_sin_empate[favorito]
    cuota_empate = cuotas.get("Draw")
    cuota_rival = equipos_sin_empate[rival]
    opciones_contrarias = [c for c in (cuota_empate, cuota_rival) if c]
    if not opciones_contrarias:
        return None
    cuota_contraria = max(opciones_contrarias)

    if cuota_contraria < UMBRAL_CUOTA_MINIMA_ALERTA:
        return None

    cobertura = analizar_cobertura(
        stake_original=1.0,
        cuota_original=cuota_favorito,
        cuota_cobertura=cuota_contraria,
    )

    return {
        "event_id": event_id,
        "partido": f"{home} vs {away}",
        "minuto_aprox": round(minuto),
        "marcador": f"{scores[home]}-{scores[away]}",
        "favorito": favorito,
        "cuota_favorito_ahora": round(cuota_favorito, 2),
        "cuota_contraria": round(cuota_contraria, 2),
        "cobertura": cobertura,
    }


def formatear_alerta(info: dict) -> str:
    c = info["cobertura"]
    return (
        f"⚠️ <b>Favorito complicado</b>\n"
        f"{info['partido']}\n"
        f"Minuto aprox. {info['minuto_aprox']} — Marcador {info['marcador']}\n\n"
        f"{info['favorito']} era favorito (cuota ~{info['cuota_favorito_ahora']}) "
        f"y no está ganando ahora mismo.\n"
        f"Cuota contraria en vivo: {info['cuota_contraria']}\n\n"
        f"Por cada 1 unidad apostada al favorito antes del partido:\n"
        f"• Cobertura ganancia igual: {c.stake_cobertura_ganancia_igual:.2f} u. "
        f"→ ganancia garantizada {c.ganancia_garantizada:.2f} u.\n"
        f"• Cobertura solo recuperar: {c.stake_cobertura_solo_recuperar:.2f} u.\n\n"
        f"Esto es un cálculo matemático de cobertura, no una confirmación de "
        f"valor real — la cuota promedio puede diferir de la de tu casa. "
        f"Confírmalo con el agente antes de apostar."
    )


def ejecutar_ronda() -> None:
    ya_alertados = cargar_alertas_enviadas()
    nuevos_alertados = set(ya_alertados)
    creditos_restantes = None

    for sport_key in LIGAS_A_REVISAR:
        if creditos_restantes is not None and creditos_restantes < COLCHON_MINIMO_CREDITOS:
            print(f"[AVISO] Quedan {creditos_restantes} créditos este mes — se detiene la ronda por seguridad.")
            break

        marcadores, restantes_scores = obtener_marcadores_en_vivo(sport_key)
        if restantes_scores >= 0:
            creditos_restantes = restantes_scores
        if not marcadores:
            continue

        cuotas_por_id, restantes_odds = obtener_cuotas_actuales(sport_key)
        if restantes_odds >= 0:
            creditos_restantes = restantes_odds

        for marcador in marcadores:
            event_id = marcador["id"]
            if event_id in ya_alertados:
                continue
            info = evaluar_partido(marcador, cuotas_por_id)
            if not info:
                continue
            enviado = enviar_alerta_telegram(formatear_alerta(info))
            print(f"Alerta {'enviada' if enviado else 'FALLÓ'}: {info['partido']}")
            if enviado:
                nuevos_alertados.add(event_id)

    if creditos_restantes is not None:
        print(f"[INFO] Créditos restantes este mes (aprox.): {creditos_restantes}")

    if nuevos_alertados != ya_alertados:
        guardar_alertas_enviadas(nuevos_alertados)


if __name__ == "__main__":
    ejecutar_ronda()
