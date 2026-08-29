"""
Script temporal: consulta cuotas reales (h2h) de las ligas relevantes y
filtra los partidos que empiezan en las proximas horas, para analisis
manual de valor pre-partido. No modifica el bot principal. Se borra
despues de usarse.
"""
import os
from datetime import datetime, timezone, timedelta
import requests

ODDS_API_KEY = os.environ.get("ODDS_API_KEY", "")
BASE = "https://api.the-odds-api.com/v4"

LIGAS = [
    "soccer_brazil_campeonato",
    "soccer_argentina_primera_division",
    "soccer_mexico_ligamx",
    "soccer_usa_mls",
]

ahora = datetime.now(timezone.utc)
limite = ahora + timedelta(hours=4)

print(f"Hora actual UTC: {ahora.isoformat()}")
print(f"Ventana hasta: {limite.isoformat()}")
print("=" * 70)

for liga in LIGAS:
    url = f"{BASE}/sports/{liga}/odds/"
    try:
        resp = requests.get(
            url,
            params={
                "apiKey": ODDS_API_KEY,
                "regions": "us,eu",
                "markets": "h2h",
                "oddsFormat": "decimal",
            },
            timeout=20,
        )
        resp.raise_for_status()
    except Exception as e:
        print(f"[ERROR] {liga}: {e}")
        continue

    restantes = resp.headers.get("x-requests-remaining", "?")
    partidos = resp.json()
    print(f"\n--- {liga} ({len(partidos)} partidos totales, creditos restantes: {restantes}) ---")

    for p in partidos:
        inicio = datetime.fromisoformat(p["commence_time"].replace("Z", "+00:00"))
        if not (ahora <= inicio <= limite):
            continue
        print(f"\n{p['home_team']} vs {p['away_team']}  |  inicio: {inicio.isoformat()}")
        for bk in p.get("bookmakers", [])[:5]:
            for mk in bk.get("markets", []):
                if mk.get("key") != "h2h":
                    continue
                cuotas = ", ".join(f"{o['name']}={o['price']}" for o in mk.get("outcomes", []))
                print(f"  {bk['title']}: {cuotas}")

print("\n" + "=" * 70)
print("FIN")
