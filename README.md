# F1 budget cap

**Did the budget cap make F1 a fair fight?**

In 2021 Formula 1 capped team spending at $145m (down to $135m by 2023). The idea was to stop the richest teams
buying championships - Mercedes had just won seven constructors' titles in a row. This project looks at 13 seasons
(2014-2026) of results, qualifying, pit stops and standings to see whether it worked.

Short answer: partly. Title fights got closer and more teams win races, but the gap between the front and the back of
the grid hasn't really moved.

![Who can win](output/powerbi_exports/03_who_can_win.png)

## Data

All from the [Jolpica F1 API](https://github.com/jolpica/jolpica-f1) (`api.jolpi.ca`), which replaced the old Ergast
API. No key needed. 5,479 race results, 5,458 qualifying entries and 9,870 pit stops.

Column notes and the couple of data problems I had to deal with (some pit stop times come through as `M:SS.sss`
instead of seconds, two have no time at all) are in [`data/processed/data_dictionary.md`](data/processed/data_dictionary.md).

## How it's put together

```
scripts/ingest.py -> data/raw/*.csv -> build_db.py -> f1.duckdb -> sql/*.sql -> data/processed/*.csv -> Power BI
```

- `sql/01_schema.sql` - parses lap and pit stop times, flags each season as before/after the cap, works out each
  team's share of the points for the HHI
- `sql/02_analysis.sql` - the analysis queries (pit stops of 60s+ are left out of the pit crew comparison, they're
  penalties or repairs, not tyre changes)
- `powerbi/` - the Power BI project (PBIP), see [`powerbi/README.md`](powerbi/README.md)

## What I found

More detail in [`output/narrative_report.md`](output/narrative_report.md).

- The average title-winning margin fell from 227 to 199 points, but it swings more. Red Bull's 451-point margin in
  2023 is the most one-sided season of the lot, cap or no cap.
- McLaren went from 9th (2015 and 2017) to back-to-back constructors' champions in 2024 and 2025.
- More teams win races: 2.7 a season before the cap, 3.3 since.
- The back of the grid is as far behind as ever.

## Running it

Needs Python 3.11 or 3.12 (duckdb doesn't have wheels for newer versions yet).

```
pip install pandas requests duckdb matplotlib
python scripts/ingest.py
python scripts/build_db.py
python scripts/run_analysis.py
python scripts/export_processed.py
python scripts/export_chart_previews.py
```
