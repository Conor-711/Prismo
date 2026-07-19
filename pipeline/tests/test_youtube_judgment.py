import importlib
from pathlib import Path

from pipeline.common.config import RUNTIME_DATA_DIR
from pipeline.domain.target_prices import youtube_judgment


def test_default_database_is_runtime_database(monkeypatch):
    monkeypatch.delenv("PRICE_DB", raising=False)
    module = importlib.reload(youtube_judgment)

    assert Path(module.DB).resolve() == (RUNTIME_DATA_DIR / "dev.db").resolve()
