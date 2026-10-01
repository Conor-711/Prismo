"""Absolute-only follow returns and sampling diagnostics."""
from __future__ import annotations

import csv
import datetime as dt
import statistics
from collections import Counter, defaultdict
from pathlib import Path


DECISION_FIELDS = (
    "politician_name", "politician_id", "ticker", "disclosure_date", "trade_ids",
    "line_items", "horizon_days", "status", "entry_date", "exit_date",
    "asset_return_pct",
)
SUMMARY_FIELDS = (
    "politician_name", "politician_id", "chamber", "party", "horizon_days",
    "decision_count", "settled_count", "pending_count", "missing_price_count",
    "disclosure_day_count", "win_rate_pct", "mean_follow_return_pct",
)


def _write_csv(path: Path, rows: list[dict], fields: tuple[str, ...]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows({field: row.get(field) for field in fields} for row in rows)


def absolute_cohort(rows: list[dict]) -> dict:
    settled = [row for row in rows if row["status"] == "settled"]
    returns = [float(row["asset_return_pct"]) for row in settled]
    return {
        "settled": len(settled),
        "pending": sum(row["status"] == "pending" for row in rows),
        "missing_price": sum(row["status"] == "missing_price" for row in rows),
        "win_rate_pct": 100 * sum(value > 0 for value in returns) / len(returns) if returns else None,
        "mean_return_pct": statistics.mean(returns) if returns else None,
        "median_return_pct": statistics.median(returns) if returns else None,
    }


def write_absolute_exports(output_dir: Path, results: list[dict], summary: list[dict], raw_trades: list[dict]) -> dict:
    buys = [row for row in results if row["side"] == "Buy"]
    buy_summary = [row for row in summary if row["side"] == "Buy"]
    _write_csv(output_dir / "absolute_decision_outcomes.csv", buys, DECISION_FIELDS)
    _write_csv(output_dir / "absolute_politician_summary.csv", buy_summary, SUMMARY_FIELDS)

    by_horizon = {horizon: absolute_cohort([row for row in buys if row["horizon_days"] == horizon])
                  for horizon in (1, 5, 10)}
    settled_five = [row for row in buys if row["horizon_days"] == 5 and row["status"] == "settled"]
    by_day: dict[str, list[float]] = defaultdict(list)
    by_person: Counter[str] = Counter()
    for row in settled_five:
        by_day[row["disclosure_date"]].append(float(row["asset_return_pct"]))
        by_person[row["politician_name"]] += 1
    raw_by_id = {str(row["id"]): row for row in raw_trades}
    lags = []
    for row in settled_five:
        for trade_id in row["trade_ids"].split(","):
            raw = raw_by_id[trade_id]
            try:
                lag = (dt.date.fromisoformat(raw["disclosure_date"]) - dt.date.fromisoformat(raw["transaction_date"])).days
            except (KeyError, TypeError, ValueError):
                continue
            if lag >= 0:
                lags.append(lag)

    def pct(value: float | None, signed: bool = False) -> str:
        if value is None:
            return "—"
        return f"{value:+.2f}%" if signed else f"{value:.2f}%"

    report = [
        "# 政客披露后跟踪的绝对收益（初步研究）", "",
        "**此版本不做任何 SPY 扣减或比较。**它衡量公众在披露后买入股票/ETF 的假设收益，不是政客自身已实现或未实现的投资收益。",
        "披露后首个美股交易日以复权收盘价入场；分别持有 1、5、10 个交易日，以退出价 / 入场价 - 1 计算。每人、标的、披露日只计一个买入决策，不计手续费、滑点或仓位权重。", "",
        "| 持有交易日 | 已结算/待结算/缺行情 | 正收益比例 | 平均绝对收益 | 中位绝对收益 |",
        "|---:|---:|---:|---:|---:|",
    ]
    for horizon, cohort in by_horizon.items():
        report.append(f"| {horizon} | {cohort['settled']}/{cohort['pending']}/{cohort['missing_price']} | "
                      f"{pct(cohort['win_rate_pct'])} | {pct(cohort['mean_return_pct'], True)} | "
                      f"{pct(cohort['median_return_pct'], True)} |")

    report += ["", "## 各政客", "",
               "每格依次为胜率 / 平均绝对收益 / 已结算笔数。— 表示没有已结算样本。", "",
               "| 政客 | 1日 | 5日 | 10日 | 5日独立披露日 |",
               "|---|---:|---:|---:|---:|"]
    by_name: dict[str, dict[int, dict]] = defaultdict(dict)
    for row in buy_summary:
        by_name[row["politician_name"]][row["horizon_days"]] = row
    for name in sorted(by_name, key=lambda name: (-by_name[name].get(5, {}).get("settled_count", 0), name)):
        cells = []
        for horizon in (1, 5, 10):
            row = by_name[name].get(horizon)
            if not row or not row["settled_count"]:
                cells.append("—")
            else:
                cells.append(f"{pct(row['win_rate_pct'])} / {pct(row['mean_follow_return_pct'], True)} / {row['settled_count']}")
        report.append(f"| {name} | {' | '.join(cells)} | {by_name[name].get(5, {}).get('disclosure_day_count', 0)} |")

    day_equal_mean = statistics.mean(statistics.mean(values) for values in by_day.values()) if by_day else None
    two_largest = sum(count for _, count in by_person.most_common(2))
    concentration = 100 * two_largest / len(settled_five) if settled_five else 0
    report += ["", "## 解读限制", "",
               f"5日样本跨 {len(by_day)} 个披露日；按披露日等权后平均绝对收益为 {pct(day_equal_mean, True)}。"
               f"样本量最大的两人占已结算买入决策的 {concentration:.1f}%。",
               f"这些买入记录从实际交易到披露的中位间隔为 {statistics.median(lags):.1f} 个自然日。" if lags else "交易到披露的延迟无法计算。",
               "因此，短期跟踪表现差不等于政客选股能力差。源数据没有实际持有人、完整仓位、成本价、卖出配对和原始申报链接，无法计算他们真实的持仓收益或已实现胜率。", "",
               "已剔除非股票/ETF、期权、无有效 ticker 和同日买卖方向冲突的记录；未走完观察期及缺行情的不计入胜率。", ""]
    (output_dir / "absolute_follow_returns.md").write_text("\n".join(report), encoding="utf-8")
    return {"by_horizon": by_horizon, "five_day_disclosure_days": len(by_day),
            "top_two_share_pct": concentration, "median_transaction_to_disclosure_days": statistics.median(lags) if lags else None}
