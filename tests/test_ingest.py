# the parts of ingest.py that turn api json into rows, tested without calling the api

import ingest


def test_parse_duration_plain_seconds():
    assert ingest.parse_duration("22.613") == 22.613


def test_parse_duration_minutes_and_seconds():
    # 2016 australia comes through like this after the red flag
    assert ingest.parse_duration("1:05.500") == 65.5


def test_parse_duration_blank_is_none():
    assert ingest.parse_duration("") is None


def _result(driver, position_text, points):
    return {
        "Driver": {"driverId": driver, "code": driver[:3].upper(), "givenName": "A", "familyName": driver},
        "Constructor": {"constructorId": "team", "name": "Team"},
        "grid": "3", "position": "1", "positionText": position_text,
        "points": points, "status": "Finished",
    }


def test_results_rows_keeps_retirements_without_a_finishing_position():
    race = {"season": "2023", "round": "5", "raceName": "Miami Grand Prix", "date": "2023-05-07",
            "Circuit": {"circuitId": "miami"},
            "Results": [_result("verstappen", "1", "26"), _result("sargeant", "R", "0")]}

    rows = ingest.results_rows([race])

    assert len(rows) == 2
    assert rows[0]["position_order"] == 1 and rows[0]["points"] == 26.0
    assert rows[1]["position_order"] is None  # 'R' = retired, no classified position
    assert rows[0]["season"] == 2023 and rows[0]["circuit_id"] == "miami"


def test_fetch_races_merges_a_race_split_across_two_pages(monkeypatch):
    # the api caps pages at 100 rows, so one race's results can land on two pages
    race = {"season": "2023", "round": "1", "raceName": "Bahrain Grand Prix"}
    pages = [
        {"total": "3", "RaceTable": {"Races": [{**race, "Results": [{"n": 1}, {"n": 2}]}]}},
        {"total": "3", "RaceTable": {"Races": [{**race, "Results": [{"n": 3}]}]}},
    ]
    calls = iter(pages)
    monkeypatch.setattr(ingest, "get", lambda path, **params: next(calls))
    monkeypatch.setattr(ingest.time, "sleep", lambda s: None)
    monkeypatch.setattr(ingest, "PAGE_SIZE", 2)

    races = ingest.fetch_races(2023, "RaceTable", "results")

    assert len(races) == 1
    assert [r["n"] for r in races[0]["Results"]] == [1, 2, 3]
