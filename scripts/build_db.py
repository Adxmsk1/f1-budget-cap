# raw csvs -> f1.duckdb, then applies sql/01_schema.sql. re-run if the raw data changes

from pathlib import Path

import duckdb

DB_PATH = Path("f1.duckdb")
SCHEMA_SQL = Path("sql/01_schema.sql")
RAW_TABLES = ["results", "qualifying", "pitstops", "driver_standings", "constructor_standings"]


def main():
    con = duckdb.connect(str(DB_PATH))
    for t in RAW_TABLES:
        con.execute(f"create or replace table {t} as select * from read_csv('data/raw/{t}.csv', header = true)")
    con.execute(SCHEMA_SQL.read_text())

    views = ["dim_season", "qualifying_clean", "fact_results",
              "constructor_season_share", "constructor_hhi_by_season"]
    for t in RAW_TABLES + views:
        n = con.execute(f"select count(*) from {t}").fetchone()[0]
        print(f"{t}: {n:,} rows")
    con.close()
    print(f"Wrote {DB_PATH}")


if __name__ == "__main__":
    main()
