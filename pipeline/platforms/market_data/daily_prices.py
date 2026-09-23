"""Incremental completed-day OHLC refresh without schema changes."""
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from .price_history import fetch_history, upsert_rows


def inactive_tickers(con) -> set[str]:
    """Return securities that no longer require a current trading-day quote."""
    try:
        return {
            str(row[0]).upper()
            for row in con.execute("SELECT ticker FROM ticker_meta WHERE is_active=0")
        }
    except Exception:
        # Isolated price-refresh tests and older databases may not have metadata.
        return set()


def refresh(con, tickers: list[str]) -> dict:
    now = datetime.now(ZoneInfo("America/New_York"))
    end = now.date() if now.hour >= 18 else now.date() - timedelta(days=1)
    failed = []
    latest = {}
    inactive = inactive_tickers(con)
    terminal = []
    for ticker in tickers:
        prior = con.execute("SELECT MAX(day) FROM price_daily WHERE ticker=?", (ticker,)).fetchone()[0]
        if prior and ticker.upper() in inactive:
            latest[ticker] = prior
            terminal.append(ticker)
            print(f"[daily-prices] {ticker} {prior} terminal", flush=True)
            continue
        if prior and prior >= end.isoformat():
            latest[ticker] = prior
            print(f"[daily-prices] {ticker} {prior} current", flush=True)
            continue
        start = max(datetime.fromisoformat(prior).date() - timedelta(days=3), end - timedelta(days=400)) if prior else end - timedelta(days=400)
        try:
            rows = [r for r in fetch_history(ticker, start, end) if r[1] <= end.isoformat()]
            if rows:
                upsert_rows(con, rows)
                con.commit()
            last = con.execute("SELECT MAX(day) FROM price_daily WHERE ticker=?", (ticker,)).fetchone()[0]
            is_stale = not last or last < (end - timedelta(days=7)).isoformat()
            if is_stale and ticker.upper() in inactive and last:
                terminal.append(ticker)
            elif is_stale:
                failed.append(ticker)
            latest[ticker] = last
        except Exception:
            last = con.execute("SELECT MAX(day) FROM price_daily WHERE ticker=?", (ticker,)).fetchone()[0]
            if ticker.upper() in inactive and last:
                terminal.append(ticker)
            else:
                failed.append(ticker)
            latest[ticker] = last
        print(f"[daily-prices] {ticker} {latest.get(ticker, 'failed')}", flush=True)
    if failed:
        raise RuntimeError(f"Stale/missing price data, publication blocked: {failed}")
    active_latest = [day for ticker, day in latest.items() if ticker.upper() not in inactive and day]
    return {
        "tickers": len(tickers),
        "through": min(active_latest) if active_latest else None,
        "terminalTickers": sorted(terminal),
    }
