"""Backfill Yahoo daily OHLC history for Score scoring.

This script writes to the existing local ``price_daily`` table. It is additive:
it upserts historical rows and does not delete the short-window data used by the
current UI.
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures
import datetime as dt
import json
import os
import re
import sqlite3
import time
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DB = ROOT / "data" / "dev.db"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
YAHOO = "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?{query}"
NASDAQ = "https://api.nasdaq.com/api/quote/{symbol}/historical?{query}"

DEFAULT_TWEET_DIRS = [
    ROOT / "equity_trader_kol_tweets_2025h2",
    ROOT / "roster_tweets_6m_f5000",
]

NON_EQUITY_TAGS = {
    "BTC", "ETH", "SOL", "DOGE", "XRP", "ADA", "BNB", "AVAX", "LINK", "MATIC",
    "PEPE", "SHIB", "USDT", "USDC", "USD", "EUR", "JPY", "GBP",
    "BTCUSD", "ETHUSD", "EURUSD", "USDJPY", "XAU", "XAUUSD", "XAGUSD",
    "SPX", "VIX", "DXY", "ES", "ES_F", "NQ", "NQ_F", "RTY", "YM",
    "CL", "CL_F", "GC", "GC_F", "SI", "SI_F", "HG", "ZB", "ZN",
    "BRENT", "NATGAS", "SOX", "DJI", "NDX", "TNX",
}
TICKER_RE = re.compile(r"^[A-Z][A-Z0-9.\-]{0,7}$")


def parse_day(s: str) -> dt.date:
    return dt.date.fromisoformat(s)


def epoch(day: dt.date) -> int:
    return int(dt.datetime(day.year, day.month, day.day, tzinfo=dt.timezone.utc).timestamp())


def store_ticker(ticker: str) -> str:
    return ticker.strip().upper().replace("-", ".")


def yahoo_symbol(ticker: str) -> str:
    return ticker.strip().upper().replace(".", "-")


def is_candidate_tag(tag: str) -> bool:
    tag = store_ticker(tag)
    if not tag or tag in NON_EQUITY_TAGS:
        return False
    if tag.endswith("_F"):
        return False
    if not TICKER_RE.match(tag):
        return False
    return True


def ensure_schema(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS price_daily (
             ticker TEXT NOT NULL, day TEXT NOT NULL,
             open REAL, high REAL, low REAL, close REAL, volume INTEGER,
             adj_close REAL, source TEXT, updated_at TEXT,
             PRIMARY KEY (ticker, day))"""
    )
    cols = {r[1] for r in con.execute("PRAGMA table_info(price_daily)")}
    for name, decl in [
        ("adj_close", "REAL"),
        ("source", "TEXT"),
        ("updated_at", "TEXT"),
    ]:
        if name not in cols:
            con.execute(f"ALTER TABLE price_daily ADD COLUMN {name} {decl}")
    con.commit()


def db_tickers(con: sqlite3.Connection) -> set[str]:
    tickers: set[str] = {"SPY"}
    for sql in [
        "SELECT ticker FROM gr_ticker",
        "SELECT DISTINCT ticker FROM yt_video WHERE ticker <> ''",
        "SELECT symbol FROM ticker_meta",
    ]:
        try:
            for (ticker,) in con.execute(sql):
                t = store_ticker(str(ticker or ""))
                if is_candidate_tag(t):
                    tickers.add(t)
        except sqlite3.OperationalError:
            continue
    return tickers


def cashtag_counts(tweet_dirs: list[Path]) -> collections.Counter[str]:
    counts: collections.Counter[str] = collections.Counter()
    for folder in tweet_dirs:
        if not folder.exists():
            continue
        for path in sorted(folder.glob("tweets_*.jsonl")):
            with path.open(encoding="utf-8") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    for raw in obj.get("cashtags") or []:
                        tag = store_ticker(str(raw or ""))
                        if is_candidate_tag(tag):
                            counts[tag] += 1
    return counts


def candidate_tickers(con: sqlite3.Connection, tweet_dirs: list[Path], top_n: int, min_count: int) -> list[str]:
    tickers = db_tickers(con)
    counts = cashtag_counts(tweet_dirs)
    for tag, count in counts.most_common(top_n):
        if count >= min_count:
            tickers.add(tag)
    return sorted(tickers)


def parse_number(value: object) -> float | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    text = text.replace("$", "").replace(",", "").replace("%", "")
    try:
        return float(text)
    except ValueError:
        return None


def parse_int(value: object) -> int:
    num = parse_number(value)
    return int(num) if num is not None else 0


def row_tuple(ticker: str, day: str, open_: float, high: float, low: float, close: float, volume: int, adj_close: float, source: str) -> tuple:
    return (
        ticker,
        day,
        round(float(open_), 6),
        round(float(high), 6),
        round(float(low), 6),
        round(float(close), 6),
        int(volume),
        round(float(adj_close), 6),
        source,
        dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
    )


def fetch_nasdaq_history(ticker: str, start: dt.date, end_inclusive: dt.date) -> list[tuple]:
    headers = {
        "User-Agent": UA,
        "Accept": "application/json, text/plain, */*",
        "Origin": "https://www.nasdaq.com",
        "Referer": "https://www.nasdaq.com/",
    }
    symbol = yahoo_symbol(ticker)
    # Nasdaq rejects same-day from/to ranges. Expand the request window and
    # filter parsed rows back to the caller's inclusive range below.
    request_start = start - dt.timedelta(days=1)
    request_end = end_inclusive + dt.timedelta(days=1)
    for assetclass in ("stocks", "etf"):
        query = urllib.parse.urlencode(
            {
                "assetclass": assetclass,
                "fromdate": request_start.isoformat(),
                "todate": request_end.isoformat(),
                "limit": 9999,
            }
        )
        req = urllib.request.Request(NASDAQ.format(symbol=symbol, query=query), headers=headers)
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
        rows = (((data.get("data") or {}).get("tradesTable") or {}).get("rows") or [])
        parsed: list[tuple] = []
        for row in rows:
            raw_day = row.get("date")
            close = parse_number(row.get("close"))
            if not raw_day or close is None:
                continue
            parsed_day = dt.datetime.strptime(str(raw_day), "%m/%d/%Y").date()
            if parsed_day < start or parsed_day > end_inclusive:
                continue
            day = parsed_day.isoformat()
            open_ = parse_number(row.get("open")) or close
            high = parse_number(row.get("high")) or max(open_, close)
            low = parse_number(row.get("low")) or min(open_, close)
            volume = parse_int(row.get("volume"))
            parsed.append(row_tuple(ticker, day, open_, high, low, close, volume, close, "nasdaq"))
        if parsed:
            parsed.sort(key=lambda r: r[1])
            return parsed
    return []


def fetch_yahoo_history(ticker: str, start: dt.date, end_exclusive: dt.date) -> list[tuple]:
    symbol = yahoo_symbol(ticker)
    query = urllib.parse.urlencode(
        {
            "period1": epoch(start),
            "period2": epoch(end_exclusive),
            "interval": "1d",
            "events": "history",
            "includeAdjustedClose": "true",
        }
    )
    req = urllib.request.Request(YAHOO.format(symbol=symbol, query=query), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=25) as r:
        data = json.load(r)
    chart = data.get("chart") or {}
    if chart.get("error"):
        return []
    result = chart.get("result") or []
    if not result:
        return []
    result = result[0]
    timestamps = result.get("timestamp") or []
    quote = ((result.get("indicators") or {}).get("quote") or [{}])[0]
    adj = ((result.get("indicators") or {}).get("adjclose") or [{}])[0].get("adjclose") or []
    opens = quote.get("open") or []
    highs = quote.get("high") or []
    lows = quote.get("low") or []
    closes = quote.get("close") or []
    volumes = quote.get("volume") or []
    rows: list[tuple] = []
    for i, ts in enumerate(timestamps):
        close = closes[i] if i < len(closes) else None
        if close is None:
            continue
        open_ = opens[i] if i < len(opens) and opens[i] is not None else close
        high = highs[i] if i < len(highs) and highs[i] is not None else max(open_, close)
        low = lows[i] if i < len(lows) and lows[i] is not None else min(open_, close)
        volume = volumes[i] if i < len(volumes) and volumes[i] is not None else 0
        adj_close = adj[i] if i < len(adj) and adj[i] is not None else close
        day = dt.datetime.fromtimestamp(ts, tz=dt.timezone.utc).strftime("%Y-%m-%d")
        rows.append(row_tuple(ticker, day, open_, high, low, close, int(volume), adj_close, "yahoo"))
    return rows


def fetch_history(ticker: str, start: dt.date, end_inclusive: dt.date) -> list[tuple]:
    try:
        rows = fetch_nasdaq_history(ticker, start, end_inclusive)
        if rows:
            return rows
    except Exception:
        pass
    if os.environ.get("SV_PRICE_YAHOO_FALLBACK", "").lower() in {"1", "true", "yes"}:
        return fetch_yahoo_history(ticker, start, end_inclusive + dt.timedelta(days=1))
    return []


def upsert_rows(con: sqlite3.Connection, rows: list[tuple]) -> None:
    if not rows:
        return
    con.executemany(
        """INSERT INTO price_daily
             (ticker, day, open, high, low, close, volume, adj_close, source, updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(ticker, day) DO UPDATE SET
             open=excluded.open,
             high=excluded.high,
             low=excluded.low,
             close=excluded.close,
             volume=excluded.volume,
             adj_close=excluded.adj_close,
             source=excluded.source,
             updated_at=excluded.updated_at""",
        rows,
    )


def run(
    *,
    db: str = str(DB),
    start: str = "2025-06-01",
    end: str | None = None,
    top_n: int = 1000,
    min_count: int = 25,
    tweet_dir: list[str] | None = None,
    only: str = "",
    sleep: float = 0.12,
    workers: int = 6,
    limit: int = 0,
) -> None:
    start_day = parse_day(start)
    end_inclusive = parse_day(end) if end else dt.datetime.now(dt.timezone.utc).date()
    tweet_dirs = [Path(p).expanduser() for p in (tweet_dir or [])] or DEFAULT_TWEET_DIRS

    con = sqlite3.connect(db)
    ensure_schema(con)

    if only.strip():
        tickers = sorted({store_ticker(t) for t in only.split(",") if is_candidate_tag(t)})
    else:
        tickers = candidate_tickers(con, tweet_dirs, top_n, min_count)
    if limit > 0:
        tickers = tickers[:limit]

    print(
        f"[sv-price] db={os.path.abspath(db)} tickers={len(tickers)} "
        f"window={start_day}..{end_inclusive} top_n={top_n} min_count={min_count}",
        flush=True,
    )
    ok = failed = total_rows = 0

    def fetch_one(ticker: str) -> tuple[str, list[tuple], str | None]:
        try:
            rows = fetch_history(ticker, start_day, end_inclusive)
            if not rows:
                return ticker, [], "no data"
            return ticker, rows, None
        except Exception as exc:  # noqa: BLE001
            return ticker, [], f"{type(exc).__name__}: {exc}"

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        future_to_ticker = {pool.submit(fetch_one, ticker): ticker for ticker in tickers}
        for i, future in enumerate(concurrent.futures.as_completed(future_to_ticker), 1):
            ticker, rows, err = future.result()
            if rows:
                upsert_rows(con, rows)
                con.commit()
                ok += 1
                total_rows += len(rows)
                print(f"  [{i}/{len(tickers)}] {ticker}: {len(rows)} rows {rows[0][1]}..{rows[-1][1]}", flush=True)
            else:
                failed += 1
                print(f"  [{i}/{len(tickers)}] {ticker}: {err or 'no data'}", flush=True)
            if sleep > 0:
                time.sleep(sleep)

    summary = con.execute(
        "SELECT count(*), count(DISTINCT ticker), min(day), max(day) FROM price_daily"
    ).fetchone()
    print(
        f"[sv-price] done ok={ok} failed={failed} inserted_or_updated_rows={total_rows} "
        f"price_daily_rows={summary[0]} tickers={summary[1]} range={summary[2]}..{summary[3]}",
        flush=True,
    )
    con.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill price_daily for Score scoring.")
    parser.add_argument("--db", default=str(DB))
    parser.add_argument("--start", default="2025-06-01")
    parser.add_argument("--end", default=None, help="Inclusive YYYY-MM-DD. Defaults to today UTC.")
    parser.add_argument("--top-n", type=int, default=1000, help="Top cashtags to include from tweet JSONL.")
    parser.add_argument("--min-count", type=int, default=25)
    parser.add_argument("--tweet-dir", action="append", default=[], help="Folder containing tweets_*.jsonl.")
    parser.add_argument("--only", default="", help="Comma-separated tickers for a focused run.")
    parser.add_argument("--sleep", type=float, default=0.12)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--limit", type=int, default=0, help="Debug cap after ticker selection.")
    args = parser.parse_args()
    run(
        db=args.db,
        start=args.start,
        end=args.end,
        top_n=args.top_n,
        min_count=args.min_count,
        tweet_dir=args.tweet_dir,
        only=args.only,
        sleep=args.sleep,
        workers=args.workers,
        limit=args.limit,
    )


if __name__ == "__main__":
    main()
