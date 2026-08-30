"""
Bot de Valor Pre-Partido -- Superagente Quant MAXYURSPORTS
============================================================
Segundo proceso permanente del sistema (distinto del bot de cobertura
en vivo de telegram_alert_bot.py). Este corre ANTES de que empiecen los
partidos y busca apuestas de valor EJECUTABLES EN 1XBET, que es la
unica casa que usa el usuario.

AJUSTE 2026-08-29 (rediseno completo tras confirmar que el usuario solo
opera en 1xBet):
  - Se elimina por completo la deteccion de arbitraje entre casas: el
    arbitraje solo funciona si se puede apostar en varias casas al
    mismo tiempo, y aqui no aplica.
  - "Mejor cuota entre casas" ya no tiene sentido: ahora se usa
    EXCLUSIVAMENTE la cuota que ofrece 1xBet. Si 1xBet no cubre un
    partido, se salta sin mas analisis.
  - La probabilidad "justa" de referencia se calcula con las OTRAS
    casas (mediana, sin incluir a 1xBet) -- esto es un leave-one-out
    real: la cuota que se esta evaluando (la de 1xBet) nunca contamina
    su propio punto de comparacion. Es la correccion tecnica correcta
    que ya habiamos identificado como pendiente en el CHANGELOG.
  - Se redujo la consulta de regiones de la API de "eu,uk,us" a solo
    "eu" (donde aparece 1xBet) -- esto reduce el consumo de creditos
    de The Odds API, ya que no tiene sentido pagar por datos de
    regiones/casas que el usuario nunca va a usar.

METODO: sigue siendo comparacion contra consenso de mercado (devig),
NO un modelo estadistico propio (ver elo_model.py para eso). Esta
version es mas estricta que la anterior porque el punto de referencia
(las otras casas) nunca incluye la cuota que se esta evaluando.

LIMITACION HONESTA: si muy pocas casas ademas de 1xBet cubren un
partido (por ejemplo solo 1 o 2), la "mediana" de referencia es poco
confiable estadisticamente. El bot exige un minimo de 3 casas de
referencia (ademas de 1xBet) antes de evaluar un partido -- ver
MINIMO_CASAS_REFERENCIA.

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

# Mismas 25 ligas que ya usa el bot de cobertura en vivo.
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

# Umbral minimo de EV (cuota de 1xBet vs. mediana de las OTRAS casas)
# para considerar que algo es una posible senal de valor. Se mantiene
# en 5% (conservador) porque, aunque el metodo leave-one-out corrige
# el sesgo de seleccion mas grave, sigue siendo comparacion entre
# casas y no un modelo propio -- ver limitacion honesta al inicio.
UMBRAL_EV_MINIMO = 0.05

# Minimo de casas de REFERENCIA (sin contar a 1xBet) necesarias para
# calcular una mediana medianamente confiable. Menos que esto y el
# partido se salta -- no vale la pena evaluar valor contra 1 o 2
# casas de referencia.
#
# AJUSTE 2026-08-29 (post-corrida real #3): con MINIMO_CASAS_REFERENCIA=3
# la primera corrida real encontro 6 "hallazgos" de valor, los 6 en el
# mismo mercado (Empate) y la misma liga (MLS) -- un patron sospechoso
# de sesgo por poca muestra, no de valor real (ver CHANGELOG.md). MLS
# tiene menos casas cotizando que las ligas europeas grandes, asi que
# con solo 3 casas de referencia la mediana tiene mucha varianza,
# especialmente en el mercado de empate (menos liquido). Se sube el
# minimo a 5 para exigir una mediana mas estable antes de confiar en
# una senal.
MINIMO_CASAS_REFERENCIA = 5

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
# ANALISIS: cuota de 1xBet vs. mediana de las OTRAS casas (leave-one-out)
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


def cuota_justa_leave_one_out(tabla_cuotas: dict) -> tuple[dict, int]:
    """
    Calcula la probabilidad "justa" de referencia usando la MEDIANA de
    todas las casas EXCEPTO 1xBet (leave-one-out real: la cuota que
    estamos evaluando nunca entra en su propio punto de comparacion).

    Devuelve (justa, num_casas_referencia_minimo_entre_resultados).
    """
    medianas = {}
    minimo_casas = None
    for resultado, precios in tabla_cuotas.items():
        otras = [precio for casa, precio in precios.items() if casa != CASA_UNICA]
        n = len(otras)
        minimo_casas = n if minimo_casas is None else min(minimo_casas, n)
        if n == 0:
            continue
        otras.sort()
        if n % 2 == 1:
            medianas[resultado] = otras[n // 2]
        else:
            medianas[resultado] = (otras[n // 2 - 1] + otras[n // 2]) / 2

    if not medianas:
        return {}, (minimo_casas or 0)

    implicita = {r: 1 / c for r, c in medianas.items()}
    overround = sum(implicita.values())
    justa = {r: implicita[r] / overround for r in implicita}
    return justa, (minimo_casas or 0)


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
                              prob_justa: float, cuota_1xbet: float, num_casas_ref: int, ev: float) -> str:
    stake = kelly_fraccionado(prob_justa, cuota_1xbet)
    return (
        f"ð <b>Posible valor en 1xBet</b>\n"
        f"{partido_nombre} ({liga})\n"
        f"Inicio: {inicio}\n\n"
        f"Resultado: <b>{resultado}</b>\n"
        f"Cuota en 1xBet: {cuota_1xbet}\n"
        f"Probabilidad justa (mediana de {num_casas_ref} otras casas, sin incluir 1xBet): {prob_justa*100:.1f}%\n"
        f"EV estimado: {ev*100:+.2f}%\n"
        f"Stake sugerido (Kelly 0.10, tope 3%): {stake*100:.2f}% de banca\n\n"
        f"â ï¸ Esto compara la cuota de 1xBet contra el resto del mercado, "
        f"NO usa un modelo estadistico propio todavia. Verifica el precio "
        f"actual en la app de 1xBet antes de apostar -- las cuotas cambian rapido."
    )


# ----------------------------------------------------------------------
# RONDA PRINCIPAL
# ----------------------------------------------------------------------

def ejecutar_ronda() -> None:
    ahora = datetime.now(timezone.utc)
    limite = ahora + timedelta(hours=VENTANA_HORAS)
    hallazgos_valor = []
    partidos_sin_1xbet = 0
    partidos_sin_referencia_suficiente = 0

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

            justa, num_casas_ref = cuota_justa_leave_one_out(tabla)
            if num_casas_ref < MINIMO_CASAS_REFERENCIA:
                partidos_sin_referencia_suficiente += 1
                continue

            for resultado, cuota in propias.items():
                prob = justa.get(resultado)
                if prob is None:
                    continue
                ev = prob * cuota - 1
                if ev >= UMBRAL_EV_MINIMO:
                    # Log detallado por hallazgo -- para poder auditar despues
                    # si un patron (misma liga, mismo mercado) se repite, que
                    # es la senal de alerta de sesgo por poca muestra que ya
                    # vimos en la corrida real del 2026-08-29 (6 hallazgos,
                    # todos Empate en MLS, con MINIMO_CASAS_REFERENCIA=3).
                    print(
                        f"[DETALLE] {nombre_partido} ({liga}) | resultado={resultado} | "
                        f"cuota_1xbet={cuota} | prob_justa={prob*100:.1f}% | "
                        f"num_casas_ref={num_casas_ref} | ev={ev*100:+.2f}%"
                    )
                    hallazgos_valor.append(
                        (nombre_partido, liga, inicio.isoformat(), resultado, prob, cuota, num_casas_ref, ev)
                    )

    print(f"[INFO] Hallazgos de valor en 1xBet (EV >= {UMBRAL_EV_MINIMO*100:.0f}%): {len(hallazgos_valor)}")
    print(f"[INFO] Partidos saltados por no estar en 1xBet: {partidos_sin_1xbet}")
    print(f"[INFO] Partidos saltados por pocas casas de referencia (<{MINIMO_CASAS_REFERENCIA}): {partidos_sin_referencia_suficiente}")

    if not hallazgos_valor:
        print("[INFO] Ronda completada. No se encontro valor real en 1xBet esta vez.")
        return

    for nombre, liga, inicio, resultado, prob, cuota, num_casas_ref, ev in hallazgos_valor:
        msg = formatear_hallazgo_valor(nombre, liga, inicio, resultado, prob, cuota, num_casas_ref, ev)
        if enviar_telegram(msg):
            print(f"Alerta de valor enviada: {nombre} ({resultado})")


if __name__ == "__main__":
    ejecutar_ronda()
