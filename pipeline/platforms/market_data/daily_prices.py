"""Incremental completed-day OHLC refresh without schema changes."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from .price_history import fetch_history, upsert_rows


def refresh(con, tickers: list[str]) -> dict:
    now = datetime.now(ZoneInfo("America/New_York"))
    end = now.date() if now.hour >= 18 else now.date() - timedelta(days=1)
    failed = []
    latest = {}
    for ticker in tickers:
        prior = con.execute("SELECT MAX(day) FROM price_daily WHERE ticker=?", (ticker,)).fetchone()[0]
        start = max(datetime.fromisoformat(prior).date() - timedelta(days=3), end - timedelta(days=400)) if prior else end - timedelta(days=400)
        try:
            rows = [r for r in fetch_history(ticker, start, end) if r[1] <= end.isoformat()]
            if rows:
                upsert_rows(con, rows)
                con.commit()
            last = con.execute("SELECT MAX(day) FROM price_daily WHERE ticker=?", (ticker,)).fetchone()[0]
            if not last or last < (end - timedelta(days=7)).isoformat():
                failed.append(ticker)
            latest[ticker] = last
        except Exception:
            failed.append(ticker)
        print(f"[daily-prices] {ticker} {latest.get(ticker, 'failed')}", flush=True)
    if failed:
        raise RuntimeError(f"Stale/missing price data, publication blocked: {failed}")
    return {"tickers": len(tickers), "through": min(latest.values())}
