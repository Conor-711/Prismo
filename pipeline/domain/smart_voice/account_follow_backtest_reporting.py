"""Reports for per-Smart-Account follow-strategy returns."""
from __future__ import annotations

import csv
import json
import statistics
from pathlib import Path
from typing import Any


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> int:
    columns: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for column in row:
            if column not in seen:
                seen.add(column)
                columns.append(column)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)


def _pct(value: Any) -> str:
    if value is None or value == "":
        return "-"
    return f"{float(value) * 100:.1f}%"


def _num(value: Any, digits: int = 2) -> str:
    if value is None or value == "":
        return "-"
    return f"{float(value):.{digits}f}"


def _account_table(rows: list[dict[str, Any]]) -> list[str]:
    lines = [
        "|平台|账户|当前排名|交易|跨度|总收益|净年化|SPY年化|年化超额|最大回撤|",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        author = row.get("handle") or row.get("name") or row["investor_id"]
        lines.append(
            "|{source}|{author}|{rank}/{population}|{trades}|{days}D|{total}|{cagr}|"
            "{spy}|{excess}|{drawdown}|".format(
                source=row["source"],
                author=author,
                rank=row["current_platform_rank"],
                population=row["current_platform_population"],
                trades=row["trade_count"],
                days=row["trading_days"],
                total=_pct(row["total_return"]),
                cagr=_pct(row["annualized_return"]),
                spy=_pct(row["benchmark_annualized_return"]),
                excess=_pct(row["annualized_excess_return"]),
                drawdown=_pct(row["max_drawdown"]),
            )
        )
    return lines


def _distribution(rows: list[dict[str, Any]]) -> dict[str, Any]:
    values = sorted(
        float(row["annualized_return"])
        for row in rows
        if row.get("annualized_return") is not None
    )
    if not values:
        return {
            "count": 0,
            "median": None,
            "p25": None,
            "p75": None,
            "positive_share": None,
            "spy_outperform_share": None,
        }
    outperform = [
        row
        for row in rows
        if row.get("annualized_return") is not None
        and row.get("benchmark_annualized_return") is not None
        and float(row["annualized_return"])
        > float(row["benchmark_annualized_return"])
    ]
    return {
        "count": len(values),
        "median": statistics.median(values),
        "p25": values[len(values) // 4],
        "p75": values[(len(values) * 3) // 4],
        "positive_share": sum(value > 0 for value in values) / len(values),
        "spy_outperform_share": len(outperform) / len(values),
    }


def write_account_follow_reports(
    output_dir: str | Path,
    executable_rows: list[dict[str, Any]],
    descriptive_rows: list[dict[str, Any]],
    trade_rows: list[dict[str, Any]],
    profile: dict[str, Any],
) -> dict[str, Any]:
    report_dir = Path(output_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    executable_count = _write_csv(
        report_dir / "smart_account_follow_returns.csv",
        executable_rows,
    )
    descriptive_count = _write_csv(
        report_dir / "smart_account_follow_returns_full_history.csv",
        descriptive_rows,
    )
    trade_count = _write_csv(
        report_dir / "smart_account_follow_trades.csv",
        trade_rows,
    )

    robust = [
        row
        for row in executable_rows
        if row["coverage_status"] == "rank_eligible"
        and row.get("annualized_return") is not None
    ]
    robust.sort(key=lambda row: float(row["annualized_return"]), reverse=True)
    top = robust[:15]
    bottom = list(reversed(robust[-15:]))
    distribution = _distribution(robust)
    source_rows: list[dict[str, Any]] = []
    for source in sorted(profile["accounts_by_source"]):
        source_all = [row for row in executable_rows if row["source"] == source]
        source_robust = [row for row in robust if row["source"] == source]
        source_distribution = _distribution(source_robust)
        source_rows.append(
            {
                "source": source,
                "formal_accounts": len(source_all),
                "executable_accounts": sum(row["trade_count"] > 0 for row in source_all),
                "rank_eligible_accounts": len(source_robust),
                **source_distribution,
            }
        )

    lines = [
        "# Smart Account 逐账户跟单收益回测",
        "",
        "## 结论口径",
        "",
        f"- 当前正式 Smart Account 共 `{profile['account_count']}` 个："
        + "、".join(
            f"{source} {count} 个"
            for source, count in profile["accounts_by_source"].items()
        )
        + "。",
        f"- 其中 `{profile['executable_accounts']}` 个有可执行的历史时点合格 Call，"
        f"`{profile['rank_eligible_accounts']}` 个达到至少 10 笔交易且跨度 126 个交易日的比较门槛。",
        f"- 严格可比账户的净年化中位数为 `{_pct(distribution['median'])}`，"
        f"正年化占比 `{_pct(distribution['positive_share'])}`，"
        f"跑赢各自同期 SPY 年化的占比 `{_pct(distribution['spy_outperform_share'])}`。",
        "",
        "## 可执行口径",
        "",
        "1. 只从作者在当时已经进入该平台正式池后的 Call 开始跟随；资格读取观点发布日前最后一份历史 Score 快照。",
        "2. 观点发布后的下一交易日复权开盘执行；看多做多、看空做空。附表同时提供只做多结果。",
        "3. 同一作者同一标的只保留一个仓位：同向新判断延长周期，反向判断在下一开盘平仓并翻向，平仓或失效判断退出。",
        "4. 未说明周期按 20 个交易日；活跃标的每日等权，无观点时持有现金。",
        "5. 主结果计入每笔 10bps 完整往返成本，价格使用拆股和分红调整后的开盘/收盘价。",
        f"6. 组合从首笔可执行交易计算到 `{profile['price_end_day']}`，最后仍开放的仓位按该日收盘盯市。",
        "",
        "## 各平台覆盖",
        "",
        "|平台|正式账户|有交易|可比较|年化中位|P25|P75|正年化占比|跑赢SPY占比|",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in source_rows:
        lines.append(
            "|{source}|{formal_accounts}|{executable_accounts}|{rank_eligible_accounts}|"
            "{median}|{p25}|{p75}|{positive}|{outperform}|".format(
                source=row["source"],
                formal_accounts=row["formal_accounts"],
                executable_accounts=row["executable_accounts"],
                rank_eligible_accounts=row["rank_eligible_accounts"],
                median=_pct(row["median"]),
                p25=_pct(row["p25"]),
                p75=_pct(row["p75"]),
                positive=_pct(row["positive_share"]),
                outperform=_pct(row["spy_outperform_share"]),
            )
        )
    lines.extend(["", "## 净年化 Top 15", ""])
    lines.extend(_account_table(top))
    lines.extend(["", "## 净年化 Bottom 15", ""])
    lines.extend(_account_table(bottom))
    lines.extend(
        [
            "",
            "## 两份收益表的区别",
            "",
            "- `smart_account_follow_returns.csv` 是主结果：只使用作者当时已进入正式池后的观点，避免用未来排名决定过去何时开始跟单。",
            "- `smart_account_follow_returns_full_history.csv` 从当前正式账户在数据库中的第一条 Call 起计算，只用于描述完整历史。它包含当前作者池选择带来的幸存者偏差，不能当成当时可实现收益。",
            "- `smart_account_follow_trades.csv` 保留主结果的逐笔入场、退出、生命周期原因、原始链接和收益，可逐账户审计。",
            "",
            "## 限制",
            "",
            "- 这是规则化信号跟随组合，不是博主真实账户收益；数据库不知道其真实仓位大小、入场成交、杠杆和未公开操作。",
            "- 只计 10bps 往返成本，未计融券可得性、借券费、融资利息、税费和市场冲击。",
            "- 不足 126 个交易日或 10 笔交易的年化波动很大，已标记为 `limited` 或 `insufficient`，不参与 Top/Bottom 比较。",
            "- 不同标的日线截止日不完全一致；仓位到达该标的最后可用价格时退出，并在 CSV 的 `price_history_end_exits` 单列，不能把这类退出解释为作者主动卖出。",
            "- 当前正式榜没有雪球作者的当前 `sv_investor_score` 行，因此本次正式账户清单只包含 X、YouTube 和 Reddit；没有用历史雪球快照伪造当前正式账户。",
            "- 本报告用于检验信号，不构成收益承诺或投资建议。",
        ]
    )
    (report_dir / "smart_account_follow_report.md").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )
    summary = {
        **profile,
        "rank_eligible_distribution": distribution,
        "source_summary": source_rows,
        "output_rows": {
            "executable": executable_count,
            "descriptive": descriptive_count,
            "trades": trade_count,
        },
    }
    (report_dir / "run_manifest.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return summary
