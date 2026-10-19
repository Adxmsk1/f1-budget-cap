# star schema out of f1.duckdb into data/processed - the csvs power bi loads

from pathlib import Path

import duckdb

DB_PATH = Path("f1.duckdb")
OUT_DIR = Path("data/processed")


def main():
    con = duckdb.connect(str(DB_PATH), read_only=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    con.execute("select * from dim_season").df().to_csv(OUT_DIR / "dim_season.csv", index=False)

    con.execute("""
        select distinct driver_id, driver_code, driver_name
        from results where driver_id is not null
    """).df().to_csv(OUT_DIR / "dim_driver.csv", index=False)

    con.execute("""
        select distinct constructor_id, constructor_name from results
    """).df().to_csv(OUT_DIR / "dim_constructor.csv", index=False)

    con.execute("""
        select distinct season, round, race_name, circuit_id, date
        from results order by season, round
    """).df().to_csv(OUT_DIR / "dim_race.csv", index=False)

    con.execute("""
        select season, round, driver_id, constructor_id, grid, position_order,
               points, status, places_gained, fastest_lap_time as fastest_lap_text,
               is_post_cap
        from fact_results
    """).df().to_csv(OUT_DIR / "fact_results.csv", index=False)

    con.execute("""
        select season, round, driver_id, constructor_id, position,
               q1_sec, q2_sec, q3_sec, best_sec
        from qualifying_clean
    """).df().to_csv(OUT_DIR / "fact_qualifying.csv", index=False)

    con.execute("""
        select p.season, p.round, p.driver_id, r.constructor_id, p.lap, p.stop, p.duration_sec
        from pitstops p
        join results r using (season, round, driver_id)
    """).df().to_csv(OUT_DIR / "fact_pitstops.csv", index=False)

    con.execute("""
        select season, constructor_id, constructor_name, position, points, wins
        from constructor_standings
    """).df().to_csv(OUT_DIR / "fact_constructor_standings.csv", index=False)

    con.execute("""
        select season, driver_id, constructor_id, position, points, wins
        from driver_standings
    """).df().to_csv(OUT_DIR / "fact_driver_standings.csv", index=False)

    for f in sorted(OUT_DIR.glob("*.csv")):
        import pandas as pd
        n = len(pd.read_csv(f))
        print(f"{f.name}: {n:,} rows")

    con.close()


if __name__ == "__main__":
    main()
