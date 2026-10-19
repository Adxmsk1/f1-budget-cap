# Power BI - F1 Budget Cap

`F1 Budget Cap.pbip` is a Power BI project in the text-based PBIP format, so the model (TMDL) and report pages (PBIR
JSON) can be read and diffed in git. It opens straight into Power BI Desktop with the data already loaded.

The report is a cover, six chapters (title fights, who can win, pace, operations, rewards, team stories) and a
closing scorecard. Most pages have season/era slicers, and the commentary is written by DAX measures, so it changes
with the selection.

## Rebuilding

The model comes from `scripts/generate_pbip.py`, and the report pages and extra measures from `build_dashboard.ps1`:

```
python ..\scripts\generate_pbip.py
powershell -ExecutionPolicy Bypass -File build_dashboard.ps1
powershell -ExecutionPolicy Bypass -File ..\scripts\powerbi_tools\save_with_data.ps1 -PowerBiDir . -Name "F1 Budget Cap"
```

The last step opens Power BI Desktop, refreshes and saves, so the project opens with data next time.

Each table loads `data\processed\<table>.csv` from wherever the project folder is. If you move it, re-run
`generate_pbip.py`, or change the source in Power BI under Transform data > Data source settings.

Page images are in `output/powerbi_exports/` (made with `scripts/powerbi_tools/shoot.ps1`).

## Model

| Table | Grain |
|---|---|
| `dim_season` | season, with `is_post_cap` and the cap amount |
| `dim_driver`, `dim_constructor`, `dim_race` | the usual lookups |
| `fact_results` | driver x race |
| `fact_qualifying` | driver x qualifying session |
| `fact_pitstops` | one row per stop |
| `fact_constructor_standings`, `fact_driver_standings` | final standings each season |
