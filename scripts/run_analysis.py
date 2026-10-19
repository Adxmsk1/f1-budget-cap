# runs each named query in sql/02_analysis.sql (split on '-- @name:') and prints the results

import re
from pathlib import Path

import duckdb
import pandas as pd

DB_PATH = Path("f1.duckdb")
ANALYSIS_SQL = Path("sql/02_analysis.sql")


def load_queries() -> dict[str, str]:
    text = ANALYSIS_SQL.read_text()
    chunks = re.split(r"--\s*@name:\s*(\w+)", text)[1:]
    names = chunks[0::2]
    bodies = chunks[1::2]
    return {name: body.strip() for name, body in zip(names, bodies)}


def run_all() -> dict[str, pd.DataFrame]:
    con = duckdb.connect(str(DB_PATH), read_only=True)
    results = {name: con.execute(sql).df() for name, sql in load_queries().items()}
    con.close()
    return results


if __name__ == "__main__":
    for name, df in run_all().items():
        print(f"\n=== {name} ({len(df)} rows) ===")
        print(df.to_string(index=False))
