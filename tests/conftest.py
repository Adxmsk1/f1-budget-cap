import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))


@pytest.fixture(autouse=True)
def run_from_repo_root(monkeypatch):
    # the scripts use paths relative to the repo root, same as when you run them by hand
    monkeypatch.chdir(ROOT)
