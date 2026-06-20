"""Build a self-contained experimental mindshare dashboard.

The output is a single static HTML file with metrics precomputed from the
current SQLite snapshot. It intentionally does not depend on Next.js or any
external charting library.
"""
from __future__ import annotations

import json
import math
import os
import re
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from statistics import fmean


ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "prismo_snapshot.db"
OUT = ROOT / "dashboard.html"
REPORT = ROOT / "MINDSHARE_PORT_ANALYSIS.md"
FORUM_JSON_CANDIDATES = [
    Path(p)
    for p in [
        os.environ.get("FORUM_MINDSHARE_JSON"),
        ROOT / "forum_mindshare.json",
        ROOT / "experiments" / "forum_mindshare.json",
        Path("/Users/tongzheng/equity1000/forum_mindshare.json"),
    ]
    if p
]
WINDOW_HOURS = 24

STANCE_FIX = {"bullish": "bull", "bearish": "bear"}
SIGN = {"bull": 1.0, "bear": -1.0, "neutral": 0.0}
REGION_ORDER = ["jp", "kr", "us", "tw"]
REGION_LABELS = {
    "jp": "JP Yahoo",
    "kr": "KR Naver",
    "us": "US Reddit",
    "tw": "TW PTT",
}
TIER_SCORE = {"high": 1.0, "mid": 0.64, "low": 0.32, "sparse": 0.2}


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    value = value.replace("T", " ").replace("Z", "")
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    return None


def round_f(value: float | None, digits: int = 4) -> float | None:
    if value is None:
        return None
    if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
        return None
    return round(float(value), digits)


def normalize_stance(value: str | None) -> str:
    v = (value or "neutral").strip().lower()
    return STANCE_FIX.get(v, v if v in SIGN else "neutral")


def norm_token(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").lower())


def entropy(counts: Counter[str]) -> float | None:
    n = sum(counts.values())
    if n <= 0:
        return None
    parts = [c / n for c in counts.values() if c > 0]
    if not parts:
        return None
    return -sum(p * math.log(p) for p in parts) / math.log(3)


def hhi(counts: Counter[str]) -> float | None:
    n = sum(counts.values())
    if n <= 0:
        return None
    return sum((c / n) ** 2 for c in counts.values())


def safe_mean(values: list[float]) -> float | None:
    values = [float(v) for v in values if v is not None]
    return fmean(values) if values else None


def table_exists(con: sqlite3.Connection, name: str) -> bool:
    row = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return bool(row)


def load_forum_mindshare() -> tuple[dict | None, Path | None]:
    for path in FORUM_JSON_CANDIDATES:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8")), path
    return None, None


def forum_score(region: str, data: dict) -> float:
    tier = data.get("tier")
    if tier in TIER_SCORE:
        return TIER_SCORE[tier]
    n = float(data.get("n") or 0)
    cap = 120 if region in {"jp", "kr"} else 30
    return min(1.0, math.log1p(n) / math.log1p(cap)) if n else 0.0


def prune_forum_region(region: str, data: dict | None) -> dict | None:
    if not data:
        return None
    out = {
        "region": region,
        "label": REGION_LABELS[region],
        "n": int(data.get("n") or 0),
        "tier": data.get("tier", ""),
        "score": round_f(forum_score(region, data), 4),
        "capped": bool(data.get("capped") or data.get("push_capped")),
        "reliable": data.get("reliable"),
    }
    for key in [
        "span_days",
        "agree",
        "agree_n",
        "sent",
        "sent_n",
        "sent_conf",
        "views_med",
        "comments",
        "push_med",
        "opinion_share",
        "voice",
    ]:
        if key in data:
            out[key] = round_f(data[key], 4) if isinstance(data[key], float) else data[key]
    return out


def forum_sort_key(row: dict) -> tuple:
    return (
        row.get("breadth", 0),
        row.get("high_regions", 0),
        row.get("score_sum", 0),
        row.get("total_n", 0),
        row.get("ticker", ""),
    )


def build_forum_sections(raw: dict | None, source: Path | None, reddit_history: list[dict]) -> dict:
    empty = {
        "available": False,
        "source": None,
        "meta": {},
        "regions": REGION_ORDER,
        "regionLabels": REGION_LABELS,
        "rows": [],
        "heatRows": [],
        "breadthRows": [],
        "tickerRegionRows": [],
        "regionTickerRows": [],
        "jpSentRows": [],
        "caseRows": [],
        "regionProfiles": [],
    }
    if not raw or not raw.get("tickers"):
        return empty

    reddit_by_ticker = defaultdict(list)
    for row in reddit_history:
        reddit_by_ticker[row["ticker"]].append(row)

    rows = []
    for ticker, entry in raw["tickers"].items():
        regions = {}
        total_n = 0
        score_sum = 0.0
        high_regions = 0
        for region in REGION_ORDER:
            region_data = prune_forum_region(region, entry.get(region))
            if not region_data:
                continue
            regions[region] = region_data
            total_n += region_data["n"]
            score_sum += float(region_data.get("score") or 0)
            if region_data.get("tier") == "high":
                high_regions += 1
        reddit_rows = reddit_by_ticker.get(ticker, [])
        reddit_mentions = sum(r.get("mention_count", 0) for r in reddit_rows)
        reddit_sentiment = safe_mean([r.get("sentiment") for r in reddit_rows])
        rows.append(
            {
                "ticker": ticker,
                "breadth": len(regions),
                "regionsPresent": list(regions),
                "regions": regions,
                "total_n": total_n,
                "score_sum": round_f(score_sum, 4),
                "high_regions": high_regions,
                "reddit_mentions_in_snapshot": reddit_mentions,
                "reddit_sentiment_in_snapshot": round_f(reddit_sentiment, 4),
            }
        )

    rows.sort(key=forum_sort_key, reverse=True)

    region_ticker_rows = []
    region_profiles = []
    for region in REGION_ORDER:
        present = [r for r in rows if region in r["regions"]]
        present.sort(
            key=lambda r: (
                r["regions"][region].get("score") or 0,
                r["regions"][region].get("n") or 0,
                r["ticker"],
            ),
            reverse=True,
        )
        total_n = sum(r["regions"][region].get("n") or 0 for r in present)
        high = sum(1 for r in present if r["regions"][region].get("tier") == "high")
        top = present[0]["ticker"] if present else ""
        region_ticker_rows.append(
            {
                "region": region,
                "label": REGION_LABELS[region],
                "rows": [
                    {
                        "ticker": r["ticker"],
                        **r["regions"][region],
                        "breadth": r["breadth"],
                    }
                    for r in present[:12]
                ],
            }
        )
        region_profiles.append(
            {
                "region": region,
                "label": REGION_LABELS[region],
                "tickers": len(present),
                "total_n": total_n,
                "high_tier": high,
                "top_ticker": top,
            }
        )

    jp_sent = [
        {
            "ticker": r["ticker"],
            **r["regions"]["jp"],
            "breadth": r["breadth"],
        }
        for r in rows
        if r["regions"].get("jp", {}).get("sent") is not None
    ]
    jp_sent.sort(key=lambda r: ((r.get("sent_n") or 0), abs(r.get("sent") or 0)), reverse=True)

    focus = [
        "NVDA",
        "MU",
        "AMD",
        "TSLA",
        "GOOGL",
        "AAPL",
        "AVGO",
        "MSFT",
        "PLTR",
        "SOFI",
        "TSM",
        "BABA",
        "NIO",
    ]
    by_ticker = {r["ticker"]: r for r in rows}
    case_rows = [by_ticker[t] for t in focus if t in by_ticker]
    if len(case_rows) < 10:
        case_rows += [r for r in rows if r not in case_rows][: 10 - len(case_rows)]

    return {
        "available": True,
        "source": str(source) if source else None,
        "meta": {
            "generated": raw.get("generated"),
            "window_start": raw.get("window_start"),
            "window_end": raw.get("window_end"),
            "window_days": raw.get("window_days"),
            "source_total": raw.get("source_total"),
            "windowed_total": raw.get("windowed_total"),
            "ticker_count": raw.get("ticker_count"),
        },
        "regions": REGION_ORDER,
        "regionLabels": REGION_LABELS,
        "rows": rows,
        "heatRows": rows[:40],
        "breadthRows": rows[:24],
        "tickerRegionRows": [r for r in rows if r["breadth"] >= 3][:24],
        "regionTickerRows": region_ticker_rows,
        "jpSentRows": jp_sent[:18],
        "caseRows": case_rows,
        "regionProfiles": region_profiles,
    }


def load_alias_terms(con: sqlite3.Connection) -> dict[str, set[str]]:
    terms: dict[str, set[str]] = defaultdict(set)
    if not table_exists(con, "ticker_meta"):
        return terms
    for row in con.execute("SELECT ticker, company_name, aliases FROM ticker_meta"):
        ticker = row["ticker"]
        bucket = terms[ticker]
        bucket.add(norm_token(ticker.split(".")[0]))
        company = row["company_name"] or ""
        company_norm = norm_token(company)
        if len(company_norm) >= 4:
            bucket.add(company_norm)
        first = norm_token(company.split(" ")[0] if company else "")
        if len(first) >= 4:
            bucket.add(first)
        aliases = row["aliases"]
        if aliases:
            try:
                parsed = json.loads(aliases)
                if isinstance(parsed, list):
                    vals = parsed
                else:
                    vals = [str(parsed)]
            except json.JSONDecodeError:
                vals = re.split(r"[,;/|]", aliases)
            for alias in vals:
                token = norm_token(str(alias))
                if len(token) >= 3:
                    bucket.add(token)
    return terms


def color_tags(metric: dict) -> list[str]:
    tags: list[str] = []
    if metric.get("is_spike") or (metric.get("zscore") is not None and metric["zscore"] >= 2.5):
        tags.append("尖峰")
    if metric.get("rank_gap") is not None and metric["rank_gap"] >= 5:
        tags.append("被 z-score 压低")
    if metric.get("rank_gap") is not None and metric["rank_gap"] <= -3:
        tags.append("速度偏爱")
    if metric.get("top_sub_share", 0) >= 0.75 and metric.get("history_mentions", 0) >= 20:
        tags.append("专属社区")
    if metric.get("entropy") is not None and metric["entropy"] >= 0.86 and metric.get("mention_count", 0) >= 8:
        tags.append("分歧高")
    if metric.get("entropy") is not None and metric["entropy"] <= 0.48 and metric.get("mention_count", 0) >= 8:
        tags.append("共识高")
    if metric.get("unique_authors", 0) < 5:
        tags.append("样本薄")
    return tags[:4]


def build() -> dict:
    if not DB.exists():
        raise FileNotFoundError(f"Missing SQLite snapshot: {DB}")

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    alias_terms = load_alias_terms(con)

    available_tables = {
        name: table_exists(con, name)
        for name in [
            "gr_post",
            "gr_ticker_region",
            "gr_ticker",
            "asia_posts",
            "asia_analysis",
            "asia_ticker_summary",
        ]
    }

    subreddit_names = {
        row["id"]: (row["display_name"] or row["id"])
        for row in con.execute("SELECT id, display_name FROM subreddits")
    }

    post_rows = []
    for row in con.execute(
        """
        SELECT id, market, author_id, created_utc, score, num_comments, subreddit_id
        FROM posts
        WHERE COALESCE(source, 'scan') = 'scan'
        """
    ):
        ts = parse_ts(row["created_utc"])
        if not ts:
            continue
        post_rows.append({**dict(row), "ts": ts, "day": ts.date().isoformat()})

    if not post_rows:
        raise RuntimeError("No posts found in snapshot")

    markets = sorted({p["market"] for p in post_rows})
    market_stats: dict[str, dict] = {}
    for market in markets:
        rows = [p for p in post_rows if p["market"] == market]
        authors = {p["author_id"] for p in rows if p["author_id"]}
        min_ts = min(p["ts"] for p in rows)
        max_ts = max(p["ts"] for p in rows)
        market_stats[market] = {
            "posts": len(rows),
            "authors": len(authors),
            "min_ts": min_ts.isoformat(sep=" "),
            "max_ts": max_ts.isoformat(sep=" "),
            "days": (max_ts.date() - min_ts.date()).days + 1,
        }

    cutoffs = {
        market: parse_ts(stats["max_ts"]) - timedelta(hours=WINDOW_HOURS)
        for market, stats in market_stats.items()
    }
    active_authors_window: dict[str, set[str]] = defaultdict(set)
    active_posts_window: Counter[str] = Counter()
    for p in post_rows:
        if p["ts"] >= cutoffs[p["market"]]:
            active_posts_window[p["market"]] += 1
            if p["author_id"]:
                active_authors_window[p["market"]].add(p["author_id"])

    rows = []
    for row in con.execute(
        """
        SELECT m.ticker, m.confidence, m.item_id,
               p.market, p.created_utc, p.subreddit_id, p.author_id,
               p.score, p.num_comments, p.title, p.permalink,
               ia.sentiment_score, ia.stance, ia.quality_score
        FROM mentions m
        JOIN posts p ON p.id = m.item_id
        JOIN item_analysis ia ON ia.item_id = m.item_id AND ia.item_type = m.item_type
        WHERE m.item_type = 'post'
          AND COALESCE(p.source, 'scan') = 'scan'
        """
    ):
        ts = parse_ts(row["created_utc"])
        if not ts:
            continue
        stance = normalize_stance(row["stance"])
        engagement = max(int(row["score"] or 0), 0) + max(int(row["num_comments"] or 0), 0)
        quality = float(row["quality_score"] if row["quality_score"] is not None else 0.5)
        confidence = float(row["confidence"] if row["confidence"] is not None else 1.0)
        weight = max(confidence, 0.05) * (1 + math.log1p(engagement)) * max(quality, 0.1)
        sub = subreddit_names.get(row["subreddit_id"], row["subreddit_id"] or "unknown")
        permalink = row["permalink"] or ""
        url = permalink if permalink.startswith("http") else f"https://www.reddit.com{permalink}"
        rows.append(
            {
                "ticker": row["ticker"],
                "market": row["market"],
                "ts": ts,
                "day": ts.date().isoformat(),
                "subreddit": sub,
                "author": row["author_id"] or f"unknown:{row['item_id']}",
                "item_id": row["item_id"],
                "score": int(row["score"] or 0),
                "comments": int(row["num_comments"] or 0),
                "title": row["title"] or "",
                "url": url,
                "sentiment": float(row["sentiment_score"] or 0.0),
                "stance": stance,
                "sign": SIGN[stance],
                "quality": quality,
                "confidence": confidence,
                "engagement": engagement,
                "weight": weight,
                "in_window": ts >= cutoffs[row["market"]],
            }
        )

    total_mentions = len(rows)
    all_tickers = {r["ticker"] for r in rows}
    mention_authors = {r["author"] for r in rows}

    trending_map: dict[tuple[str, str], dict] = {}
    if table_exists(con, "trending"):
        for row in con.execute(
            """
            SELECT ticker, market, mention_count, baseline_mean, baseline_std,
                   zscore, sentiment_avg, sentiment_delta, is_spike, rank
            FROM trending
            WHERE window = '24h'
            """
        ):
            trending_map[(row["ticker"], row["market"])] = {
                "trend_mentions": row["mention_count"],
                "baseline_mean": round_f(row["baseline_mean"], 4),
                "baseline_std": round_f(row["baseline_std"], 4),
                "zscore": round_f(row["zscore"], 3),
                "sentiment_delta": round_f(row["sentiment_delta"], 3),
                "is_spike": bool(row["is_spike"]),
                "z_rank": row["rank"],
            }

    rollup_map: dict[tuple[str, str], dict] = {}
    if table_exists(con, "ticker_rollup"):
        for row in con.execute(
            """
            SELECT ticker, market, mention_count, weighted_mentions, mindshare_pct,
                   sentiment_avg, unique_authors
            FROM ticker_rollup
            WHERE bucket = 'window'
            """
        ):
            rollup_map[(row["ticker"], row["market"])] = {
                "rollup_mentions": row["mention_count"],
                "weighted_mentions": round_f(row["weighted_mentions"], 3),
                "mindshare_pct": round_f(row["mindshare_pct"], 3),
                "rollup_sentiment": round_f(row["sentiment_avg"], 3),
                "rollup_authors": row["unique_authors"],
            }

    def aggregate(records: list[dict], mode: str) -> list[dict]:
        grouped: dict[tuple[str, str], list[dict]] = defaultdict(list)
        for rec in records:
            grouped[(rec["ticker"], rec["market"])].append(rec)

        out = []
        for (ticker, market), group in grouped.items():
            authors = {g["author"] for g in group}
            posts = {g["item_id"] for g in group}
            stance_counts = Counter(g["stance"] for g in group)
            weight_sum = sum(g["weight"] for g in group)
            sent_w = sum(g["sentiment"] * g["weight"] for g in group)
            dir_w = sum(g["sign"] * g["weight"] for g in group)
            denom_authors = (
                len(active_authors_window[market])
                if mode == "window"
                else market_stats[market]["authors"]
            )
            metric = {
                "ticker": ticker,
                "market": market,
                "mention_count": len(group),
                "post_count": len(posts),
                "unique_authors": len(authors),
                "active_author_denom": denom_authors,
                "penetration": (len(authors) / denom_authors) if denom_authors else None,
                "sentiment": (sent_w / weight_sum) if weight_sum else safe_mean([g["sentiment"] for g in group]),
                "dir_vw": (dir_w / weight_sum) if weight_sum else None,
                "dir_raw": (stance_counts["bull"] - stance_counts["bear"]) / len(group) if group else None,
                "entropy": entropy(stance_counts),
                "bull": stance_counts["bull"],
                "bear": stance_counts["bear"],
                "neutral": stance_counts["neutral"],
                "engagement": sum(g["engagement"] for g in group),
                "quality": safe_mean([g["quality"] for g in group]),
                "confidence": safe_mean([g["confidence"] for g in group]),
                "first_seen": min(g["ts"] for g in group).isoformat(sep=" "),
                "last_seen": max(g["ts"] for g in group).isoformat(sep=" "),
            }
            metric.update(trending_map.get((ticker, market), {}))
            metric.update(rollup_map.get((ticker, market), {}))
            out.append(metric)
        return out

    window_metrics = aggregate([r for r in rows if r["in_window"]], "window")
    history_metrics = aggregate(rows, "history")
    hist_by_key = {(m["ticker"], m["market"]): m for m in history_metrics}

    sub_counts: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    author_counts: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    for r in rows:
        key = (r["ticker"], r["market"])
        sub_counts[key][r["subreddit"]] += 1
        author_counts[key][r["author"]] += 1

    for metric in history_metrics:
        key = (metric["ticker"], metric["market"])
        sc = sub_counts[key]
        ac = author_counts[key]
        top_sub, top_sub_n = sc.most_common(1)[0] if sc else ("", 0)
        top_author, top_author_n = ac.most_common(1)[0] if ac else ("", 0)
        top_norm = norm_token(top_sub)
        terms = alias_terms.get(metric["ticker"], {norm_token(metric["ticker"])})
        same_name = any(term and (term in top_norm or top_norm in term) for term in terms)
        metric.update(
            {
                "history_mentions": metric["mention_count"],
                "top_subreddit": top_sub,
                "top_sub_share": top_sub_n / metric["mention_count"] if metric["mention_count"] else 0,
                "top_sub_count": top_sub_n,
                "subreddit_hhi": hhi(sc),
                "subreddit_breadth": len(sc),
                "top_author_share": top_author_n / metric["mention_count"] if metric["mention_count"] else 0,
                "top_author_count": top_author_n,
                "author_hhi": hhi(ac),
                "same_name_capture": bool(same_name),
            }
        )

    hist_by_key = {(m["ticker"], m["market"]): m for m in history_metrics}
    for metric in window_metrics:
        hist = hist_by_key.get((metric["ticker"], metric["market"]), {})
        for key in [
            "history_mentions",
            "top_subreddit",
            "top_sub_share",
            "top_sub_count",
            "subreddit_hhi",
            "subreddit_breadth",
            "top_author_share",
            "top_author_count",
            "author_hhi",
            "same_name_capture",
        ]:
            metric[key] = hist.get(key)

    for market in markets:
        market_rows = [m for m in window_metrics if m["market"] == market]
        market_rows.sort(key=lambda m: (m["penetration"] or 0, m["unique_authors"]), reverse=True)
        for i, metric in enumerate(market_rows, 1):
            metric["penetration_rank"] = i
        no_rank = [m for m in market_rows if m.get("z_rank") is None]
        no_rank.sort(key=lambda m: (m.get("zscore") or -999), reverse=True)
        for i, metric in enumerate(no_rank, 1):
            metric["z_rank"] = metric.get("z_rank") or i

    for metric in window_metrics:
        if metric.get("z_rank") is not None and metric.get("penetration_rank") is not None:
            metric["rank_gap"] = metric["z_rank"] - metric["penetration_rank"]
        else:
            metric["rank_gap"] = None
        metric["tags"] = color_tags(metric)

    def prune_metric(metric: dict) -> dict:
        keep = {
            "ticker",
            "market",
            "mention_count",
            "post_count",
            "unique_authors",
            "active_author_denom",
            "penetration",
            "sentiment",
            "dir_vw",
            "dir_raw",
            "entropy",
            "bull",
            "bear",
            "neutral",
            "engagement",
            "quality",
            "first_seen",
            "last_seen",
            "zscore",
            "z_rank",
            "penetration_rank",
            "rank_gap",
            "baseline_mean",
            "is_spike",
            "mindshare_pct",
            "weighted_mentions",
            "history_mentions",
            "top_subreddit",
            "top_sub_share",
            "top_sub_count",
            "subreddit_hhi",
            "subreddit_breadth",
            "top_author_share",
            "top_author_count",
            "author_hhi",
            "same_name_capture",
            "tags",
        }
        out = {k: metric.get(k) for k in keep if k in metric}
        return {k: round_f(v, 5) if isinstance(v, float) else v for k, v in out.items()}

    window_out = [prune_metric(m) for m in sorted(window_metrics, key=lambda m: (m["market"], m.get("penetration_rank") or 999))]
    history_out = [prune_metric(m) for m in sorted(history_metrics, key=lambda m: m["mention_count"], reverse=True)]

    top_history = history_out[:24]
    tickers_for_heat = [m["ticker"] for m in top_history]
    seen = set()
    tickers_for_heat = [t for t in tickers_for_heat if not (t in seen or seen.add(t))][:20]
    cross_rows = []
    max_cross_mentions = max((m["mention_count"] for m in history_metrics), default=1)
    for ticker in tickers_for_heat:
        cells = {}
        total = 0
        for market in markets:
            metric = hist_by_key.get((ticker, market))
            if metric:
                cells[market] = {
                    "sentiment": round_f(metric["sentiment"], 4),
                    "penetration": round_f(metric["penetration"], 5),
                    "mentions": metric["mention_count"],
                    "authors": metric["unique_authors"],
                    "intensity": round_f(math.sqrt(metric["mention_count"] / max_cross_mentions), 4),
                }
                total += metric["mention_count"]
        cross_rows.append({"ticker": ticker, "cells": cells, "total": total})

    sub_total = Counter(r["subreddit"] for r in rows)
    top_subs = [s for s, _ in sub_total.most_common(10)]
    community_tickers = [m["ticker"] for m in history_out[:22]]
    seen = set()
    community_tickers = [t for t in community_tickers if not (t in seen or seen.add(t))][:18]
    by_ticker_sub: dict[str, Counter[str]] = defaultdict(Counter)
    for r in rows:
        by_ticker_sub[r["ticker"]][r["subreddit"]] += 1
    max_comm = max((by_ticker_sub[t][s] for t in community_tickers for s in top_subs), default=1)
    community_rows = []
    for ticker in community_tickers:
        community_rows.append(
            {
                "ticker": ticker,
                "cells": {
                    sub: {
                        "mentions": by_ticker_sub[ticker][sub],
                        "intensity": round_f(math.log1p(by_ticker_sub[ticker][sub]) / math.log1p(max_comm), 4)
                        if by_ticker_sub[ticker][sub]
                        else 0,
                    }
                    for sub in top_subs
                },
            }
        )

    dates = sorted({r["day"] for r in rows})
    last_dates = dates[-16:]
    daily_tickers = community_tickers[:14]
    by_ticker_day: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in rows:
        if r["day"] in last_dates and r["ticker"] in daily_tickers:
            by_ticker_day[(r["ticker"], r["day"])].append(r)
    max_day_n = max((len(v) for v in by_ticker_day.values()), default=1)
    daily_heat_rows = []
    for ticker in daily_tickers:
        cells = {}
        for day in last_dates:
            group = by_ticker_day.get((ticker, day), [])
            if group:
                cells[day] = {
                    "sentiment": round_f(safe_mean([g["sentiment"] for g in group]), 4),
                    "mentions": len(group),
                    "intensity": round_f(math.sqrt(len(group) / max_day_n), 4),
                }
        daily_heat_rows.append({"ticker": ticker, "cells": cells})

    by_day_market: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    for r in rows:
        by_day_market[(r["day"], r["market"])]["mentions"] += 1
        by_day_market[(r["day"], r["market"])][f"author:{r['author']}"] = 1
    volume_days = dates[-24:]
    daily_volume = []
    for day in volume_days:
        item = {"day": day}
        for market in markets:
            c = by_day_market[(day, market)]
            item[market] = c["mentions"]
        item["total"] = sum(item[m] for m in markets)
        daily_volume.append(item)

    ticker_markets: dict[str, dict[str, dict]] = defaultdict(dict)
    for metric in history_metrics:
        ticker_markets[metric["ticker"]][metric["market"]] = metric
    divergence = []
    for ticker, by_market in ticker_markets.items():
        if "us" in by_market and "cn" in by_market:
            us = by_market["us"]
            cn = by_market["cn"]
            if us["mention_count"] >= 3 and cn["mention_count"] >= 3:
                divergence.append(
                    {
                        "ticker": ticker,
                        "us_sentiment": round_f(us["sentiment"], 4),
                        "cn_sentiment": round_f(cn["sentiment"], 4),
                        "spread": round_f((us["sentiment"] or 0) - (cn["sentiment"] or 0), 4),
                        "us_mentions": us["mention_count"],
                        "cn_mentions": cn["mention_count"],
                        "us_dir": round_f(us["dir_vw"], 4),
                        "cn_dir": round_f(cn["dir_vw"], 4),
                    }
                )
    divergence.sort(key=lambda d: abs(d["spread"] or 0), reverse=True)

    concentration = [
        prune_metric(m)
        for m in sorted(
            history_metrics,
            key=lambda m: (
                (m.get("top_sub_share") or 0) * 0.7 + (m.get("top_author_share") or 0) * 0.3,
                m["mention_count"],
            ),
            reverse=True,
        )
        if m["mention_count"] >= 10
    ][:18]

    trend_rows = []
    for key, tr in trending_map.items():
        ticker, market = key
        wm = next((m for m in window_metrics if m["ticker"] == ticker and m["market"] == market), None)
        hist = hist_by_key.get(key, {})
        item = {
            "ticker": ticker,
            "market": market,
            **tr,
            "penetration": round_f(wm.get("penetration"), 5) if wm else None,
            "penetration_rank": wm.get("penetration_rank") if wm else None,
            "rank_gap": wm.get("rank_gap") if wm else None,
            "top_sub_share": round_f(hist.get("top_sub_share"), 4) if hist else None,
            "top_subreddit": hist.get("top_subreddit") if hist else None,
            "tags": color_tags({**hist, **tr, **(wm or {})}),
        }
        trend_rows.append(item)
    trend_rows.sort(key=lambda r: r.get("zscore") if r.get("zscore") is not None else -999, reverse=True)

    top_posts = sorted(
        [r for r in rows if r["in_window"]],
        key=lambda r: (r["quality"] * (1 + math.log1p(r["engagement"])) + abs(r["sentiment"]) * 0.25),
        reverse=True,
    )[:12]
    top_posts_out = [
        {
            "ticker": r["ticker"],
            "market": r["market"],
            "subreddit": r["subreddit"],
            "title": r["title"],
            "url": r["url"],
            "sentiment": round_f(r["sentiment"], 3),
            "stance": r["stance"],
            "quality": round_f(r["quality"], 3),
            "score": r["score"],
            "comments": r["comments"],
        }
        for r in top_posts
    ]

    forum_raw, forum_source = load_forum_mindshare()
    forum = build_forum_sections(forum_raw, forum_source, history_out)

    summary = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "snapshot_path": str(DB.relative_to(ROOT)),
        "report_path": str(REPORT.relative_to(ROOT)) if REPORT.exists() else None,
        "window_hours": WINDOW_HOURS,
        "markets": markets,
        "available_tables": available_tables,
        "market_stats": market_stats,
        "window_active": {
            market: {
                "posts": active_posts_window[market],
                "authors": len(active_authors_window[market]),
            }
            for market in markets
        },
        "posts": len(post_rows),
        "mentions": total_mentions,
        "tickers": len(all_tickers),
        "mention_authors": len(mention_authors),
        "forum": {
            "available": forum["available"],
            "source": forum["source"],
            **forum["meta"],
        },
        "coverage_note": (
            "已合并 equity1000 的 forum_mindshare.json（JP Yahoo / KR Naver / US Reddit / TW PTT）；"
            "Supabase 当前仍没有 gr_*/asia_* 表，所以 Prismo 原始库部分只覆盖 Reddit us/cn。"
            if forum["available"] and not available_tables.get("gr_ticker_region")
            else (
                "当前快照没有 gr_*/asia_* 表；跨区图以 Reddit us/cn market 与 subreddit 社区代理呈现。"
                if not available_tables.get("gr_ticker_region")
                else "当前快照包含 gr_* 表。"
            )
        ),
    }

    con.close()

    return {
        "summary": summary,
        "windowRows": window_out,
        "historyRows": history_out[:90],
        "crossHeat": {"markets": markets, "rows": cross_rows},
        "communityHeat": {"subreddits": top_subs, "rows": community_rows},
        "dailyHeat": {"dates": last_dates, "rows": daily_heat_rows},
        "dailyVolume": {"markets": markets, "rows": daily_volume},
        "divergence": divergence[:16],
        "concentration": concentration,
        "trendRows": trend_rows[:28],
        "topPosts": top_posts_out,
        "forum": forum,
    }


HTML_TEMPLATE = r"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Prismo Mindshare Lab</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d0f12;
      --panel: #16191f;
      --panel-2: #101318;
      --line: #2a3038;
      --line-soft: #20262d;
      --text: #edf1f5;
      --muted: #9da8b5;
      --faint: #6f7a86;
      --green: #2fc27e;
      --red: #f05a67;
      --amber: #f0b44c;
      --cyan: #48b9c7;
      --violet: #b48cff;
      --blue: #4f8df7;
      --shadow: 0 16px 44px rgba(0,0,0,.28);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-size: 14px;
      letter-spacing: 0;
    }
    a { color: inherit; text-decoration: none; }
    .shell { width: min(1480px, calc(100% - 32px)); margin: 0 auto; padding: 24px 0 48px; }
    .mast {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 20px;
      align-items: end;
      padding: 18px 0 20px;
      border-bottom: 1px solid var(--line);
    }
    .eyebrow { margin: 0 0 8px; color: var(--cyan); font-size: 12px; font-weight: 700; text-transform: uppercase; }
    h1 { margin: 0; font-size: 30px; line-height: 1.12; font-weight: 760; }
    h2 { margin: 0; font-size: 16px; font-weight: 720; }
    .subline { margin: 8px 0 0; color: var(--muted); line-height: 1.55; max-width: 920px; }
    .stamp {
      min-width: 260px;
      border: 1px solid var(--line);
      background: var(--panel-2);
      padding: 12px 14px;
      border-radius: 8px;
      color: var(--muted);
    }
    .stamp strong { display: block; color: var(--text); margin-top: 4px; font-size: 13px; word-break: break-word; }
    .pillbar { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 12px; }
    .pill {
      display: inline-flex;
      align-items: center;
      min-height: 26px;
      padding: 4px 9px;
      border: 1px solid var(--line);
      background: #12161b;
      border-radius: 999px;
      color: var(--muted);
      font-size: 12px;
      white-space: nowrap;
    }
    .pill.good { color: #bdf2d7; border-color: rgba(47,194,126,.35); background: rgba(47,194,126,.08); }
    .pill.warn { color: #ffe1a6; border-color: rgba(240,180,76,.36); background: rgba(240,180,76,.09); }
    .kpis {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 10px;
      margin: 18px 0;
    }
    .kpi, .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
    }
    .kpi { padding: 14px; min-height: 92px; }
    .kpi .label { color: var(--muted); font-size: 12px; }
    .kpi .value { margin-top: 9px; font-size: 24px; font-weight: 760; font-variant-numeric: tabular-nums; }
    .kpi .foot { margin-top: 5px; color: var(--faint); font-size: 12px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(12, minmax(0, 1fr));
      gap: 14px;
      align-items: start;
    }
    .panel { padding: 15px; overflow: hidden; }
    .span-3 { grid-column: span 3; }
    .span-4 { grid-column: span 4; }
    .span-5 { grid-column: span 5; }
    .span-6 { grid-column: span 6; }
    .span-7 { grid-column: span 7; }
    .span-8 { grid-column: span 8; }
    .span-12 { grid-column: span 12; }
    .panel-head {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 12px;
      border-bottom: 1px solid var(--line-soft);
      padding-bottom: 10px;
    }
    .hint { color: var(--muted); font-size: 12px; }
    .chart-scroll { overflow-x: auto; padding-bottom: 2px; }
    .bar-list { display: grid; gap: 8px; }
    .bar-row {
      display: grid;
      grid-template-columns: 78px minmax(120px, 1fr) 86px;
      gap: 10px;
      align-items: center;
      min-height: 28px;
    }
    .bar-label { display: flex; align-items: center; gap: 7px; min-width: 0; }
    .ticker { font-weight: 760; font-variant-numeric: tabular-nums; }
    .market {
      color: var(--muted);
      font-size: 11px;
      text-transform: uppercase;
      border: 1px solid var(--line);
      border-radius: 4px;
      padding: 1px 5px;
    }
    .bar-track { height: 10px; background: #242a31; border-radius: 999px; overflow: hidden; }
    .bar-fill { height: 100%; border-radius: 999px; background: linear-gradient(90deg, var(--cyan), var(--green)); }
    .bar-val { text-align: right; color: var(--muted); font-variant-numeric: tabular-nums; font-size: 12px; }
    .heat-grid {
      display: grid;
      gap: 4px;
      min-width: 620px;
      align-items: stretch;
    }
    .heat-label, .heat-head, .heat-cell {
      min-height: 34px;
      border-radius: 6px;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 5px 6px;
      font-variant-numeric: tabular-nums;
    }
    .heat-label {
      justify-content: flex-start;
      color: var(--text);
      background: #11151a;
      border: 1px solid var(--line-soft);
      font-weight: 720;
    }
    .heat-head { color: var(--muted); background: transparent; border: 1px solid transparent; font-size: 12px; }
    .heat-cell {
      border: 1px solid rgba(255,255,255,.04);
      color: #f7fafc;
      flex-direction: column;
      gap: 2px;
      text-shadow: 0 1px 1px rgba(0,0,0,.35);
      white-space: nowrap;
    }
    .heat-cell.blank { background: #11151a; color: var(--faint); border-color: var(--line-soft); }
    .heat-cell strong { font-size: 12px; }
    .heat-cell small { color: rgba(255,255,255,.72); font-size: 10px; }
    .svg-chart { width: 100%; height: 330px; display: block; }
    .axis { stroke: #3a424c; stroke-width: 1; }
    .axis-label { fill: var(--muted); font-size: 11px; }
    .chart-label { fill: #eef2f6; font-size: 11px; font-weight: 700; paint-order: stroke; stroke: rgba(13,15,18,.92); stroke-width: 3px; }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; min-width: 760px; }
    th, td { padding: 9px 8px; border-bottom: 1px solid var(--line-soft); text-align: left; vertical-align: middle; }
    th { color: var(--muted); font-size: 11px; font-weight: 680; text-transform: uppercase; }
    td { color: #dfe5eb; font-size: 13px; }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    .tagset { display: flex; gap: 5px; flex-wrap: wrap; }
    .tag {
      color: #f4f0df;
      background: rgba(240,180,76,.12);
      border: 1px solid rgba(240,180,76,.22);
      border-radius: 4px;
      padding: 2px 5px;
      font-size: 11px;
      white-space: nowrap;
    }
    .region-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
    }
    .region-card {
      min-height: 132px;
      border: 1px solid var(--line-soft);
      background: #11151a;
      border-radius: 8px;
      padding: 11px;
    }
    .region-card h3 {
      margin: 0 0 9px;
      font-size: 13px;
      color: var(--text);
      display: flex;
      justify-content: space-between;
      gap: 10px;
    }
    .region-card .big {
      font-size: 24px;
      font-weight: 760;
      font-variant-numeric: tabular-nums;
      margin: 5px 0 2px;
    }
    .region-card .meta {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.45;
    }
    .region-chip {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 30px;
      height: 20px;
      border: 1px solid var(--line);
      border-radius: 4px;
      font-size: 11px;
      font-weight: 760;
      text-transform: uppercase;
    }
    .forum-cell {
      min-width: 118px;
      display: grid;
      gap: 3px;
      align-content: center;
      justify-items: start;
      padding: 7px;
      border-radius: 6px;
      border: 1px solid var(--line-soft);
      background: #11151a;
    }
    .forum-cell strong { font-size: 12px; }
    .forum-cell small { color: var(--muted); font-size: 11px; line-height: 1.25; }
    .forum-cell.empty { color: var(--faint); justify-items: center; }
    .forum-cases {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }
    .case-card {
      border: 1px solid var(--line-soft);
      background: #11151a;
      border-radius: 8px;
      padding: 11px;
    }
    .case-card .case-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 10px;
      margin-bottom: 8px;
    }
    .case-regions { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; }
    .case-region {
      min-height: 56px;
      border-radius: 6px;
      padding: 6px;
      background: #151a20;
      border: 1px solid var(--line-soft);
      font-size: 11px;
      color: var(--muted);
      line-height: 1.35;
    }
    .case-region strong { display: block; color: var(--text); font-size: 12px; }
    .region-lanes {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }
    .lane {
      border: 1px solid var(--line-soft);
      background: #11151a;
      border-radius: 8px;
      padding: 11px;
    }
    .lane h3 { margin: 0 0 10px; font-size: 13px; }
    .lane-row {
      display: grid;
      grid-template-columns: 58px minmax(0, 1fr);
      gap: 8px;
      padding: 7px 0;
      border-bottom: 1px solid var(--line-soft);
      min-height: 38px;
    }
    .lane-row:last-child { border-bottom: 0; }
    .lane-row .mini { color: var(--muted); font-size: 11px; line-height: 1.25; }
    .split-row {
      display: grid;
      grid-template-columns: 78px minmax(0,1fr);
      gap: 12px;
      align-items: center;
      padding: 7px 0;
      border-bottom: 1px solid var(--line-soft);
    }
    .dual-bars { display: grid; gap: 5px; }
    .dual { display: grid; grid-template-columns: 74px minmax(120px, 1fr) 42px; gap: 8px; align-items: center; color: var(--muted); font-size: 12px; }
    .dual .fill { height: 8px; border-radius: 999px; background: var(--amber); }
    .dual .fill.author { background: var(--violet); }
    .post-list { display: grid; gap: 9px; }
    .post {
      display: grid;
      gap: 5px;
      padding: 10px 0;
      border-bottom: 1px solid var(--line-soft);
    }
    .post-title { color: var(--text); line-height: 1.4; font-weight: 650; }
    .post-meta { display: flex; flex-wrap: wrap; gap: 8px; color: var(--muted); font-size: 12px; }
    .legend { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; color: var(--muted); font-size: 12px; }
    .swatch { width: 18px; height: 8px; border-radius: 999px; display: inline-block; vertical-align: middle; margin-right: 5px; }
    .empty { color: var(--muted); padding: 20px 0; }
    @media (max-width: 1180px) {
      .kpis { grid-template-columns: repeat(3, minmax(0, 1fr)); }
      .span-3, .span-4, .span-5, .span-6, .span-7, .span-8 { grid-column: span 12; }
      .region-grid, .region-lanes { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
    @media (max-width: 720px) {
      .shell { width: min(100% - 20px, 1480px); padding-top: 10px; }
      .mast { grid-template-columns: 1fr; }
      h1 { font-size: 24px; }
      .kpis { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .grid { gap: 10px; }
      .panel { padding: 12px; }
      .bar-row { grid-template-columns: 74px minmax(100px, 1fr) 72px; }
      .region-grid, .region-lanes, .forum-cases { grid-template-columns: 1fr; }
      .case-regions { grid-template-columns: repeat(2, 1fr); }
    }
  </style>
</head>
<body>
  <main class="shell">
    <header class="mast">
      <div>
        <p class="eyebrow">Prismo · Advanced Mindshare Lab</p>
        <h1>Reddit 论坛指标驾驶舱</h1>
        <p class="subline" id="coverageNote"></p>
        <div class="pillbar" id="coveragePills"></div>
      </div>
      <div class="stamp">
        <span>Generated</span>
        <strong id="generatedAt"></strong>
        <span>Snapshot</span>
        <strong id="snapshotPath"></strong>
      </div>
    </header>

    <section class="kpis" id="kpis"></section>

    <section class="grid">
      <article class="panel span-4">
        <div class="panel-head">
          <h2>24h Penetration 排名</h2>
          <span class="hint">独立作者 / 市场活跃作者</span>
        </div>
        <div class="bar-list" id="penetrationBars"></div>
      </article>

      <article class="panel span-8">
        <div class="panel-head">
          <h2>跨市场情绪热力</h2>
          <div class="legend">
            <span><i class="swatch" style="background:rgba(240,90,103,.7)"></i>偏空</span>
            <span><i class="swatch" style="background:rgba(47,194,126,.7)"></i>偏多</span>
            <span>数字=情绪 / mentions</span>
          </div>
        </div>
        <div class="chart-scroll"><div id="crossHeat"></div></div>
      </article>

      <article class="panel span-8" id="forumHeatPanel">
        <div class="panel-head">
          <h2>四地区论坛热力</h2>
          <div class="legend">
            <span>JP=Yahoo</span><span>KR=Naver</span><span>US=Reddit</span><span>TW=PTT</span>
          </div>
        </div>
        <div class="chart-scroll"><div id="forumHeat"></div></div>
      </article>

      <article class="panel span-4" id="forumBreadthPanel">
        <div class="panel-head">
          <h2>Region Breadth</h2>
          <span class="hint">唯一诚实的跨区聚合</span>
        </div>
        <div class="bar-list" id="forumBreadthBars"></div>
      </article>

      <article class="panel span-12" id="regionProfilesPanel">
        <div class="panel-head">
          <h2>Region 概览</h2>
          <span class="hint">每个区域单独看覆盖 ticker、样本量和高热标的</span>
        </div>
        <div class="region-grid" id="regionProfiles"></div>
      </article>

      <article class="panel span-12" id="tickerRegionPanel">
        <div class="panel-head">
          <h2>Ticker × Region 对比案例</h2>
          <span class="hint">同一 ticker 在不同区域的热度、情绪代理和互动代理</span>
        </div>
        <div class="table-wrap"><table id="tickerRegionTable"></table></div>
      </article>

      <article class="panel span-12" id="regionTickerPanel">
        <div class="panel-head">
          <h2>Region × Ticker 对比案例</h2>
          <span class="hint">同一区域内部最热 ticker，各区指标各看各的</span>
        </div>
        <div class="region-lanes" id="regionTickerLanes"></div>
      </article>

      <article class="panel span-6" id="jpSentPanel">
        <div class="panel-head">
          <h2>JP 原生自评情绪</h2>
          <span class="hint">Yahoo Finance Japan 五档买卖标签</span>
        </div>
        <div class="bar-list" id="jpSentBars"></div>
      </article>

      <article class="panel span-6" id="forumCasePanel">
        <div class="panel-head">
          <h2>跨区样例卡</h2>
          <span class="hint">半导体 / 大科技 / 中概案例</span>
        </div>
        <div class="forum-cases" id="forumCases"></div>
      </article>

      <article class="panel span-6">
        <div class="panel-head">
          <h2>z-score vs Penetration</h2>
          <span class="hint">识别长期热门被速度榜压低</span>
        </div>
        <svg id="rankScatter" class="svg-chart" viewBox="0 0 720 330" role="img"></svg>
      </article>

      <article class="panel span-6">
        <div class="panel-head">
          <h2>方向 × 共识定位</h2>
          <span class="hint">x=量加权多空，y=1-entropy</span>
        </div>
        <svg id="convictionMap" class="svg-chart" viewBox="0 0 720 330" role="img"></svg>
      </article>

      <article class="panel span-7">
        <div class="panel-head">
          <h2>社区 × 标的热力</h2>
          <span class="hint">当前快照 mentions，颜色按 log 强度</span>
        </div>
        <div class="chart-scroll"><div id="communityHeat"></div></div>
      </article>

      <article class="panel span-5">
        <div class="panel-head">
          <h2>集中度风险</h2>
          <span class="hint">专属社区 / 单作者回音室</span>
        </div>
        <div id="concentrationRows"></div>
      </article>

      <article class="panel span-8">
        <div class="panel-head">
          <h2>逐日情绪热力</h2>
          <span class="hint">最近可用日期，颜色=平均情绪</span>
        </div>
        <div class="chart-scroll"><div id="dailyHeat"></div></div>
      </article>

      <article class="panel span-4">
        <div class="panel-head">
          <h2>日 mentions</h2>
          <span class="hint">按 market 堆叠</span>
        </div>
        <svg id="dailyVolume" class="svg-chart" viewBox="0 0 520 330" role="img"></svg>
      </article>

      <article class="panel span-6">
        <div class="panel-head">
          <h2>us/cn 情绪差</h2>
          <span class="hint">同一 ticker 的市场分歧</span>
        </div>
        <div class="table-wrap"><table id="divergenceTable"></table></div>
      </article>

      <article class="panel span-6">
        <div class="panel-head">
          <h2>速度榜审计</h2>
          <span class="hint">trending.zscore 对照 penetration</span>
        </div>
        <div class="table-wrap"><table id="trendTable"></table></div>
      </article>

      <article class="panel span-12">
        <div class="panel-head">
          <h2>24h 信号表</h2>
          <span class="hint">当前可生产指标候选</span>
        </div>
        <div class="table-wrap"><table id="signalTable"></table></div>
      </article>

      <article class="panel span-12">
        <div class="panel-head">
          <h2>高质量样本帖</h2>
          <span class="hint">quality × engagement proxy</span>
        </div>
        <div class="post-list" id="topPosts"></div>
      </article>
    </section>
  </main>

  <script id="prismo-data" type="application/json">__DATA_JSON__</script>
  <script>
    const DATA = JSON.parse(document.getElementById("prismo-data").textContent);
    const $ = (id) => document.getElementById(id);
    const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (m) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[m]));
    const pct = (v, d = 1) => v == null ? "—" : `${(v * 100).toFixed(d)}%`;
    const num = (v, d = 1) => v == null ? "—" : Number(v).toFixed(d);
    const signed = (v, d = 2) => v == null ? "—" : `${v > 0 ? "+" : ""}${Number(v).toFixed(d)}`;
    const compact = (v) => Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 }).format(v || 0);

    function sentBg(value, intensity = 1) {
      if (value == null) return "rgba(255,255,255,.04)";
      const alpha = Math.max(.14, Math.min(.86, .18 + Math.abs(value) * .55 + intensity * .28));
      if (value > .02) return `rgba(47,194,126,${alpha})`;
      if (value < -.02) return `rgba(240,90,103,${alpha})`;
      return `rgba(79,141,247,${Math.max(.16, intensity * .32)})`;
    }

    function pointColor(value) {
      if (value == null) return "#9da8b5";
      if (value > .05) return "#2fc27e";
      if (value < -.05) return "#f05a67";
      return "#48b9c7";
    }

    function tagHtml(tags) {
      if (!tags || !tags.length) return "";
      return `<span class="tagset">${tags.map((t) => `<span class="tag">${esc(t)}</span>`).join("")}</span>`;
    }

    const REGION_COLORS = { jp: "#f05a67", kr: "#4f8df7", us: "#f0b44c", tw: "#48b9c7" };
    const REGION_SHORT = { jp: "JP", kr: "KR", us: "US", tw: "TW" };

    function regionLabel(region) {
      return DATA.forum?.regionLabels?.[region] || region.toUpperCase();
    }

    function regionBg(region, score = 0) {
      const color = REGION_COLORS[region] || "#9da8b5";
      const alpha = Math.max(.12, Math.min(.82, .14 + (score || 0) * .64));
      const rgb = {
        "#f05a67": "240,90,103",
        "#4f8df7": "79,141,247",
        "#f0b44c": "240,180,76",
        "#48b9c7": "72,185,199",
      }[color] || "157,168,181";
      return `rgba(${rgb},${alpha})`;
    }

    function metricLine(region, c) {
      if (!c) return "no data";
      if (region === "jp") {
        const bits = [`n ${c.n}`, c.agree != null ? `agree ${pct(c.agree, 0)}` : null, c.sent != null ? `sent ${signed(c.sent, 2)} (${c.sent_n})` : null];
        return bits.filter(Boolean).join(" · ");
      }
      if (region === "kr") {
        const bits = [`n ${c.n}`, c.views_med != null ? `views med ${num(c.views_med, 0)}` : null];
        return bits.filter(Boolean).join(" · ");
      }
      if (region === "us") {
        return `n ${c.n} · comments ${compact(c.comments || 0)}`;
      }
      if (region === "tw") {
        const bits = [`n ${c.n}`, c.push_med != null ? `push med ${num(c.push_med, 0)}` : null, c.opinion_share != null ? `opinion ${pct(c.opinion_share, 0)}` : null, c.voice ? c.voice : null];
        return bits.filter(Boolean).join(" · ");
      }
      return `n ${c.n}`;
    }

    function regionChip(region, active = true) {
      const color = active ? REGION_COLORS[region] : "var(--line)";
      return `<span class="region-chip" style="color:${active ? color : "var(--faint)"};border-color:${active ? color : "var(--line)"}">${REGION_SHORT[region] || region.toUpperCase()}</span>`;
    }

    function forumCell(region, c) {
      if (!c) return `<div class="forum-cell empty">—</div>`;
      const cap = c.capped ? " · capped" : "";
      return `<div class="forum-cell" style="background:${regionBg(region, c.score)}" title="${esc(regionLabel(region))}: ${esc(metricLine(region, c))}${cap}">
        <strong>${esc(c.tier || "seen")} · ${c.n}${c.capped ? " cap" : ""}</strong>
        <small>${esc(metricLine(region, c))}</small>
      </div>`;
    }

    function renderHeader() {
      const s = DATA.summary;
      $("generatedAt").textContent = s.generated_at;
      $("snapshotPath").textContent = s.snapshot_path;
      $("coverageNote").textContent = s.coverage_note;
      const pills = [];
      for (const market of s.markets) {
        const st = s.market_stats[market];
        const win = s.window_active[market];
        pills.push(`<span class="pill good">${market.toUpperCase()} ${st.posts} posts · ${st.days} days</span>`);
        pills.push(`<span class="pill">${market.toUpperCase()} 24h ${win.authors} authors</span>`);
      }
      const hasGlobal = s.available_tables.gr_ticker_region;
      pills.push(`<span class="pill ${hasGlobal ? "good" : "warn"}">${hasGlobal ? "gr_* available" : "gr_* unavailable"}</span>`);
      if (s.forum && s.forum.available) {
        pills.push(`<span class="pill good">Forum ${s.forum.ticker_count} tickers · ${s.forum.window_start}..${s.forum.window_end}</span>`);
      }
      $("coveragePills").innerHTML = pills.join("");
    }

    function renderKpis() {
      const s = DATA.summary;
      const items = [
        ["Posts", compact(s.posts), "scan source"],
        ["Mentions", compact(s.mentions), "ticker-linked posts"],
        ["Tickers", compact(s.tickers), "unique symbols"],
        ["Authors", compact(s.mention_authors), "with mentions"],
        ["Markets", s.markets.map((m) => m.toUpperCase()).join(" / "), "snapshot coverage"],
        ["Window", `${s.window_hours}h`, "per-market latest"],
        ["Forums", s.forum?.available ? `${s.forum.ticker_count}` : "0", s.forum?.available ? "JP/KR/US/TW tickers" : "no forum json"],
      ];
      $("kpis").innerHTML = items.map(([label, value, foot]) => `
        <div class="kpi"><div class="label">${label}</div><div class="value">${value}</div><div class="foot">${foot}</div></div>
      `).join("");
    }

    function renderPenetrationBars() {
      const rows = [...DATA.windowRows].sort((a, b) => (b.penetration || 0) - (a.penetration || 0)).slice(0, 18);
      const max = Math.max(...rows.map((r) => r.penetration || 0), .001);
      $("penetrationBars").innerHTML = rows.map((r) => `
        <div class="bar-row" title="${esc(r.ticker)} ${esc(r.market)} · ${r.unique_authors}/${r.active_author_denom} authors · z rank ${r.z_rank ?? "—"}">
          <div class="bar-label"><span class="ticker">${esc(r.ticker)}</span><span class="market">${esc(r.market)}</span></div>
          <div class="bar-track"><div class="bar-fill" style="width:${Math.max(2, (r.penetration || 0) / max * 100)}%"></div></div>
          <div class="bar-val">${pct(r.penetration, 1)}</div>
        </div>
      `).join("");
    }

    function renderHeat(target, headers, rows, cellFor, minWidth = 660) {
      const grid = document.createElement("div");
      grid.className = "heat-grid";
      grid.style.gridTemplateColumns = `112px repeat(${headers.length}, minmax(70px, 1fr))`;
      grid.style.minWidth = `${minWidth}px`;
      grid.innerHTML = `<div class="heat-head"></div>` + headers.map((h) => `<div class="heat-head">${esc(h)}</div>`).join("");
      for (const row of rows) {
        grid.insertAdjacentHTML("beforeend", `<div class="heat-label">${esc(row.ticker || row.label)}</div>`);
        for (const h of headers) {
          grid.insertAdjacentHTML("beforeend", cellFor(row, h));
        }
      }
      $(target).replaceChildren(grid);
    }

    function renderCrossHeat() {
      const markets = DATA.crossHeat.markets;
      renderHeat("crossHeat", markets.map((m) => m.toUpperCase()), DATA.crossHeat.rows, (row, label) => {
        const market = label.toLowerCase();
        const c = row.cells[market];
        if (!c) return `<div class="heat-cell blank">—</div>`;
        return `<div class="heat-cell" style="background:${sentBg(c.sentiment, c.intensity)}" title="${esc(row.ticker)} ${label}: sentiment ${signed(c.sentiment)} · mentions ${c.mentions} · penetration ${pct(c.penetration, 2)}">
          <strong>${signed(c.sentiment, 2)}</strong><small>${c.mentions}</small>
        </div>`;
      }, 520);
    }

    function renderCommunityHeat() {
      const headers = DATA.communityHeat.subreddits;
      renderHeat("communityHeat", headers, DATA.communityHeat.rows, (row, sub) => {
        const c = row.cells[sub];
        if (!c || !c.mentions) return `<div class="heat-cell blank">—</div>`;
        return `<div class="heat-cell" style="background:rgba(240,180,76,${.12 + c.intensity * .72})" title="${esc(row.ticker)} in r/${esc(sub)}: ${c.mentions} mentions">
          <strong>${c.mentions}</strong>
        </div>`;
      }, 960);
    }

    function renderDailyHeat() {
      const days = DATA.dailyHeat.dates;
      const labels = days.map((d) => d.slice(5));
      const rows = DATA.dailyHeat.rows.map((r) => ({ ...r, label: r.ticker }));
      renderHeat("dailyHeat", labels, rows, (row, shortDay) => {
        const fullDay = days.find((d) => d.endsWith(shortDay));
        const c = row.cells[fullDay];
        if (!c) return `<div class="heat-cell blank">—</div>`;
        return `<div class="heat-cell" style="background:${sentBg(c.sentiment, c.intensity)}" title="${esc(row.ticker)} ${fullDay}: sentiment ${signed(c.sentiment)} · mentions ${c.mentions}">
          <strong>${signed(c.sentiment, 1)}</strong><small>${c.mentions}</small>
        </div>`;
      }, 1040);
    }

    function hideForumPanels() {
      for (const id of ["forumHeatPanel", "forumBreadthPanel", "regionProfilesPanel", "tickerRegionPanel", "regionTickerPanel", "jpSentPanel", "forumCasePanel"]) {
        const el = $(id);
        if (el) el.style.display = "none";
      }
    }

    function renderForumHeat() {
      if (!DATA.forum?.available) return hideForumPanels();
      const regions = DATA.forum.regions || [];
      const labels = regions.map((r) => REGION_SHORT[r] || r.toUpperCase());
      renderHeat("forumHeat", labels, DATA.forum.heatRows, (row, label) => {
        const region = regions.find((r) => (REGION_SHORT[r] || r.toUpperCase()) === label);
        const c = row.regions[region];
        if (!c) return `<div class="heat-cell blank">—</div>`;
        return `<div class="heat-cell" style="background:${regionBg(region, c.score)}" title="${esc(row.ticker)} · ${esc(regionLabel(region))}: ${esc(metricLine(region, c))}">
          <strong>${esc(c.tier || "seen")}</strong><small>${c.n}${c.capped ? " cap" : ""}</small>
        </div>`;
      }, 620);
    }

    function renderForumBreadth() {
      if (!DATA.forum?.available) return;
      const rows = DATA.forum.breadthRows.slice(0, 20);
      const max = Math.max(...rows.map((r) => r.score_sum || 0), 1);
      $("forumBreadthBars").innerHTML = rows.map((r) => {
        const chips = (DATA.forum.regions || []).map((reg) => regionChip(reg, !!r.regions[reg])).join("");
        return `<div class="bar-row" title="${esc(r.ticker)} · breadth ${r.breadth} · total regional n ${r.total_n}">
          <div class="bar-label"><span class="ticker">${esc(r.ticker)}</span></div>
          <div>
            <div class="bar-track"><div class="bar-fill" style="width:${Math.max(3, (r.score_sum || 0) / max * 100)}%;background:linear-gradient(90deg,#f05a67,#4f8df7,#f0b44c,#48b9c7)"></div></div>
            <div class="pillbar" style="margin-top:5px">${chips}</div>
          </div>
          <div class="bar-val">${r.breadth}/4</div>
        </div>`;
      }).join("");
    }

    function renderRegionProfiles() {
      if (!DATA.forum?.available) return;
      $("regionProfiles").innerHTML = DATA.forum.regionProfiles.map((p) => `
        <div class="region-card" style="border-color:${REGION_COLORS[p.region]}66">
          <h3><span>${regionChip(p.region)} ${esc(p.label)}</span><span>${esc(p.top_ticker)}</span></h3>
          <div class="big">${compact(p.total_n)}</div>
          <div class="meta">${p.tickers} tickers covered · ${p.high_tier} high-tier names<br/>Top attention: <strong>${esc(p.top_ticker)}</strong></div>
        </div>
      `).join("");
    }

    function renderTickerRegionTable() {
      if (!DATA.forum?.available) return;
      const regs = DATA.forum.regions || [];
      $("tickerRegionTable").innerHTML = `
        <thead><tr><th>Ticker</th>${regs.map((r) => `<th>${regionChip(r)} ${esc(regionLabel(r))}</th>`).join("")}<th class="num">Breadth</th></tr></thead>
        <tbody>${DATA.forum.tickerRegionRows.slice(0, 22).map((row) => `
          <tr>
            <td><span class="ticker">${esc(row.ticker)}</span></td>
            ${regs.map((reg) => `<td>${forumCell(reg, row.regions[reg])}</td>`).join("")}
            <td class="num">${row.breadth}/4</td>
          </tr>
        `).join("")}</tbody>
      `;
    }

    function renderRegionTickerLanes() {
      if (!DATA.forum?.available) return;
      $("regionTickerLanes").innerHTML = DATA.forum.regionTickerRows.map((lane) => `
        <div class="lane" style="border-color:${REGION_COLORS[lane.region]}55">
          <h3>${regionChip(lane.region)} ${esc(lane.label)}</h3>
          ${lane.rows.slice(0, 10).map((r) => `
            <div class="lane-row">
              <div><span class="ticker">${esc(r.ticker)}</span></div>
              <div class="mini">
                <div class="bar-track"><div class="bar-fill" style="width:${Math.max(3, (r.score || 0) * 100)}%;background:${REGION_COLORS[lane.region]}"></div></div>
                <div>${esc(r.tier || "seen")} · ${esc(metricLine(lane.region, r))}</div>
              </div>
            </div>
          `).join("")}
        </div>
      `).join("");
    }

    function renderJpSentiment() {
      if (!DATA.forum?.available) return;
      const rows = DATA.forum.jpSentRows || [];
      $("jpSentBars").innerHTML = rows.length ? rows.map((r) => {
        const color = (r.sent || 0) >= 0 ? "var(--green)" : "var(--red)";
        return `<div class="bar-row" title="${esc(r.ticker)} · JP native sentiment ${signed(r.sent)} · label n ${r.sent_n}">
          <div class="bar-label"><span class="ticker">${esc(r.ticker)}</span></div>
          <div class="bar-track"><div class="bar-fill" style="width:${Math.max(3, Math.abs(r.sent || 0) * 100)}%;background:${color}"></div></div>
          <div class="bar-val">${signed(r.sent, 2)} · n${r.sent_n}</div>
        </div>`;
      }).join("") : `<div class="empty">JP native labels 不足。</div>`;
    }

    function renderForumCases() {
      if (!DATA.forum?.available) return;
      const regs = DATA.forum.regions || [];
      $("forumCases").innerHTML = DATA.forum.caseRows.slice(0, 10).map((row) => `
        <div class="case-card">
          <div class="case-head">
            <span class="ticker">${esc(row.ticker)}</span>
            <span class="hint">${row.breadth}/4 regions · n ${compact(row.total_n)}</span>
          </div>
          <div class="case-regions">
            ${regs.map((reg) => {
              const c = row.regions[reg];
              if (!c) return `<div class="case-region"><strong>${regionChip(reg, false)}</strong>no data</div>`;
              return `<div class="case-region" style="background:${regionBg(reg, c.score)}"><strong>${regionChip(reg)} ${esc(c.tier || "seen")} · ${c.n}</strong>${esc(metricLine(reg, c))}</div>`;
            }).join("")}
          </div>
        </div>
      `).join("");
    }

    function svgEl(name, attrs = {}) {
      const el = document.createElementNS("http://www.w3.org/2000/svg", name);
      for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
      return el;
    }

    function renderScatter() {
      const svg = $("rankScatter");
      svg.replaceChildren();
      const rows = DATA.windowRows.filter((r) => r.penetration != null && r.zscore != null);
      const W = 720, H = 330, m = { l: 52, r: 24, t: 18, b: 44 };
      const xMax = Math.max(...rows.map((r) => r.penetration || 0), .01) * 1.12;
      const yMin = Math.min(-.5, ...rows.map((r) => r.zscore || 0)) - .25;
      const yMax = Math.max(3, ...rows.map((r) => r.zscore || 0)) + .35;
      const x = (v) => m.l + (v / xMax) * (W - m.l - m.r);
      const y = (v) => H - m.b - ((v - yMin) / (yMax - yMin)) * (H - m.t - m.b);
      svg.append(svgEl("line", { x1: m.l, y1: H - m.b, x2: W - m.r, y2: H - m.b, class: "axis" }));
      svg.append(svgEl("line", { x1: m.l, y1: m.t, x2: m.l, y2: H - m.b, class: "axis" }));
      for (const tick of [0, .05, .1, .2, .4].filter((v) => v <= xMax)) {
        const tx = x(tick);
        svg.append(svgEl("line", { x1: tx, x2: tx, y1: H - m.b, y2: H - m.b + 4, class: "axis" }));
        const t = svgEl("text", { x: tx, y: H - 18, "text-anchor": "middle", class: "axis-label" });
        t.textContent = pct(tick, 0);
        svg.append(t);
      }
      for (const tick of [0, 1, 2, 3, 4, 5].filter((v) => v <= yMax && v >= yMin)) {
        const ty = y(tick);
        svg.append(svgEl("line", { x1: m.l - 4, x2: m.l, y1: ty, y2: ty, class: "axis" }));
        const t = svgEl("text", { x: m.l - 8, y: ty + 4, "text-anchor": "end", class: "axis-label" });
        t.textContent = tick.toFixed(0);
        svg.append(t);
      }
      const watch = new Set(["NVDA", "GOOGL", "SPCX", "MU", "BABA", "NIO", "MSFT", "AMZN"]);
      rows.forEach((r) => {
        const cx = x(r.penetration || 0), cy = y(r.zscore || 0);
        const radius = Math.min(18, 4 + Math.sqrt(r.mention_count || 1) * 1.6);
        const c = svgEl("circle", { cx, cy, r: radius, fill: pointColor(r.sentiment), opacity: .72, stroke: "rgba(255,255,255,.45)", "stroke-width": 1 });
        c.append(svgEl("title"));
        c.querySelector("title").textContent = `${r.ticker} ${r.market}: penetration ${pct(r.penetration)} / z ${signed(r.zscore)} / ${r.mention_count} mentions`;
        svg.append(c);
        if (watch.has(r.ticker) || (r.rank_gap || 0) >= 5) {
          const label = svgEl("text", { x: cx + radius + 4, y: cy + 4, class: "chart-label" });
          label.textContent = r.ticker;
          svg.append(label);
        }
      });
      const xl = svgEl("text", { x: W / 2, y: H - 4, "text-anchor": "middle", class: "axis-label" });
      xl.textContent = "penetration";
      svg.append(xl);
      const yl = svgEl("text", { x: 14, y: 24, class: "axis-label" });
      yl.textContent = "z-score";
      svg.append(yl);
    }

    function renderConviction() {
      const svg = $("convictionMap");
      svg.replaceChildren();
      const rows = DATA.historyRows.filter((r) => r.dir_vw != null && r.entropy != null).slice(0, 55);
      const W = 720, H = 330, m = { l: 52, r: 24, t: 18, b: 44 };
      const x = (v) => m.l + ((v + 1) / 2) * (W - m.l - m.r);
      const y = (v) => H - m.b - (v * (H - m.t - m.b));
      svg.append(svgEl("line", { x1: m.l, y1: y(.5), x2: W - m.r, y2: y(.5), class: "axis" }));
      svg.append(svgEl("line", { x1: x(0), y1: m.t, x2: x(0), y2: H - m.b, class: "axis" }));
      svg.append(svgEl("line", { x1: m.l, y1: H - m.b, x2: W - m.r, y2: H - m.b, class: "axis" }));
      svg.append(svgEl("line", { x1: m.l, y1: m.t, x2: m.l, y2: H - m.b, class: "axis" }));
      [-1, -.5, 0, .5, 1].forEach((tick) => {
        const tx = x(tick);
        const t = svgEl("text", { x: tx, y: H - 18, "text-anchor": "middle", class: "axis-label" });
        t.textContent = signed(tick, 1);
        svg.append(t);
      });
      [0, .5, 1].forEach((tick) => {
        const ty = y(tick);
        const t = svgEl("text", { x: m.l - 8, y: ty + 4, "text-anchor": "end", class: "axis-label" });
        t.textContent = tick.toFixed(1);
        svg.append(t);
      });
      const watch = new Set(["SPCX", "BABA", "NVDA", "NIO", "GOOGL", "MU", "TSLA", "MSFT"]);
      rows.forEach((r) => {
        const cx = x(Math.max(-1, Math.min(1, r.dir_vw || 0)));
        const consensus = Math.max(0, Math.min(1, 1 - (r.entropy || 0)));
        const cy = y(consensus);
        const radius = Math.min(20, 4 + Math.sqrt(r.mention_count || 1) * .52);
        const c = svgEl("circle", { cx, cy, r: radius, fill: pointColor(r.sentiment), opacity: .68, stroke: "rgba(255,255,255,.38)", "stroke-width": 1 });
        c.append(svgEl("title"));
        c.querySelector("title").textContent = `${r.ticker} ${r.market}: dir ${signed(r.dir_vw)} / consensus ${num(consensus, 2)} / entropy ${num(r.entropy, 2)}`;
        svg.append(c);
        if (watch.has(r.ticker) || r.mention_count > 80) {
          const label = svgEl("text", { x: cx + radius + 4, y: cy + 4, class: "chart-label" });
          label.textContent = r.ticker;
          svg.append(label);
        }
      });
      const xl = svgEl("text", { x: W / 2, y: H - 4, "text-anchor": "middle", class: "axis-label" });
      xl.textContent = "bearish ← volume-weighted direction → bullish";
      svg.append(xl);
      const yl = svgEl("text", { x: 14, y: 24, class: "axis-label" });
      yl.textContent = "consensus";
      svg.append(yl);
    }

    function renderDailyVolume() {
      const svg = $("dailyVolume");
      svg.replaceChildren();
      const rows = DATA.dailyVolume.rows;
      const markets = DATA.dailyVolume.markets;
      const W = 520, H = 330, m = { l: 42, r: 14, t: 18, b: 42 };
      const max = Math.max(...rows.map((r) => r.total), 1);
      const bw = Math.max(6, (W - m.l - m.r) / rows.length - 3);
      const colors = { us: "#48b9c7", cn: "#f0b44c", jp: "#b48cff", kr: "#2fc27e", tw: "#f05a67" };
      svg.append(svgEl("line", { x1: m.l, y1: H - m.b, x2: W - m.r, y2: H - m.b, class: "axis" }));
      svg.append(svgEl("line", { x1: m.l, y1: m.t, x2: m.l, y2: H - m.b, class: "axis" }));
      rows.forEach((r, i) => {
        const x = m.l + i * ((W - m.l - m.r) / rows.length) + 1;
        let yBase = H - m.b;
        markets.forEach((market) => {
          const h = (r[market] || 0) / max * (H - m.t - m.b);
          yBase -= h;
          const rect = svgEl("rect", { x, y: yBase, width: bw, height: Math.max(0, h), fill: colors[market] || "#9da8b5", rx: 2 });
          rect.append(svgEl("title"));
          rect.querySelector("title").textContent = `${r.day} ${market}: ${r[market] || 0}`;
          svg.append(rect);
        });
        if (i % Math.ceil(rows.length / 6) === 0 || i === rows.length - 1) {
          const t = svgEl("text", { x: x + bw / 2, y: H - 18, "text-anchor": "middle", class: "axis-label" });
          t.textContent = r.day.slice(5);
          svg.append(t);
        }
      });
      const top = svgEl("text", { x: m.l - 8, y: m.t + 4, "text-anchor": "end", class: "axis-label" });
      top.textContent = compact(max);
      svg.append(top);
    }

    function renderConcentration() {
      const rows = DATA.concentration.slice(0, 16);
      $("concentrationRows").innerHTML = rows.map((r) => `
        <div class="split-row" title="${esc(r.ticker)} ${esc(r.market)} · HHI ${num(r.subreddit_hhi, 2)}">
          <div><span class="ticker">${esc(r.ticker)}</span> <span class="market">${esc(r.market)}</span></div>
          <div class="dual-bars">
            <div class="dual"><span>r/${esc(r.top_subreddit)}</span><span class="bar-track"><span class="fill" style="display:block;width:${Math.max(2, (r.top_sub_share || 0) * 100)}%"></span></span><span>${pct(r.top_sub_share, 0)}</span></div>
            <div class="dual"><span>top author</span><span class="bar-track"><span class="fill author" style="display:block;width:${Math.max(2, (r.top_author_share || 0) * 100)}%"></span></span><span>${pct(r.top_author_share, 0)}</span></div>
          </div>
        </div>
      `).join("");
    }

    function renderTables() {
      const divRows = DATA.divergence;
      $("divergenceTable").innerHTML = `
        <thead><tr><th>Ticker</th><th class="num">US Sent</th><th class="num">CN Sent</th><th class="num">Spread</th><th class="num">US/CN n</th></tr></thead>
        <tbody>${divRows.length ? divRows.map((r) => `
          <tr><td><span class="ticker">${esc(r.ticker)}</span></td><td class="num">${signed(r.us_sentiment)}</td><td class="num">${signed(r.cn_sentiment)}</td><td class="num">${signed(r.spread)}</td><td class="num">${r.us_mentions}/${r.cn_mentions}</td></tr>
        `).join("") : `<tr><td colspan="5" class="empty">没有足够的 us/cn 双市场样本。</td></tr>`}</tbody>
      `;

      $("trendTable").innerHTML = `
        <thead><tr><th>Ticker</th><th class="num">z</th><th class="num">z rank</th><th class="num">pen rank</th><th>Flags</th></tr></thead>
        <tbody>${DATA.trendRows.slice(0, 18).map((r) => `
          <tr><td><span class="ticker">${esc(r.ticker)}</span> <span class="market">${esc(r.market)}</span></td><td class="num">${signed(r.zscore, 2)}</td><td class="num">${r.z_rank ?? "—"}</td><td class="num">${r.penetration_rank ?? "—"}</td><td>${tagHtml(r.tags)}</td></tr>
        `).join("")}</tbody>
      `;

      $("signalTable").innerHTML = `
        <thead><tr><th>Ticker</th><th class="num">Penetration</th><th class="num">Mindshare</th><th class="num">Sent</th><th class="num">VW Dir</th><th class="num">Entropy</th><th class="num">Authors</th><th class="num">HHI</th><th>Flags</th></tr></thead>
        <tbody>${DATA.windowRows.map((r) => `
          <tr>
            <td><span class="ticker">${esc(r.ticker)}</span> <span class="market">${esc(r.market)}</span></td>
            <td class="num">${pct(r.penetration, 2)}</td>
            <td class="num">${r.mindshare_pct == null ? "—" : `${num(r.mindshare_pct, 1)}%`}</td>
            <td class="num">${signed(r.sentiment, 2)}</td>
            <td class="num">${signed(r.dir_vw, 2)}</td>
            <td class="num">${num(r.entropy, 2)}</td>
            <td class="num">${r.unique_authors}/${r.active_author_denom}</td>
            <td class="num">${num(r.subreddit_hhi, 2)}</td>
            <td>${tagHtml(r.tags)}</td>
          </tr>
        `).join("")}</tbody>
      `;
    }

    function renderPosts() {
      $("topPosts").innerHTML = DATA.topPosts.map((p) => `
        <a class="post" href="${esc(p.url)}" target="_blank" rel="noreferrer">
          <div class="post-title">${esc(p.title)}</div>
          <div class="post-meta">
            <span class="ticker">${esc(p.ticker)}</span><span class="market">${esc(p.market)}</span>
            <span>r/${esc(p.subreddit)}</span><span>${esc(p.stance)}</span>
            <span>sent ${signed(p.sentiment)}</span><span>q ${num(p.quality, 2)}</span>
            <span>${p.score} score · ${p.comments} comments</span>
          </div>
        </a>
      `).join("");
    }

    renderHeader();
    renderKpis();
    renderPenetrationBars();
    renderCrossHeat();
    renderForumHeat();
    renderForumBreadth();
    renderRegionProfiles();
    renderTickerRegionTable();
    renderRegionTickerLanes();
    renderJpSentiment();
    renderForumCases();
    renderScatter();
    renderConviction();
    renderCommunityHeat();
    renderConcentration();
    renderDailyHeat();
    renderDailyVolume();
    renderTables();
    renderPosts();
  </script>
</body>
</html>
"""


def main() -> None:
    data = build()
    data_json = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    OUT.write_text(HTML_TEMPLATE.replace("__DATA_JSON__", data_json), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    print(
        f"snapshot: {data['summary']['posts']} posts, "
        f"{data['summary']['mentions']} mentions, "
        f"{data['summary']['tickers']} tickers"
    )


if __name__ == "__main__":
    main()
