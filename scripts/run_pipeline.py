# runs the whole thing in order: (ingest) -> build_db -> check_data -> export_processed
# ingest is skipped by default because the raw csvs are in the repo and the api is slow to page through.
#   python scripts/run_pipeline.py            rebuild from data/raw
#   python scripts/run_pipeline.py --ingest   pull fresh data from the api first

import subprocess
import sys

STEPS = ["build_db", "check_data", "export_processed"]


def main():
    steps = (["ingest"] if "--ingest" in sys.argv else []) + STEPS
    for step in steps:
        print(f"\n--- {step} ---", flush=True)
        result = subprocess.run([sys.executable, f"scripts/{step}.py"])
        if result.returncode != 0:
            print(f"\nstopped at {step}")
            sys.exit(result.returncode)
    print("\ndone - data/processed is up to date")


if __name__ == "__main__":
    main()
