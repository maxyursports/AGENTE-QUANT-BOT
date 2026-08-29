"""
Bot de Valor Pre-Partido -- Superagente Quant MAXYURSPORTS
============================================================
Segundo proceso permanente del sistema (distinto del bot de cobertura
en vivo de telegram_alert_bot.py). Este corre ANTES de que empiecen los
partidos y busca:

  1. Apuestas de valor por comparacion contra el mercado (metodo
     "cuota justa" via devig, igual al que usamos manualmente el
     29-ago-2026 -- puntos 17 de la lista de 40 ideas: Closing Line
     Value / comparacion contra consenso de mercado).
  2. Arbitraje entre casas cuando existe (punto 16).
  3. Tamano de apuesta sugerido con Kelly fraccionado 0.10, tope 3%
     (punto 24 -- integra el protocolo del Excel directamente en el bot).
  4. Guarda cada consulta en un historial de cuotas (estado/historial_cuotas.jsonl)
     para poder medir despues Closing Line Value real y detectar
     "steam moves" (puntos 4 y 18).

LIMITACION HONESTA: el metodo de "cuota justa" de este script compara
casas de apuestas ENTRE SI (asume que el consenso de mercado es
eficiente y busca la casa que se desvia). NO es lo mismo que tener una
probabilidad propia basada en un modelo estadistico (Elo, xG, forma,
lesiones -- ver elo_model.py). Es una estrategia valida y realmente
usada por apostadores cuantitativos, pero el "edge" que encuentra es
mas pequeno y mas raro que el que daria un modelo propio bien
entrenado y validado. Cuando elo_model.py tenga historial suficiente
(ver resultados_historicos.csv), este script se puede extender para
usar tambien la probabilidad del modelo Elo como fuente adicional de
comparacion.

Variables de entorno requeridas (las mismas que ya usa el bot de
cobertura en vivo):
    TELEGRAM_BOT_TOKEN
    TELEGRAM_CHAT_ID
    ODDS_API_KEY

Se ejecuta via GitHub Actions (.github/workflows/valor_prepartido.yml),
programado para correr unas horas antes de cada tanda de partidos.
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

# Mismas 25 ligas que ya usa el bot de cobertura en vivo (punto 1 de
# las 40 ideas: ya estamos usando el catalogo amplio que el plan pago
# permite). Se puede ampliar a otros deportes (punto 39: tenis, etc.)
# agregando sus sport_key aqui, verificados primero contra /v4/sports.
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
]

# Ventana hacia adelante en la que buscamos partidos (horas).
VENTANA_HORAS = 6

# Umbral minimo de EV (contra la cuota justa de mercado) para
# considerar que algo es una posible senal de valor, no solo ruido.
#
# CORRECCION 2026-08-29 (tras la primera corrida real): comparar la
# MEJOR cuota (el maximo entre N casas) contra el promedio del mercado
# tiene un sesgo estadistico conocido -- el maximo de varias
# cotizaciones con ruido casi siempre queda por encima del promedio,
# aunque el mercado sea eficiente. Con 5 casas, la primera corrida real
# encontro 23 "hallazgos" de valor y 5 de arbitraje, una cantidad
# sospechosamente alta comparada con el analisis manual del mismo dia
# (que no encontro nada con un metodo mas estricto). Se sube el umbral
# de 2% a 5% como correccion conservadora inmediata, y se deja
# pendiente en el CHANGELOG una correccion mas rigurosa (comparar
# contra la mediana o excluir la propia casa outlier del calculo del
# promedio, en vez de comparar el maximo contra un promedio que la
# incluye).
UMBRAL_EV_MINIMO = 0.05

# Umbral de arbitraje: si la suma de 1/mejor_cuota de cada resultado
# es menor a este numero, existe una combinacion que gana siempre
# (arbitraje real, punto 16). Se deja un margen de seguridad de 0.5%
# sobre 1.0 por errores de redondeo/timing entre casas.
UMBRAL_ARBITRAJE = 0.995

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
                "regions": "eu,uk,us",
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
# ANALISIS: cuota justa (devig), valor, arbitraje
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


def cuota_justa_por_devig(tabla_cuotas: dict) -> dict:
    """
    Usa la MEDIANA (no el promedio) de la cuota entre casas por
    resultado y le quita el margen (overround) proporcionalmente,
    dejando una probabilidad "justa" de mercado. Metodo de devig
    multiplicativo sobre mediana.

    CORRECCION 2026-08-29: se cambio de promedio a mediana a proposito.
    Comparar la MEJOR cuota (el maximo) contra un promedio que incluye
    esa misma cuota outlier infla artificialmente el EV calculado (la
    cuota outlier "contamina" su propio punto de referencia y ademas
    el maximo de varias muestras con ruido casi siempre queda por
    encima del promedio, aunque el mercado sea eficiente). La mediana
    es mucho mas robusta a un solo outlier y da una estimacion mas
    honesta de "cuanto piensa el mercado en su conjunto", separada de
    la casa que se esta evaluando como posible valor.
    """
    mediana = {}
    for resultado, precios in tabla_cuotas.items():
        valores = sorted(precios.values())
        n = len(valores)
        if n % 2 == 1:
            mediana[resultado] = valores[n // 2]
        else:
            mediana[resultado] = (valores[n // 2 - 1] + valores[n // 2]) / 2
    implicita = {r: 1 / c for r, c in mediana.items()}
    overround = sum(implicita.values())
    justa = {r: implicita[r] / overround for r in implicita}
    return justa, overround


def mejor_cuota_por_resultado(tabla_cuotas: dict) -> dict:
    mejor = {}
    for resultado, precios in tabla_cuotas.items():
        casa, precio = max(precios.items(), key=lambda kv: kv[1])
        mejor[resultado] = (precio, casa)
    return mejor


def detectar_arbitraje(mejor: dict) -> dict | None:
    """
    Si la suma de 1/mejor_cuota de TODOS los resultados es menor a 1
    (menos el margen de seguridad), hay arbitraje real: apostando en
    proporcion inversa a cada cuota se gana sin importar el resultado.
    """
    suma_inversa = sum(1 / precio for precio, _casa in mejor.values())
    if suma_inversa >= UMBRAL_ARBITRAJE:
        return None
    ganancia_garantizada = (1 / suma_inversa) - 1
    stakes = {
        resultado: round((1 / precio) / suma_inversa, 4)
        for resultado, (precio, _casa) in mejor.items()
    }
    return {
        "ganancia_garantizada_pct": round(ganancia_garantizada * 100, 2),
        "reparto_stake": stakes,
        "cuotas_usadas": {r: v for r, v in mejor.items()},
    }


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


def formatear_hallazgo_valor(partido_nombre: str, liga: str, inicio: str, resultado: str,
                              prob_justa: float, cuota: float, casa: str, ev: float) -> str:
    stake = kelly_fraccionado(prob_justa, cuota)
    return (
        f"📈 <b>Posible valor pre-partido</b>\n"
        f"{partido_nombre} ({liga})\n"
        f"Inicio: {inicio}\n\n"
        f"Resultado: <b>{resultado}</b>\n"
        f"Cuota: {cuota} en {casa}\n"
        f"Probabilidad justa de mercado (devig, no es modelo propio): {prob_justa*100:.1f}%\n"
        f"EV estimado vs. consenso: {ev*100:+.2f}%\n"
        f"Stake sugerido (Kelly 0.10, tope 3%): {stake*100:.2f}% de banca\n\n"
        f"⚠️ Este calculo compara casas entre si, NO usa un modelo "
        f"estadistico propio todavia. Revisar manualmente antes de apostar."
    )


def formatear_hallazgo_arbitraje(partido_nombre: str, liga: str, inicio: str, arb: dict) -> str:
    detalle = "\n".join(
        f"  {resultado}: {cuota} en {casa} -> stake {arb['reparto_stake'][resultado]*100:.1f}%"
        for resultado, (cuota, casa) in arb["cuotas_usadas"].items()
    )
    return (
        f"🟢 <b>Posible arbitraje entre casas</b>\n"
        f"{partido_nombre} ({liga})\n"
        f"Inicio: {inicio}\n\n"
        f"Ganancia garantizada estimada: {arb['ganancia_garantizada_pct']:.2f}%\n"
        f"{detalle}\n\n"
        f"⚠️ Verificar manualmente en cada casa antes de apostar: cuotas "
        f"cambian rapido y algunas casas limitan cuentas que arbitran "
        f"seguido. Revisar tambien limites de apuesta minima/maxima."
    )


# ----------------------------------------------------------------------
# RONDA PRINCIPAL
# ----------------------------------------------------------------------

def ejecutar_ronda() -> None:
    ahora = datetime.now(timezone.utc)
    limite = ahora + timedelta(hours=VENTANA_HORAS)
    hallazgos_valor = []
    hallazgos_arbitraje = []

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

            nombre_partido = f"{partido['home_team']} vs {partido['away_team']}"
            guardar_en_historial(partido["id"], nombre_partido, liga, "pre_partido", tabla)

            justa, overround = cuota_justa_por_devig(tabla)
            mejor = mejor_cuota_por_resultado(tabla)

            arb = detectar_arbitraje(mejor)
            if arb:
                hallazgos_arbitraje.append((nombre_partido, liga, inicio.isoformat(), arb))

            for resultado, (cuota, casa) in mejor.items():
                prob = justa.get(resultado)
                if prob is None:
                    continue
                ev = prob * cuota - 1
                if ev >= UMBRAL_EV_MINIMO:
                    hallazgos_valor.append(
                        (nombre_partido, liga, inicio.isoformat(), resultado, prob, cuota, casa, ev)
                    )

    print(f"[INFO] Hallazgos de valor (EV >= {UMBRAL_EV_MINIMO*100:.0f}%): {len(hallazgos_valor)}")
    print(f"[INFO] Hallazgos de arbitraje: {len(hallazgos_arbitraje)}")

    if not hallazgos_valor and not hallazgos_arbitraje:
        print("[INFO] Ronda completada. No se encontro valor real ni arbitraje esta vez.")
        return

    for nombre, liga, inicio, resultado, prob, cuota, casa, ev in hallazgos_valor:
        msg = formatear_hallazgo_valor(nombre, liga, inicio, resultado, prob, cuota, casa, ev)
        if enviar_telegram(msg):
            print(f"Alerta de valor enviada: {nombre} ({resultado})")

    for nombre, liga, inicio, arb in hallazgos_arbitraje:
        msg = formatear_hallazgo_arbitraje(nombre, liga, inicio, arb)
        if enviar_telegram(msg):
            print(f"Alerta de arbitraje enviada: {nombre}")


if __name__ == "__main__":
    ejecutar_ronda()
