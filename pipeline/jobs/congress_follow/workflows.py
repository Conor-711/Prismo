"""Preliminary, reproducible returns from locally captured disclosures."""
from __future__ import annotations

import csv
import concurrent.futures
import datetime as dt
import json
import re
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path

from ...platforms.market_data.price_history import fetch_yahoo_history
from .absolute import write_absolute_exports


HORIZONS = (1, 5, 10)
TICKER = re.compile(r"^[A-Z][A-Z0-9.]{0,7}$")


def build_decisions(rows: list[dict], as_of: dt.date) -> tuple[list[dict], dict[str, int]]:
    """Collapse line items sharing the same actionable disclosure signal."""
    excluded: Counter[str] = Counter()
    grouped: dict[tuple[str, str, str, str], dict] = {}
    for row in rows:
        if row.get("asset_type") not in {"Stock", "ETF"}:
            excluded["non_stock_or_etf"] += 1
            continue
        if row.get("option_type") or row.get("strike_price") or row.get("option_expiry"):
            excluded["option"] += 1
            continue
        side = str(row.get("trade_type") or "")
        if side not in {"Buy", "Sell"}:
            excluded["other_action"] += 1
            continue
        ticker = str(row.get("ticker") or "").strip().upper().replace("-", ".")
        if not TICKER.fullmatch(ticker):
            excluded["invalid_ticker"] += 1
            continue
        try:
            disclosed = dt.date.fromisoformat(str(row["disclosure_date"]))
        except (KeyError, TypeError, ValueError):
            excluded["invalid_disclosure_date"] += 1
            continue
        if disclosed > as_of:
            excluded["future_disclosure"] += 1
            continue
        person_id = str(row.get("politician_id") or row.get("politician_name") or "")
        if not person_id:
            excluded["missing_politician"] += 1
            continue
        key = (person_id, ticker, side, disclosed.isoformat())
        decision = grouped.setdefault(key, {
            "politician_id": person_id,
            "politician_name": row.get("politician_name") or person_id,
            "chamber": row.get("chamber") or "",
            "party": row.get("party") or "",
            "ticker": ticker,
            "side": side,
            "disclosure_date": disclosed.isoformat(),
            "trade_ids": [],
        })
        decision["trade_ids"].append(str(row["id"]))
    side_by_signal: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    for person_id, ticker, side, day in grouped:
        side_by_signal[(person_id, ticker, day)].add(side)
    ambiguous = {key for key, sides in side_by_signal.items() if len(sides) > 1}
    decisions = []
    for (person_id, ticker, _side, day), decision in grouped.items():
        if (person_id, ticker, day) in ambiguous:
            excluded["conflicting_sides"] += len(decision["trade_ids"])
        else:
            decisions.append(decision)
    decisions.sort(key=lambda d: (d["politician_name"], d["disclosure_date"], d["ticker"], d["side"]))
    return decisions, dict(excluded)


def load_prices(db_path: Path, tickers: set[str], start: dt.date, end: dt.date) -> dict[str, dict[dt.date, float]]:
    if not db_path.exists():
        raise FileNotFoundError(db_path)
    prices: dict[str, dict[dt.date, float]] = defaultdict(dict)
    with sqlite3.connect(db_path) as connection:
        names = sorted(tickers | {"SPY"})
        for offset in range(0, len(names), 400):
            batch = names[offset:offset + 400]
            placeholders = ",".join("?" for _ in batch)
            query = (
                "SELECT ticker, day, COALESCE(adj_close, close) FROM price_daily "
                f"WHERE ticker IN ({placeholders}) AND day BETWEEN ? AND ? "
                "AND COALESCE(adj_close, close) > 0 ORDER BY ticker, day"
            )
            for ticker, day, close in connection.execute(query, (*batch, start.isoformat(), end.isoformat())):
                prices[ticker][dt.date.fromisoformat(day)] = float(close)
    if not prices.get("SPY"):
        raise ValueError("SPY benchmark prices are unavailable")
    return prices


def supplement_yahoo_prices(
    prices: dict[str, dict[dt.date, float]], tickers: set[str],
    start: dt.date, end: dt.date, cache_path: Path, workers: int = 6,
) -> dict[str, str]:
    cached: dict = {}
    if cache_path.exists():
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
    cached_rows = cached.get("prices", {}) if cached.get("as_of") == end.isoformat() else {}
    failures: dict[str, str] = {}
    needed = sorted((tickers | {"SPY"}) - set(cached_rows))

    def fetch(ticker: str) -> tuple[str, list[tuple]]:
        return ticker, fetch_yahoo_history(ticker, start, end + dt.timedelta(days=1))

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = {executor.submit(fetch, ticker): ticker for ticker in needed}
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            ticker = futures[future]
            try:
                _, raw = future.result()
                if raw:
                    cached_rows[ticker] = [[row[1], row[7]] for row in raw]
                else:
                    failures[ticker] = "no rows"
            except Exception as exc:
                failures[ticker] = f"{type(exc).__name__}: {exc}"
            if index % 50 == 0 or index == len(needed):
                print(f"Yahoo prices {index}/{len(needed)}; failed={len(failures)}", flush=True)
    for ticker, rows in cached_rows.items():
        for day, adjusted_close in rows:
            parsed_day = dt.date.fromisoformat(day)
            if start <= parsed_day <= end and adjusted_close > 0:
                prices[ticker][parsed_day] = float(adjusted_close)
    cache_path.write_text(json.dumps({"as_of": end.isoformat(), "prices": cached_rows}, separators=(",", ":")) + "\n", encoding="utf-8")
    return failures


def settle_decisions(decisions: list[dict], prices: dict[str, dict[dt.date, float]], horizons: tuple[int, ...] = HORIZONS) -> list[dict]:
    sessions = sorted(prices["SPY"])
    results: list[dict] = []
    for decision in decisions:
        disclosed = dt.date.fromisoformat(decision["disclosure_date"])
        entry_index = next((i for i, day in enumerate(sessions) if day > disclosed), None)
        for horizon in horizons:
            result = {**decision, "trade_ids": ",".join(decision["trade_ids"]),
                      "line_items": len(decision["trade_ids"]), "horizon_days": horizon,
                      "entry_date": "", "exit_date": "", "asset_return_pct": None,
                      "spy_return_pct": None, "excess_return_pp": None}
            if entry_index is None or entry_index + horizon >= len(sessions):
                result["status"] = "pending"
            else:
                entry, exit_day = sessions[entry_index], sessions[entry_index + horizon]
                result["entry_date"], result["exit_date"] = entry.isoformat(), exit_day.isoformat()
                asset = prices.get(decision["ticker"], {})
                if entry not in asset or exit_day not in asset:
                    result["status"] = "missing_price"
                else:
                    asset_return = (asset[exit_day] / asset[entry] - 1) * 100
                    spy_return = (prices["SPY"][exit_day] / prices["SPY"][entry] - 1) * 100
                    result.update(status="settled", asset_return_pct=asset_return,
                                  spy_return_pct=spy_return, excess_return_pp=asset_return - spy_return)
            results.append(result)
    return results


def summarize(results: list[dict]) -> list[dict]:
    groups: dict[tuple[str, int, str], list[dict]] = defaultdict(list)
    for row in results:
        groups[(row["politician_id"], row["horizon_days"], row["side"])].append(row)
    summary = []
    for (_, horizon, side), rows in groups.items():
        settled = [row for row in rows if row["status"] == "settled"]
        count = len(settled)
        returns = [float(row["asset_return_pct"]) for row in settled]
        excess = [float(row["excess_return_pp"]) for row in settled]
        summary.append({
            "politician_id": rows[0]["politician_id"],
            "politician_name": rows[0]["politician_name"],
            "chamber": rows[0]["chamber"], "party": rows[0]["party"],
            "side": side, "horizon_days": horizon,
            "decision_count": len(rows), "settled_count": count,
            "pending_count": sum(row["status"] == "pending" for row in rows),
            "missing_price_count": sum(row["status"] == "missing_price" for row in rows),
            "disclosure_day_count": len({row["disclosure_date"] for row in settled}),
            "win_rate_pct": (100 * sum(value > 0 for value in returns) / count if side == "Buy" else None) if count else None,
            "mean_follow_return_pct": (sum(returns) / count if side == "Buy" else None) if count else None,
            "mean_spy_return_pct": sum(float(row["spy_return_pct"]) for row in settled) / count if count else None,
            "mean_excess_pp": (sum(excess) / count if side == "Buy" else None) if count else None,
            "sale_followed_by_decline_pct": (100 * sum(value < 0 for value in returns) / count if side == "Sell" else None) if count else None,
            "mean_post_sale_stock_return_pct": (sum(returns) / count if side == "Sell" else None) if count else None,
        })
    return sorted(summary, key=lambda row: (row["horizon_days"], row["side"], -row["settled_count"], row["politician_name"]))


def _csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def run(snapshot_path: Path, db_path: Path, output_dir: Path, as_of: dt.date, *, fetch_prices: bool = False, workers: int = 6) -> dict:
    payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
    if payload.get("source") != "disclosed_capitol" or not isinstance(payload.get("trades"), list):
        raise ValueError("Unexpected congressional trade snapshot")
    decisions, excluded = build_decisions(payload["trades"], as_of)
    tickers = {row["ticker"] for row in decisions}
    start = min(dt.date.fromisoformat(row["disclosure_date"]) for row in decisions) - dt.timedelta(days=1)
    prices = load_prices(db_path, tickers, start, as_of)
    output_dir.mkdir(parents=True, exist_ok=True)
    price_failures = supplement_yahoo_prices(prices, tickers, start, as_of, output_dir / "yahoo_prices.json", workers) if fetch_prices else {}
    results = settle_decisions(decisions, prices)
    summary = summarize(results)
    absolute_diagnostics = write_absolute_exports(output_dir, results, summary, payload["trades"])
    _csv(output_dir / "decision_outcomes.csv", results)
    _csv(output_dir / "politician_summary.csv", summary)
    counts = Counter(row["status"] for row in results)
    manifest = {
        "snapshot": str(snapshot_path.resolve()), "price_db": str(db_path.resolve()),
        "as_of": as_of.isoformat(), "latest_spy_price_date": max(prices["SPY"]).isoformat(),
        "raw_trades": len(payload["trades"]), "eligible_decisions": len(decisions),
        "politicians": len({row["politician_id"] for row in decisions}),
        "price_sources": ["local price_daily", "Yahoo adjusted close supplement"] if fetch_prices else ["local price_daily"],
        "price_fetch_failures": price_failures,
        "excluded_line_items": excluded, "outcome_status_counts": dict(counts),
        "absolute_diagnostics": absolute_diagnostics,
        "horizons_trading_days": list(HORIZONS), "benchmark": "SPY",
        "entry": "adjusted close of first US trading session strictly after disclosure date",
        "exit": "adjusted close H US trading sessions after entry",
        "aggregation": "equal weight per politician/ticker/side/disclosure-date decision; no compounding or fees",
        "limitations": ["Owner and original filing URL absent in vendor response", "Disclosure times unavailable",
                        "Sales are not modeled as short positions", "One-month snapshot and clustered filings"],
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = ["# 政客披露后跟踪表现（初步研究）", "",
              f"数据截至 {manifest['latest_spy_price_date']}；披露记录 {len(payload['trades'])} 条，去重后可跟踪决策 {len(decisions)} 条、{manifest['politicians']} 位政客。",
              "", "**口径**：仅买入股票/ETF 可作为跟踪交易。披露日后的首个美股交易日收盘模拟买入，持有 1/5/10 个交易日；以复权收盘价计算，不计交易成本。",
              "同一人、同一标的、同一方向、同一披露日合并。胜率是正收益决策占比；跟踪收益和 SPY 超额均为决策等权平均，**不是实际账户收益**。", "",
              "## 买入总体", "",
              "| 持有交易日 | 已结算/待结算/缺行情 | 胜率 | 平均跟踪收益 | 平均超额(SPY) |",
              "|---:|---:|---:|---:|---:|"]
    for horizon in HORIZONS:
        cohort = [row for row in results if row["side"] == "Buy" and row["horizon_days"] == horizon]
        settled = [row for row in cohort if row["status"] == "settled"]
        count = len(settled)
        win_rate = 100 * sum(float(row["asset_return_pct"]) > 0 for row in settled) / count if count else 0
        mean_return = sum(float(row["asset_return_pct"]) for row in settled) / count if count else 0
        mean_excess = sum(float(row["excess_return_pp"]) for row in settled) / count if count else 0
        report.append(f"| {horizon} | {count}/{sum(row['status'] == 'pending' for row in cohort)}/"
                      f"{sum(row['status'] == 'missing_price' for row in cohort)} | "
                      f"{win_rate:.2f}% | {mean_return:+.2f}% | {mean_excess:+.2f}% |")
    report += ["", "## 各政客买入表现（5日）", "",
              "| 政客 | 5日已结算/待结算/缺行情 | 胜率 | 平均跟踪收益 | 平均超额(SPY) | 披露日数 |",
              "|---|---:|---:|---:|---:|---:|"]
    for row in sorted((r for r in summary if r["side"] == "Buy" and r["horizon_days"] == 5),
                      key=lambda r: (-r["settled_count"], r["politician_name"])):
        def pct(value: float | None, *, signed: bool = True) -> str:
            return (f"{value:+.2f}%" if signed else f"{value:.2f}%") if value is not None else "—"
        report.append(f"| {row['politician_name']} | {row['settled_count']}/{row['pending_count']}/{row['missing_price_count']} | "
                      f"{pct(row['win_rate_pct'], signed=False)} | {pct(row['mean_follow_return_pct'])} | "
                      f"{pct(row['mean_excess_pp'])} | {row['disclosure_day_count']} |")
    report += ["", "## 卖出后的标的走势（5日）", "",
               "| 政客 | 已结算/待结算/缺行情 | 卖出后下跌比例 | 标的平均涨跌 |",
               "|---|---:|---:|---:|"]
    for row in sorted((r for r in summary if r["side"] == "Sell" and r["horizon_days"] == 5),
                      key=lambda r: (-r["settled_count"], r["politician_name"])):
        decline = f"{row['sale_followed_by_decline_pct']:.2f}%" if row["sale_followed_by_decline_pct"] is not None else "—"
        change = f"{row['mean_post_sale_stock_return_pct']:+.2f}%" if row["mean_post_sale_stock_return_pct"] is not None else "—"
        report.append(f"| {row['politician_name']} | {row['settled_count']}/{row['pending_count']}/{row['missing_price_count']} | {decline} | {change} |")
    report += ["", "卖出后下跌比例只是时点观察，不等于可复制的做空胜率。逐人 1日和10日结果见 politician_summary.csv。",
               "", f"**局限**：免费 API 未提供资产实际持有人和原始申报链接；方向冲突的 {excluded.get('conflicting_sides', 0)} 条原始记录已排除。"
               "本批只有约一个月披露记录，且部分集中于同一天；这些平均值不是独立的长期胜率。未核验来源前不应用于公开排名或交易决策。", ""]
    (output_dir / "report.md").write_text("\n".join(report), encoding="utf-8")
    return manifest
