# Data dictionary - F1 budget cap

From the [Jolpica F1 API](https://api.jolpi.ca/ergast/f1) (the replacement for the old Ergast API). Every season
2014-2026.

## dim_season.csv
| Column | Type | Notes |
|---|---|---|
| season | int | |
| is_post_cap | bool | true from 2021 |
| cap_usd_m | float | cost cap that season, $m: 145 (2021), 140 (2022), 135 (2023 on). Blank before 2021 |
| num_races | int | rounds that season (17 in 2020 because of COVID; 17 so far in 2026) |

## dim_driver.csv / dim_constructor.csv / dim_race.csv
Lookups: driver code and name, team name, and race name/circuit/date for each round.

## fact_results.csv
One row per driver per race, classified finishers only (DNS/DNQ have no finishing position to compare).

| Column | Type | Notes |
|---|---|---|
| season, round | int | |
| driver_id, constructor_id | text | keys |
| grid | int | starting position |
| position_order | int | finishing position |
| points | float | |
| status | text | Finished, +1 Lap, Engine, Collision, etc. |
| places_gained | int | grid - position_order, so positive = finished higher than they started |
| fastest_lap_text | text | raw M:SS.sss, not used in the analysis |
| is_post_cap | bool | |

## fact_qualifying.csv
One row per driver per qualifying session.

| Column | Type | Notes |
|---|---|---|
| season, round, driver_id, constructor_id | | |
| position | int | qualifying position |
| q1_sec, q2_sec, q3_sec | float | lap time in seconds, parsed from M:SS.sss. Blank if they didn't set a time in that part |
| best_sec | float | best of the three |

## fact_pitstops.csv
One row per stop.

| Column | Type | Notes |
|---|---|---|
| season, round, driver_id, constructor_id | | |
| lap, stop | int | lap number, and which stop it was for that driver |
| duration_sec | float | a few (e.g. 2016 Australian GP) come through as M:SS.sss and get converted. Two (Kvyat round 7 and Vettel round 12, both 2016) have no time in the source and are left blank |

Stops of 60 seconds or more are left out of the pit crew comparison (but kept in this file) - at that length it's a
penalty or a repair, not a tyre change.

## fact_constructor_standings.csv / fact_driver_standings.csv
Final standings each season. A few one-off stand-in drivers (André Lotterer at Spa 2014, Jenson Button at Monaco
2017) have no position in the source, so it's left blank.

## Gaps
- Pit stop data isn't there for every race. Missing races just have no rows.
- 2026 isn't finished (17 rounds so far), so treat it as the season to date.
