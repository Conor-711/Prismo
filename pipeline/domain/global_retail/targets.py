"""Global retail ticker universe and storage helpers."""
from __future__ import annotations

import yaml

from ...common.config import PKG_DATA_DIR
from ...common.models import Base, GrPost


def load_targets() -> list[dict]:
    with open(PKG_DATA_DIR / "global_targets.yml", "r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)["tickers"]


def ensure_tables() -> None:
    from ...common.db import engine

    Base.metadata.create_all(
        engine,
        tables=[
            GrPost.__table__,
            Base.metadata.tables["gr_ticker_region"],
            Base.metadata.tables["gr_ticker"],
        ],
    )
