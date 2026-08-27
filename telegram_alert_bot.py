"""
Bot de Alertas en Vivo — Superagente Quant MAXYURSPORTS
=========================================================
Revisa las cuotas en vivo de los partidos permitidos (mismo alcance de
ligas ya definido: Premier League, La Liga, Serie A, Bundesliga, Ligue 1,
Champions/Europa/Conference, Liga BetPlay, Brasileirão, Argentina, Chile,
Uruguay, Liga MX, MLS) y, cuando detecta que el favorito va perdiendo o
empatando, calcula la cobertura exacta con hedge_calculator.py y manda
la alerta lista a Telegram.

Pensado para correr solo, sin supervisión, cada N minutos vía GitHub
Actions (ver .github/workflows/monitor_partidos.yml) — gratis, sin
depender de que tu computador esté prendido ni de esta conversación.

CREDENCIALES: nunca van escritas aquí. Se leen de variables de entorno
(en GitHub Actions se configuran como "Secrets", nunca quedan visibles
en el código ni en el repositorio).

Variables de entorno requeridas:
    TELEGRAM_BOT_TOKEN   -> el token que te da @BotFather
    TELEGRAM_CHAT_ID     -> tu chat id (te lo doy el paso a paso en el README)
    ODDS_API_KEY         -> tu llave gratuita de odds-api.io (o el proveedor que uses)

Este archivo es un ESQUELETO funcional: la conexión a Telegram y el
cálculo de cobertura ya están completos y probados. La función
`obtener_partidos_en_vivo()` trae un ejemplo de integración con
odds-api.io que debes ajustar según el proveedor de datos que
finalmente elijamos (dejo comentarios donde hay que adaptar).
"""

import os
import sys
import requests

from hedge_calculator import analizar_cobertura

# ---------------------------------------------------------------------
# CONFIGURACIÓN
# ---------------------------------------------------------------------

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
ODDS_API_KEY = os.environ.get("ODDS_API_KEY", "")

# Mismo alcance de ligas ya acordado — NUNCA "todas las ligas del mundo".
# Ajusta estos códigos al formato exacto que use el proveedor de cuotas.
LIGAS_PERMITIDAS = [
    "soccer_epl",              # Premier League
    "soccer_spain_la_liga",    # La Liga
    "soccer_italy_serie_a",    # Serie A
    "soccer_germany_bundesliga",
    "soccer_france_ligue_one",
    "soccer_uefa_champs_league",
    "soccer_uefa_europa_league",
    "soccer_uefa_europa_conference_league",
    "soccer_colombia_primera_a",
    "soccer_brazil_campeonato",
    "soccer_argentina_primera_division",
    "soccer_chile_primera_division",
    "soccer_usa_mls",
    "soccer_mexico_ligamx",
    # Uruguay: agregar el código exacto cuando confirmemos que el
    # proveedor de datos lo cubre.
]

# Umbral: cuánto tiene que subir la cuota del "no favorito" para que
# consideremos que vale la pena avisar (evita spam de alertas por
# movimientos insignificantes).
UMBRAL_CUOTA_MINIMA_ALERTA = 3.0


# ---------------------------------------------------------------------
# TELEGRAM
# ---------------------------------------------------------------------

def enviar_alerta_telegram(mensaje: str) -> bool:
    """Envía un mensaje al chat de Telegram configurado. Devuelve True/False."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        print("[ERROR] Falta TELEGRAM_BOT_TOKEN o TELEGRAM_CHAT_ID en el entorno.")
        return False

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    resp = requests.post(
        url,
        data={
            "chat_id": TELEGRAM_CHAT_ID,
            "text": mensaje,
            "parse_mode": "HTML",
        },
        timeout=15,
    )
    if resp.status_code != 200:
        print(f"[ERROR] Telegram respondió {resp.status_code}: {resp.text}")
        return False
    return True


# ---------------------------------------------------------------------
# DATOS EN VIVO (ADAPTAR AL PROVEEDOR ELEGIDO)
# ---------------------------------------------------------------------

def obtener_partidos_en_vivo():
    """
    Ejemplo de integración con odds-api.io (plan gratuito: 100
    consultas/hora, 500/día, cuotas en vivo + pre-partido).

    Devuelve una lista de diccionarios, uno por partido en vivo dentro
    del alcance de ligas permitidas, con al menos:
        {
            "partido": "Equipo A vs Equipo B",
            "liga": "soccer_epl",
            "minuto": 62,
            "marcador": "1-0",
            "favorito_va_perdiendo_o_empatando": True/False,
            "cuota_original_favorito": 1.45,
            "cuota_en_vivo_contraria": 4.20,   # empate o rival, la que aplique
        }

    IMPORTANTE: este cuerpo es un EJEMPLO — el endpoint y los campos
    exactos hay que ajustarlos una vez elijamos el proveedor final y
    confirmemos qué casas de apuestas cubre el plan gratuito.
    """
    if not ODDS_API_KEY:
        print("[ERROR] Falta ODDS_API_KEY en el entorno.")
        return []

    partidos_detectados = []

    # --- EJEMPLO de llamada (ajustar a la doc real del proveedor) ---
    # resp = requests.get(
    #     "https://api.odds-api.io/v3/odds/live",
    #     params={"apiKey": ODDS_API_KEY, "sport": "soccer", "regions": "eu"},
    #     timeout=20,
    # )
    # data = resp.json()
    # for partido in data:
    #     if partido["league_code"] not in LIGAS_PERMITIDAS:
    #         continue
    #     ... lógica para detectar favorito abajo/empatando y
    #     armar el diccionario de arriba ...

    return partidos_detectados


# ---------------------------------------------------------------------
# LÓGICA PRINCIPAL
# ---------------------------------------------------------------------

def formatear_alerta(partido: dict) -> str:
    cobertura = analizar_cobertura(
        stake_original=1.0,  # referencia por unidad de banca; el usuario escala
        cuota_original=partido["cuota_original_favorito"],
        cuota_cobertura=partido["cuota_en_vivo_contraria"],
    )
    return (
        f"⚠️ <b>Repricing detectado</b>\n"
        f"{partido['partido']} ({partido['liga']})\n"
        f"Minuto {partido['minuto']} — Marcador {partido['marcador']}\n\n"
        f"Cuota contraria en vivo: {partido['cuota_en_vivo_contraria']:.2f}\n\n"
        f"Por cada 1 unidad apostada originalmente:\n"
        f"• Cobertura ganancia igual: {cobertura.stake_cobertura_ganancia_igual:.2f} u. "
        f"→ ganancia garantizada {cobertura.ganancia_garantizada:.2f} u.\n"
        f"• Cobertura solo recuperar: {cobertura.stake_cobertura_solo_recuperar:.2f} u.\n\n"
        f"Recuerda: esto NO confirma valor por sí solo — confírmalo conmigo "
        f"antes de apostar si quieres el análisis de probabilidad real."
    )


def ejecutar_ronda():
    partidos = obtener_partidos_en_vivo()
    if not partidos:
        print("Sin partidos con repricing relevante en esta ronda.")
        return

    for partido in partidos:
        if not partido.get("favorito_va_perdiendo_o_empatando"):
            continue
        if partido["cuota_en_vivo_contraria"] < UMBRAL_CUOTA_MINIMA_ALERTA:
            continue
        mensaje = formatear_alerta(partido)
        enviado = enviar_alerta_telegram(mensaje)
        print(f"Alerta {'enviada' if enviado else 'FALLÓ'}: {partido['partido']}")


if __name__ == "__main__":
    ejecutar_ronda()
