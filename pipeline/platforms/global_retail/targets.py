"""Global retail platform ticker universe helpers."""
from __future__ import annotations

import yaml

from ...common.config import PKG_DATA_DIR


def load_targets() -> list[dict]:
    with open(PKG_DATA_DIR / "global_targets.yml", "r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)["tickers"]
