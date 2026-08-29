import os
import requests

ODDS_API_KEY = os.environ.get("ODDS_API_KEY", "")
resp = requests.get("https://api.the-odds-api.com/v4/sports", params={"apiKey": ODDS_API_KEY, "all": "true"}, timeout=20)
resp.raise_for_status()
sports = resp.json()
soccer = [s for s in sports if s["key"].startswith("soccer_")]
print(f"Total soccer leagues: {len(soccer)}")
for s in soccer:
    print(f"{s['key']} | {s['title']} | active={s['active']}")
