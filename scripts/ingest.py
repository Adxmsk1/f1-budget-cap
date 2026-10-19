# results, qualifying, pit stops and standings for 2014-2026 from the jolpica api (ergast's replacement)
# -> data/raw. cap came in for 2021 so 2014-20 is 'before', 2021-26 'after'.
# api pages are max 100 rows whatever limit you ask for, so keep paging until we have 'total'

import time
from pathlib import Path

import pandas as pd
import requests

def parse_duration(raw: str) -> float | None:
    # mostly plain seconds, but a few are M:SS.sss (2016 australia) and a couple are blank -> null
    if not raw:
        return None
    parts = raw.split(":")
    seconds = float(parts[-1])
    for i, p in enumerate(reversed(parts[:-1])):
        seconds += float(p) * (60 ** (i + 1))
    return seconds


API = "https://api.jolpi.ca/ergast/f1"
HEADERS = {"User-Agent": "Mozilla/5.0 (portfolio data project)"}
OUT_DIR = Path("data/raw")
SEASONS = range(2014, 2027)
PAGE_SIZE = 100


def get(path: str, **params) -> dict:
    for attempt in range(6):
        resp = requests.get(f"{API}/{path}", params=params, headers=HEADERS, timeout=30)
        if resp.status_code == 429:
            wait = int(resp.headers.get("Retry-After", 2 * (attempt + 1)))
            time.sleep(wait)
            continue
        resp.raise_for_status()
        return resp.json()["MRData"]
    resp.raise_for_status()


RACE_ITEM_KEYS = ("Results", "QualifyingResults", "PitStops")


def fetch_races(season: int, table_key: str, race_key: str) -> list[dict]:
    # one season of an endpoint, one row per race item. a race can be split across two pages so merge, don't overwrite
    offset = 0
    races_seen = {}
    while True:
        data = get(f"{season}/{race_key}.json", limit=PAGE_SIZE, offset=offset)
        total = int(data["total"])
        for race in data[table_key]["Races"]:
            key = (race["season"], race["round"])
            if key not in races_seen:
                races_seen[key] = race
            else:
                for item_key in RACE_ITEM_KEYS:
                    if item_key in race:
                        races_seen[key].setdefault(item_key, []).extend(race[item_key])
        offset += PAGE_SIZE
        if offset >= total or not data[table_key]["Races"]:
            break
        time.sleep(0.4)
    return list(races_seen.values())


def results_rows(races: list[dict]) -> list[dict]:
    rows = []
    for race in races:
        for r in race.get("Results", []):
            rows.append({
                "season": int(race["season"]), "round": int(race["round"]),
                "race_name": race["raceName"], "circuit_id": race["Circuit"]["circuitId"],
                "date": race["date"],
                "driver_id": r["Driver"]["driverId"], "driver_code": r["Driver"].get("code"),
                "driver_name": f"{r['Driver']['givenName']} {r['Driver']['familyName']}",
                "constructor_id": r["Constructor"]["constructorId"],
                "constructor_name": r["Constructor"]["name"],
                "grid": int(r["grid"]), "position": r.get("position"),
                "position_order": int(r["positionText"]) if r["positionText"].isdigit() else None,
                "points": float(r["points"]), "status": r["status"],
                "fastest_lap_rank": r.get("FastestLap", {}).get("rank"),
                "fastest_lap_time": r.get("FastestLap", {}).get("Time", {}).get("time"),
            })
    return rows


def qualifying_rows(races: list[dict]) -> list[dict]:
    rows = []
    for race in races:
        for q in race.get("QualifyingResults", []):
            rows.append({
                "season": int(race["season"]), "round": int(race["round"]),
                "race_name": race["raceName"],
                "driver_id": q["Driver"]["driverId"],
                "constructor_id": q["Constructor"]["constructorId"],
                "position": int(q["position"]),
                "q1": q.get("Q1"), "q2": q.get("Q2"), "q3": q.get("Q3"),
            })
    return rows


def fetch_pitstops_for_round(season: int, round_: int, race_name: str) -> list[dict]:
    # /pitstops won't do a whole season, has to be one round at a time
    offset = 0
    rows = []
    while True:
        try:
            data = get(f"{season}/{round_}/pitstops.json", limit=PAGE_SIZE, offset=offset)
        except requests.exceptions.HTTPError as e:
            if e.response is not None and e.response.status_code == 400:
                break  # no pit stop data for this round
            raise  # a persistent rate limit or server error - don't silently drop data
        races = data["RaceTable"]["Races"]
        if not races:
            break
        for p in races[0].get("PitStops", []):
            rows.append({
                "season": season, "round": round_, "race_name": race_name,
                "driver_id": p["driverId"], "lap": int(p["lap"]), "stop": int(p["stop"]),
                "duration_sec": parse_duration(p["duration"]),
            })
        offset += PAGE_SIZE
        if offset >= int(data["total"]):
            break
        time.sleep(0.4)
    return rows


def fetch_standings(season: int, kind: str) -> list[dict]:
    data = get(f"{season}/{kind}.json")
    lists = data["StandingsTable"]["StandingsLists"]
    if not lists:
        return []
    key = "DriverStandings" if kind == "driverStandings" else "ConstructorStandings"
    rows = []
    for s in lists[0][key]:
        # one-off stand-ins (Lotterer at Spa 2014, Button at Monaco 2017) have no position, just '-'
        row = {"season": season, "position": int(s["position"]) if "position" in s else None,
               "points": float(s["points"]), "wins": int(s["wins"])}
        if kind == "driverStandings":
            row["driver_id"] = s["Driver"]["driverId"]
            row["constructor_id"] = s["Constructors"][0]["constructorId"] if s["Constructors"] else None
        else:
            row["constructor_id"] = s["Constructor"]["constructorId"]
            row["constructor_name"] = s["Constructor"]["name"]
        rows.append(row)
    return rows


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    all_results, all_qualifying, all_pitstops = [], [], []
    all_driver_standings, all_constructor_standings = [], []

    for season in SEASONS:
        print(f"season {season}...")
        races = fetch_races(season, "RaceTable", "results")
        res = results_rows(races)
        all_results += res
        print(f"  results: {len(res)}")
        time.sleep(0.4)

        qual_races = fetch_races(season, "RaceTable", "qualifying")
        qual = qualifying_rows(qual_races)
        all_qualifying += qual
        print(f"  qualifying: {len(qual)}")
        time.sleep(0.4)

        pits = []
        for race in sorted(races, key=lambda r: int(r["round"])):
            pits += fetch_pitstops_for_round(season, int(race["round"]), race["raceName"])
            time.sleep(0.4)
        all_pitstops += pits
        print(f"  pit stops: {len(pits)}")

        all_driver_standings += fetch_standings(season, "driverStandings")
        all_constructor_standings += fetch_standings(season, "constructorStandings")
        time.sleep(0.4)

    pd.DataFrame(all_results).to_csv(OUT_DIR / "results.csv", index=False)
    pd.DataFrame(all_qualifying).to_csv(OUT_DIR / "qualifying.csv", index=False)
    pd.DataFrame(all_pitstops).to_csv(OUT_DIR / "pitstops.csv", index=False)
    pd.DataFrame(all_driver_standings).to_csv(OUT_DIR / "driver_standings.csv", index=False)
    pd.DataFrame(all_constructor_standings).to_csv(OUT_DIR / "constructor_standings.csv", index=False)

    print(f"\nresults: {len(all_results):,}")
    print(f"qualifying: {len(all_qualifying):,}")
    print(f"pit stops: {len(all_pitstops):,}")
    print(f"driver standings rows: {len(all_driver_standings):,}")
    print(f"constructor standings rows: {len(all_constructor_standings):,}")


if __name__ == "__main__":
    main()
