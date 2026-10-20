# runs each check in sql/03_checks.sql against f1.duckdb. a check passes if its query returns no rows.
# exits with 1 if anything fails, so run_pipeline.py stops before exporting bad data

import re
import sys
from pathlib import Path

import duckdb

DB_PATH = Path("f1.duckdb")
CHECKS_SQL = Path("sql/03_checks.sql")


def load_checks() -> dict[str, str]:
    chunks = re.split(r"--\s*@check:\s*(\w+)", CHECKS_SQL.read_text())[1:]
    return {name: body.strip().rstrip(";") for name, body in zip(chunks[0::2], chunks[1::2])}


def run_checks(con) -> list[str]:
    failed = []
    for name, sql in load_checks().items():
        bad = con.execute(sql).df()
        if bad.empty:
            print(f"  pass  {name}")
        else:
            print(f"  FAIL  {name} ({len(bad)} rows)")
            print(bad.head(10).to_string(index=False))
            failed.append(name)
    return failed


def main():
    con = duckdb.connect(str(DB_PATH), read_only=True)
    failed = run_checks(con)
    con.close()
    if failed:
        print(f"\n{len(failed)} check(s) failed")
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
