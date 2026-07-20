import datetime as dt

from sqlalchemy import create_engine, func, select

from pipeline.common.models import XueqiuPostTicker
from pipeline.platforms.xueqiu import pipeline as xueqiu_pipeline


def test_sqlite_bulk_upsert_chunks_large_mapping_batch(monkeypatch) -> None:
    engine = create_engine("sqlite://")
    XueqiuPostTicker.__table__.create(engine)
    monkeypatch.setattr(xueqiu_pipeline, "engine", engine)
    now = dt.datetime(2026, 7, 17)
    rows = [
        {
            "native_id": str(index),
            "ticker": "NVDA",
            "role": "mentioned",
            "confidence": 0.65,
            "created_utc": now,
            "updated_at": now,
        }
        for index in range(2_000)
    ]

    inserted = xueqiu_pipeline._bulk_upsert(
        XueqiuPostTicker,
        rows,
        ["native_id", "ticker"],
    )

    assert inserted == len(rows)
    with engine.connect() as connection:
        assert connection.scalar(select(func.count()).select_from(XueqiuPostTicker)) == len(rows)
