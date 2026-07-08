"""Load the complete local X/Twitter ticker universe into dev.db.

This is a local snapshot builder for the product pages:

1. Scan the local tweet JSONL archives.
2. Select tickers that have local price history and cashtag coverage in at
   least N distinct months, default 12.
3. Load all non-retweet raw X posts for those tickers into ``x_opinion``.
4. Upsert ``ticker_meta``, ``gr_ticker``, ``gr_ticker_region``, and ``gr_quote``
   so ticker overview/detail routes exist for the same universe.

The script is deterministic and rerunnable. It does not call an LLM.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

try:
    import requests
except Exception:  # noqa: BLE001
    requests = None  # type: ignore[assignment]


ROOT = Path(__file__).resolve().parents[3]
DB = Path(os.environ.get("PIPELINE_DB", ROOT / "data" / "dev.db"))
TWEET_DIRS = [
    ROOT / "equity_trader_kol_tweets_2025h2",
    ROOT / "roster_tweets_6m_f5000",
]
MIN_MONTHS = int(os.environ.get("X_COMPLETE_MIN_MONTHS", "12"))
BATCH = int(os.environ.get("X_COMPLETE_BATCH", "5000"))
SEC_COMPANY_TICKERS = "https://www.sec.gov/files/company_tickers.json"


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def tweet_files() -> list[Path]:
    out: list[Path] = []
    for folder in TWEET_DIRS:
        if folder.exists():
            out.extend(sorted(folder.glob("tweets_*.jsonl")))
    return out


def norm_ticker(raw: Any) -> str:
    return str(raw or "").strip().upper().lstrip("$").replace("-", ".")


def load_valid_price_tickers(con: sqlite3.Connection) -> set[str]:
    return {
        str(r[0]).upper()
        for r in con.execute(
            "SELECT ticker FROM price_daily WHERE close IS NOT NULL GROUP BY ticker HAVING COUNT(*) >= 80"
        )
        if r[0]
    }


def load_existing_meta(con: sqlite3.Connection) -> dict[str, dict[str, Any]]:
    rows = con.execute(
        "SELECT ticker, company_name, cik, exchange, sector, market, is_active, aliases FROM ticker_meta"
    ).fetchall()
    return {
        str(r[0]).upper(): {
            "company_name": r[1] or str(r[0]).upper(),
            "cik": r[2],
            "exchange": r[3] or "",
            "sector": r[4] or "",
            "market": r[5] or "us",
            "is_active": 1 if r[6] is None else int(bool(r[6])),
            "aliases": r[7] or "[]",
        }
        for r in rows
    }


def fetch_sec_names() -> dict[str, tuple[str, str]]:
    """Return ticker -> (company title, cik). Best-effort only."""
    if requests is None:
        return {}
    try:
        resp = requests.get(
            SEC_COMPANY_TICKERS,
            headers={"User-Agent": "Prismo local data loader zfy3712@gmail.com"},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
    except Exception as exc:  # noqa: BLE001
        print(f"[x-universe] SEC names unavailable: {exc}", flush=True)
        return {}
    out: dict[str, tuple[str, str]] = {}
    for v in data.values():
        ticker = norm_ticker(v.get("ticker"))
        title = str(v.get("title") or ticker).strip()
        cik = str(v.get("cik_str") or "").strip()
        if ticker:
            out[ticker] = (title, cik)
    return out


def scan_complete_tickers(valid: set[str]) -> tuple[set[str], dict[str, set[str]], Counter[str]]:
    months_by_ticker: dict[str, set[str]] = defaultdict(set)
    raw_posts_by_ticker: Counter[str] = Counter()
    files = tweet_files()
    scanned = 0
    for path in files:
        with path.open(encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                scanned += 1
                created = str(obj.get("created_at") or "")
                month = created[:7] if len(created) >= 7 else path.stem.replace("tweets_", "")[:7]
                tags = {norm_ticker(t) for t in obj.get("cashtags") or []}
                for ticker in tags & valid:
                    months_by_ticker[ticker].add(month)
                    raw_posts_by_ticker[ticker] += 1
    complete = {t for t, months in months_by_ticker.items() if len(months) >= MIN_MONTHS}
    print(
        f"[x-universe] scanned={scanned:,} files={len(files)} "
        f"valid_tickers={len(months_by_ticker):,} complete_months>={MIN_MONTHS}: {len(complete):,}",
        flush=True,
    )
    return complete, months_by_ticker, raw_posts_by_ticker


def ensure_tables(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS x_opinion (
          tweet_id TEXT, ticker TEXT, handle TEXT, text TEXT, lang TEXT,
          likes INTEGER, retweets INTEGER, replies INTEGER, quotes INTEGER, views INTEGER, bookmarks INTEGER,
          created TEXT, url TEXT, PRIMARY KEY (ticker, tweet_id)
        );
        CREATE INDEX IF NOT EXISTS idx_x_opinion_ticker_created ON x_opinion(ticker, created);
        CREATE INDEX IF NOT EXISTS idx_x_opinion_handle ON x_opinion(handle);

        CREATE TABLE IF NOT EXISTS gr_ticker (
          ticker VARCHAR(16) NOT NULL PRIMARY KEY,
          name_en VARCHAR(96) NOT NULL,
          name_zh VARCHAR(64) NOT NULL,
          regions_present INTEGER NOT NULL,
          total_posts INTEGER NOT NULL,
          avg_sentiment FLOAT NOT NULL,
          consensus VARCHAR(16) NOT NULL,
          spread FLOAT NOT NULL,
          divergent_region VARCHAR(8) NOT NULL,
          overview_zh TEXT NOT NULL,
          overview_en TEXT NOT NULL,
          updated_at DATETIME NOT NULL
        );

        CREATE TABLE IF NOT EXISTS gr_ticker_region (
          id INTEGER NOT NULL PRIMARY KEY,
          region VARCHAR(8) NOT NULL,
          ticker VARCHAR(16) NOT NULL,
          post_count INTEGER NOT NULL,
          bull_count INTEGER NOT NULL,
          bear_count INTEGER NOT NULL,
          neutral_count INTEGER NOT NULL,
          bull_pct FLOAT NOT NULL,
          bear_pct FLOAT NOT NULL,
          neutral_pct FLOAT NOT NULL,
          sentiment_avg FLOAT NOT NULL,
          mood_label VARCHAR(16) NOT NULL,
          engagement INTEGER NOT NULL,
          updated_at DATETIME NOT NULL,
          UNIQUE(region, ticker)
        );
        CREATE INDEX IF NOT EXISTS ix_gr_ticker_region_region ON gr_ticker_region(region);
        CREATE INDEX IF NOT EXISTS ix_gr_ticker_region_ticker ON gr_ticker_region(ticker);

        CREATE TABLE IF NOT EXISTS gr_quote (
          ticker VARCHAR(16) NOT NULL PRIMARY KEY,
          price FLOAT NOT NULL,
          prev_close FLOAT NOT NULL,
          change_pct FLOAT NOT NULL,
          currency VARCHAR(8) NOT NULL,
          asof VARCHAR(32) NOT NULL,
          updated_at DATETIME NOT NULL
        );
        """
    )
    con.commit()


def upsert_ticker_meta(con: sqlite3.Connection, tickers: set[str]) -> None:
    existing = load_existing_meta(con)
    sec_names = fetch_sec_names()
    rows = []
    for ticker in sorted(tickers):
        current = existing.get(ticker, {})
        sec_name, cik = sec_names.get(ticker, (ticker, ""))
        name = current.get("company_name") or sec_name or ticker
        rows.append(
            (
                ticker,
                str(name)[:256],
                current.get("cik") or cik or None,
                current.get("exchange") or "",
                current.get("sector") or "",
                current.get("market") or "us",
                1,
                current.get("aliases") or "[]",
            )
        )
    con.executemany(
        """INSERT INTO ticker_meta (ticker, company_name, cik, exchange, sector, market, is_active, aliases)
           VALUES (?,?,?,?,?,?,?,?)
           ON CONFLICT(ticker) DO UPDATE SET
             company_name=excluded.company_name,
             cik=COALESCE(ticker_meta.cik, excluded.cik),
             exchange=COALESCE(NULLIF(ticker_meta.exchange,''), excluded.exchange),
             sector=COALESCE(NULLIF(ticker_meta.sector,''), excluded.sector),
             market=COALESCE(NULLIF(ticker_meta.market,''), excluded.market),
             is_active=1,
             aliases=COALESCE(NULLIF(ticker_meta.aliases,''), excluded.aliases)""",
        rows,
    )
    con.commit()
    print(f"[x-universe] ticker_meta upserted={len(rows):,}", flush=True)


def load_raw_x_opinions(con: sqlite3.Connection, tickers: set[str]) -> dict[str, dict[str, Any]]:
    for i in range(0, len(tickers), 800):
        chunk = sorted(tickers)[i : i + 800]
        con.executemany("DELETE FROM x_opinion WHERE ticker = ?", [(t,) for t in chunk])
        con.commit()

    stats: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"posts": 0, "authors": set(), "engagement": 0, "first": "", "last": ""}
    )
    batch: list[tuple[Any, ...]] = []
    inserted = scanned = 0
    for path in tweet_files():
        with path.open(encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                scanned += 1
                if str(obj.get("tweet_type") or "").lower() == "retweet":
                    continue
                tweet_id = str(obj.get("tweet_id") or "")
                text = str(obj.get("text") or "")
                if not tweet_id or not text:
                    continue
                tags = sorted({norm_ticker(t) for t in obj.get("cashtags") or []} & tickers)
                if not tags:
                    continue
                handle = str(obj.get("author_handle") or "").lstrip("@")
                created = str(obj.get("created_at") or "")
                url = str(obj.get("url") or "")
                likes = int(obj.get("like_count") or 0)
                retweets = int(obj.get("retweet_count") or 0)
                replies = int(obj.get("reply_count") or 0)
                quotes = int(obj.get("quote_count") or 0)
                views = int(obj.get("view_count") or 0)
                bookmarks = int(obj.get("bookmark_count") or 0)
                engagement = likes + retweets + replies + quotes + bookmarks
                for ticker in tags:
                    batch.append(
                        (
                            tweet_id,
                            ticker,
                            handle,
                            text,
                            str(obj.get("lang") or ""),
                            likes,
                            retweets,
                            replies,
                            quotes,
                            views,
                            bookmarks,
                            created,
                            url,
                        )
                    )
                    s = stats[ticker]
                    s["posts"] += 1
                    if handle:
                        s["authors"].add(handle)
                    s["engagement"] += engagement
                    day = created[:10]
                    if day:
                        s["first"] = min(s["first"], day) if s["first"] else day
                        s["last"] = max(s["last"], day) if s["last"] else day
                if len(batch) >= BATCH:
                    con.executemany("INSERT OR REPLACE INTO x_opinion VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", batch)
                    inserted += len(batch)
                    batch.clear()
                    con.commit()
                    if inserted and inserted % 100_000 < BATCH:
                        print(f"  [x-universe] inserted_pairs={inserted:,} scanned={scanned:,}", flush=True)
    if batch:
        con.executemany("INSERT OR REPLACE INTO x_opinion VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", batch)
        inserted += len(batch)
        con.commit()
    print(f"[x-universe] x_opinion loaded pairs={inserted:,} scanned={scanned:,}", flush=True)
    return x_opinion_stats(con, tickers)


def x_opinion_stats(con: sqlite3.Connection, tickers: set[str]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    ordered = sorted(tickers)
    for i in range(0, len(ordered), 800):
        chunk = ordered[i : i + 800]
        placeholders = ",".join("?" for _ in chunk)
        rows = con.execute(
            f"""SELECT ticker,
                       COUNT(*) AS posts,
                       COALESCE(SUM(likes + retweets + replies + quotes + bookmarks), 0) AS engagement,
                       MIN(date(created)) AS first_day,
                       MAX(date(created)) AS last_day
                  FROM x_opinion
                 WHERE ticker IN ({placeholders})
                 GROUP BY ticker""",
            tuple(chunk),
        ).fetchall()
        for ticker, posts, engagement, first_day, last_day in rows:
            out[str(ticker).upper()] = {
                "posts": int(posts or 0),
                "engagement": int(engagement or 0),
                "first": first_day or "",
                "last": last_day or "",
            }
    return out


def direction_counts(con: sqlite3.Connection, tickers: set[str]) -> dict[str, Counter[str]]:
    out: dict[str, Counter[str]] = defaultdict(Counter)
    placeholders = ",".join("?" for _ in tickers)
    if not placeholders:
        return out
    rows = con.execute(
        f"""SELECT cc.ticker, c.direction, COUNT(DISTINCT cc.tweet_id) AS n
              FROM sv_call_candidate cc
              JOIN sv_call c ON c.candidate_id = cc.candidate_id
             WHERE cc.ticker IN ({placeholders})
               AND c.is_actionable_call = 1
               AND c.direction IN ('bull','bear')
             GROUP BY cc.ticker, c.direction""",
        tuple(sorted(tickers)),
    ).fetchall()
    for ticker, direction, n in rows:
        out[str(ticker).upper()][str(direction)] += int(n or 0)
    return out


def consensus_of(bull: int, bear: int) -> tuple[str, float, str]:
    directional = bull + bear
    if directional < 5:
        return "sparse", 0.0, "neutral"
    sentiment = (bull - bear) / directional
    if sentiment >= 0.35:
        return "all_bull", sentiment, "bull"
    if sentiment <= -0.35:
        return "all_bear", sentiment, "bear"
    return "mixed", sentiment, "neutral"


def upsert_gr_tables(con: sqlite3.Connection, tickers: set[str], x_stats: dict[str, dict[str, Any]]) -> None:
    meta = load_existing_meta(con)
    dirs = direction_counts(con, tickers)
    now = utc_now()
    ticker_rows = []
    region_rows = []
    for ticker in sorted(tickers):
        st = x_stats.get(ticker, {})
        posts = int(st.get("posts") or 0)
        engagement = int(st.get("engagement") or 0)
        bull = int(dirs.get(ticker, Counter()).get("bull", 0))
        bear = int(dirs.get(ticker, Counter()).get("bear", 0))
        neutral = max(0, posts - bull - bear)
        consensus, sentiment, mood = consensus_of(bull, bear)
        total = max(1, posts)
        name = str(meta.get(ticker, {}).get("company_name") or ticker)
        ticker_rows.append(
            (
                ticker,
                name[:96],
                name[:64],
                1,
                posts,
                round(sentiment, 4),
                consensus,
                0.0,
                "",
                f"{ticker} 的 X/Twitter 讨论覆盖 {posts:,} 条本地原始推文。",
                f"{ticker} has {posts:,} local raw X/Twitter posts in the complete archive.",
                now,
            )
        )
        region_rows.append(
            (
                "us",
                ticker,
                posts,
                bull,
                bear,
                neutral,
                round(bull / total * 100, 2),
                round(bear / total * 100, 2),
                round(neutral / total * 100, 2),
                round(sentiment, 4),
                mood,
                engagement,
                now,
            )
        )
    con.executemany(
        """INSERT INTO gr_ticker
           (ticker,name_en,name_zh,regions_present,total_posts,avg_sentiment,consensus,spread,divergent_region,
            overview_zh,overview_en,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(ticker) DO UPDATE SET
             name_en=excluded.name_en,
             name_zh=excluded.name_zh,
             regions_present=excluded.regions_present,
             total_posts=excluded.total_posts,
             avg_sentiment=excluded.avg_sentiment,
             consensus=excluded.consensus,
             spread=excluded.spread,
             divergent_region=excluded.divergent_region,
             overview_zh=excluded.overview_zh,
             overview_en=excluded.overview_en,
             updated_at=excluded.updated_at""",
        ticker_rows,
    )
    con.executemany("DELETE FROM gr_ticker_region WHERE region='us' AND ticker = ?", [(t,) for t in tickers])
    con.executemany(
        """INSERT INTO gr_ticker_region
           (region,ticker,post_count,bull_count,bear_count,neutral_count,bull_pct,bear_pct,neutral_pct,
            sentiment_avg,mood_label,engagement,updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        region_rows,
    )
    con.commit()
    print(f"[x-universe] gr_ticker/gr_ticker_region upserted={len(ticker_rows):,}", flush=True)


def upsert_quotes(con: sqlite3.Connection, tickers: set[str]) -> None:
    now = utc_now()
    rows = []
    for ticker in sorted(tickers):
        px = con.execute(
            "SELECT day, close FROM price_daily WHERE ticker=? AND close IS NOT NULL ORDER BY day DESC LIMIT 2",
            (ticker,),
        ).fetchall()
        if not px:
            continue
        price = float(px[0][1])
        prev = float(px[1][1]) if len(px) > 1 else price
        change_pct = ((price / prev - 1) * 100) if prev else 0.0
        rows.append((ticker, price, prev, change_pct, "USD", str(px[0][0]), now))
    con.executemany(
        """INSERT INTO gr_quote (ticker,price,prev_close,change_pct,currency,asof,updated_at)
           VALUES (?,?,?,?,?,?,?)
           ON CONFLICT(ticker) DO UPDATE SET
             price=excluded.price,
             prev_close=excluded.prev_close,
             change_pct=excluded.change_pct,
             currency=excluded.currency,
             asof=excluded.asof,
             updated_at=excluded.updated_at""",
        rows,
    )
    con.commit()
    print(f"[x-universe] gr_quote upserted={len(rows):,}", flush=True)


def main() -> None:
    db = DB.resolve()
    if not db.exists():
        raise SystemExit(f"DB not found: {db}")
    con = sqlite3.connect(db)
    try:
        con.execute("PRAGMA journal_mode=WAL")
        con.execute("PRAGMA busy_timeout=8000")
        ensure_tables(con)
        valid = load_valid_price_tickers(con)
        complete, _, _ = scan_complete_tickers(valid)
        if not complete:
            raise SystemExit("[x-universe] no complete tickers found")
        upsert_ticker_meta(con, complete)
        x_stats = load_raw_x_opinions(con, complete)
        upsert_gr_tables(con, complete, x_stats)
        upsert_quotes(con, complete)
        con.execute("ANALYZE")
        con.commit()
        print(
            "[x-universe] done "
            f"complete_tickers={len(complete):,} "
            f"x_opinion_rows={con.execute('SELECT COUNT(*) FROM x_opinion').fetchone()[0]:,} "
            f"gr_tickers={con.execute('SELECT COUNT(*) FROM gr_ticker').fetchone()[0]:,}",
            flush=True,
        )
    finally:
        con.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("[x-universe] interrupted", file=sys.stderr)
        raise
