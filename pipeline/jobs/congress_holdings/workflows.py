"""Estimate asset returns for buys without a later disclosed exit in this snapshot."""
from __future__ import annotations

import csv
import datetime as dt
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

from ..congress_follow.workflows import TICKER, load_prices, supplement_yahoo_prices


def build_unclosed_buys(rows: list[dict], as_of: dt.date) -> tuple[list[dict], dict[str, int]]:
    exclusions: Counter[str] = Counter()
    valid = []
    for row in rows:
        if row.get("asset_type") not in {"Stock", "ETF"}:
            exclusions["non_stock_or_etf"] += 1
            continue
        if any(row.get(field) for field in ("option_type", "strike_price", "option_expiry")):
            exclusions["option"] += 1
            continue
        action = str(row.get("trade_type") or "")
        if action not in {"Buy", "Sell", "Exchange"}:
            exclusions["other_action"] += 1
            continue
        ticker = str(row.get("ticker") or "").strip().upper().replace("-", ".")
        if not TICKER.fullmatch(ticker):
            exclusions["invalid_ticker"] += 1
            continue
        try:
            transaction_date = dt.date.fromisoformat(str(row["transaction_date"]))
            disclosure_date = dt.date.fromisoformat(str(row["disclosure_date"]))
        except (KeyError, TypeError, ValueError):
            exclusions["invalid_date"] += 1
            continue
        if disclosure_date > as_of or transaction_date > as_of:
            exclusions["future_date"] += 1
            continue
        person_id = str(row.get("politician_id") or row.get("politician_name") or "")
        if not person_id:
            exclusions["missing_politician"] += 1
            continue
        valid.append((row, person_id, ticker, action, transaction_date))

    exits: dict[tuple[str, str], list[dt.date]] = defaultdict(list)
    for _, person_id, ticker, action, transaction_date in valid:
        if action in {"Sell", "Exchange"}:
            exits[(person_id, ticker)].append(transaction_date)

    lots: dict[tuple[str, str, dt.date], dict] = {}
    for row, person_id, ticker, action, transaction_date in valid:
        if action != "Buy":
            continue
        if any(exit_date >= transaction_date for exit_date in exits[(person_id, ticker)]):
            exclusions["later_exit_disclosed"] += 1
            continue
        key = person_id, ticker, transaction_date
        lot = lots.setdefault(key, {
            "politician_id": person_id,
            "politician_name": str(row.get("politician_name") or person_id),
            "chamber": str(row.get("chamber") or ""),
            "party": str(row.get("party") or ""),
            "ticker": ticker,
            "transaction_date": transaction_date.isoformat(),
            "first_disclosure_date": str(row["disclosure_date"]),
            "source_trade_ids": [],
        })
        lot["source_trade_ids"].append(str(row["id"]))
        lot["first_disclosure_date"] = min(lot["first_disclosure_date"], str(row["disclosure_date"]))
    return sorted(lots.values(), key=lambda lot: (lot["politician_name"], lot["ticker"], lot["transaction_date"])), dict(exclusions)


def mark_to_market(lots: list[dict], prices: dict[str, dict[dt.date, float]]) -> list[dict]:
    sessions = sorted(prices["SPY"])
    latest = sessions[-1]
    marked = []
    for lot in lots:
        trade_date = dt.date.fromisoformat(lot["transaction_date"])
        entry_index = next((index for index, day in enumerate(sessions) if day >= trade_date), None)
        result = {**lot, "source_trade_ids": ",".join(lot["source_trade_ids"]),
                  "line_items": len(lot["source_trade_ids"]),
                  "entry_date": "", "price_date": latest.isoformat(),
                  "entry_adjusted_close": None, "latest_adjusted_close": None,
                  "holding_calendar_days": None, "holding_trading_days": None,
                  "unrealized_asset_return_pct": None}
        if entry_index is None or sessions[entry_index] > latest:
            result["status"] = "no_entry_session"
        else:
            entry = sessions[entry_index]
            result["entry_date"] = entry.isoformat()
            asset = prices.get(lot["ticker"], {})
            if entry not in asset:
                result["status"] = "missing_entry_price"
            elif latest not in asset:
                result["status"] = "missing_latest_price"
            else:
                result.update(
                    status="priced_open_proxy",
                    entry_adjusted_close=asset[entry],
                    latest_adjusted_close=asset[latest],
                    holding_calendar_days=(latest - entry).days,
                    holding_trading_days=len(sessions) - 1 - entry_index,
                    unrealized_asset_return_pct=(asset[latest] / asset[entry] - 1) * 100,
                )
        marked.append(result)
    return marked


def summarize(marked: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in marked:
        groups[row["politician_id"]].append(row)
    summaries = []
    for rows in groups.values():
        priced = [row for row in rows if row["status"] == "priced_open_proxy"]
        returns = [float(row["unrealized_asset_return_pct"]) for row in priced]
        summaries.append({
            "politician_id": rows[0]["politician_id"],
            "politician_name": rows[0]["politician_name"],
            "chamber": rows[0]["chamber"], "party": rows[0]["party"],
            "candidate_lots": len(rows), "priced_lots": len(priced),
            "missing_price_lots": len(rows) - len(priced),
            "distinct_purchase_days": len({row["transaction_date"] for row in priced}),
            "positive_return_rate_pct": 100 * sum(value > 0 for value in returns) / len(returns) if returns else None,
            "mean_unrealized_return_pct": statistics.mean(returns) if returns else None,
            "median_unrealized_return_pct": statistics.median(returns) if returns else None,
            "mean_holding_calendar_days": statistics.mean(row["holding_calendar_days"] for row in priced) if priced else None,
        })
    return sorted(summaries, key=lambda row: (-row["priced_lots"], row["politician_name"]))


def _csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def run(snapshot_path: Path, db_path: Path, output_dir: Path, as_of: dt.date, *, fetch_prices: bool = False, workers: int = 6) -> dict:
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    if snapshot.get("source") != "disclosed_capitol" or not isinstance(snapshot.get("trades"), list):
        raise ValueError("Unexpected congressional trade snapshot")
    lots, excluded = build_unclosed_buys(snapshot["trades"], as_of)
    if not lots:
        raise ValueError("No eligible buy lots in the snapshot")
    output_dir.mkdir(parents=True, exist_ok=True)
    start = min(dt.date.fromisoformat(lot["transaction_date"]) for lot in lots) - dt.timedelta(days=1)
    tickers = {lot["ticker"] for lot in lots}
    prices = load_prices(db_path, tickers, start, as_of)
    price_failures = supplement_yahoo_prices(prices, tickers, start, as_of, output_dir / "yahoo_prices.json", workers) if fetch_prices else {}
    marked = mark_to_market(lots, prices)
    summary = summarize(marked)
    _csv(output_dir / "unclosed_buy_lots.csv", marked)
    _csv(output_dir / "politician_open_buy_returns.csv", summary)
    priced = [row for row in marked if row["status"] == "priced_open_proxy"]
    returns = [float(row["unrealized_asset_return_pct"]) for row in priced]
    top_two_count = sum(row["priced_lots"] for row in summary[:2])
    top_two_share = 100 * top_two_count / len(priced) if priced else None
    first_buy = min(lot["transaction_date"] for lot in lots)
    last_buy = max(lot["transaction_date"] for lot in lots)
    manifest = {
        "as_of": as_of.isoformat(), "latest_market_date": max(prices["SPY"]).isoformat(),
        "source_snapshot": str(snapshot_path.resolve()),
        "snapshot_query_since": snapshot.get("query_since"),
        "snapshot_query_until": snapshot.get("query_until"),
        "snapshot_possibly_truncated": snapshot.get("possibly_truncated"),
        "source_trade_count": len(snapshot["trades"]),
        "candidate_buy_lots": len(lots), "priced_lots": len(priced),
        "politician_count": len(summary), "excluded_line_items": excluded,
        "candidate_transaction_date_range": [first_buy, last_buy],
        "top_two_politician_priced_lot_share_pct": top_two_share,
        "price_status_counts": dict(Counter(row["status"] for row in marked)),
        "price_fetch_failures": price_failures,
        "entry_policy": "adjusted close on transaction date, or next US trading session",
        "latest_policy": "adjusted close on latest common US trading session; no stale forward fill",
        "exit_policy": "exclude entire buy lot if same politician/ticker has any disclosed sell or exchange on or after its transaction date",
        "aggregation": "equal weight per politician/ticker/transaction-date buy lot; no cost basis, position sizing, fees, or tax",
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def fmt(value: float | None, signed: bool = False) -> str:
        if value is None:
            return "—"
        return f"{value:+.2f}%" if signed else f"{value:.2f}%"

    report = ["# 未见后续卖出买入批次的估算浮盈", "",
              f"行情截至 {manifest['latest_market_date']}；披露快照范围 {manifest['snapshot_query_since']} 至 {manifest['snapshot_query_until']}。",
              f"候选买入交易日期为 {first_buy} 至 {last_buy}；这只覆盖约数周到两个多月的价格表现，尚不能评价中长期投资能力。",
              "这里的“未见卖出”仅指**当前快照未检出**同一政客、同一标的、买入日或之后的卖出/换股披露，不代表真实账户仍持有。",
              "买入基准价是交易日复权收盘价（休市则用下一交易日），而不是未知的真实成交价。最新价必须与共同市场日期完全匹配，不使用陈旧价格。", "",
              f"去重后候选买入批次 {len(lots)}，其中有完整行情 {len(priced)}；"
              f"正收益比例 {fmt(100 * sum(value > 0 for value in returns) / len(returns) if returns else None)}；"
              f"等权平均估算浮盈 {fmt(statistics.mean(returns) if returns else None, True)}；"
              f"中位数 {fmt(statistics.median(returns) if returns else None, True)}。", "",
              "| 政客 | 有行情/候选批次 | 正收益比例 | 平均估算浮盈 | 中位数 | 平均持有自然日 |",
              "|---|---:|---:|---:|---:|---:|"]
    for row in summary:
        days = f"{row['mean_holding_calendar_days']:.0f}" if row["mean_holding_calendar_days"] is not None else "—"
        report.append(f"| {row['politician_name']} | {row['priced_lots']}/{row['candidate_lots']} | "
                      f"{fmt(row['positive_return_rate_pct'])} | {fmt(row['mean_unrealized_return_pct'], True)} | "
                      f"{fmt(row['median_unrealized_return_pct'], True)} | {days} |")
    report += ["", f"有行情的批次中，样本最多的两位政客占 {top_two_share:.1f}%，总体等权均值因此高度受其影响。" if top_two_share is not None else "",
               "**不能解读为真实投资胜率。**原始 API 缺少实际持有人、成交价、准确买卖数量和申报原文；"
               "金额仅为区间，因此不计算账户加权收益。快照只含上述披露窗口，更早或尚未披露的卖出会漏掉；"
               "任一后续卖出会保守地排除整个买入批次，即使它可能只是部分减仓。", ""]
    (output_dir / "report.md").write_text("\n".join(report), encoding="utf-8")
    return manifest
