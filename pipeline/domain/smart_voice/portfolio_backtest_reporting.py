"""CSV and Markdown reports for Smart Voice portfolio backtests."""
from __future__ import annotations

import csv
import statistics
from pathlib import Path
from typing import Any


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns: list[str] = []
    seen: set[str] = set()
    for row in rows:
        for column in row:
            if column not in seen:
                columns.append(column)
                seen.add(column)
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


def _collective_table(rows: list[dict[str, Any]]) -> list[str]:
    lines = [
        "|指标|窗口|持有|方向|交易数|暴露率|净年化(10bps)|夏普|最大回撤|SPY年化|",
        "|---|---:|---:|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "|{indicator}|{signal_window_days}D|{holding_days}D|{position_mode}|"
            "{n_trades}|{exposure}|{cagr}|{sharpe}|{drawdown}|{benchmark}|".format(
                indicator=row["indicator"],
                signal_window_days=row["signal_window_days"],
                holding_days=row["holding_days"],
                position_mode=row["position_mode"],
                n_trades=row["n_trades"],
                exposure=_pct(row["exposure_pct"]),
                cagr=_pct(row["annualized_return_10bps"]),
                sharpe=_num(row["sharpe_10bps"]),
                drawdown=_pct(row["max_drawdown_10bps"]),
                benchmark=_pct(row["benchmark_annualized_return"]),
            )
        )
    return lines


def _author_table(rows: list[dict[str, Any]]) -> list[str]:
    lines = [
        "|作者|当前SV|交易数|净年化(10bps)|夏普|最大回撤|命中率|",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        author = row.get("handle") or row.get("name") or row["investor_id"]
        lines.append(
            "|{author}|{sv}|{trades}|{cagr}|{sharpe}|{drawdown}|{hit}|".format(
                author=author,
                sv=_num(row.get("current_sv"), 1),
                trades=row["n_trades"],
                cagr=_pct(row["annualized_return_10bps"]),
                sharpe=_num(row["sharpe_10bps"]),
                drawdown=_pct(row["max_drawdown_10bps"]),
                hit=_pct(row["trade_hit_rate_10bps"]),
            )
        )
    return lines


def _rank_strategy_table(rows: list[dict[str, Any]]) -> list[str]:
    labels = {
        "top_follow": "跟随头部",
        "bottom_contrarian": "反向底部",
        "top_bottom_divergence": "头尾背离",
    }
    lines = [
        "|策略|分位|窗口|持有|交易数|净年化(10bps)|夏普|最大回撤|命中率|",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "|{strategy}|{rank}%|{window}D|{holding}D|{trades}|{cagr}|"
            "{sharpe}|{drawdown}|{hit}|".format(
                strategy=labels.get(row["strategy"], row["strategy"]),
                rank=row["rank_band_pct"],
                window=row["signal_window_days"],
                holding=row["holding_days"],
                trades=row["n_trades"],
                cagr=_pct(row["annualized_return_10bps"]),
                sharpe=_num(row["sharpe_10bps"]),
                drawdown=_pct(row["max_drawdown_10bps"]),
                hit=_pct(row["trade_hit_rate_10bps"]),
            )
        )
    return lines


def _rank_robustness_table(rows: list[dict[str, Any]]) -> list[str]:
    labels = {
        "top_follow": "跟随头部",
        "bottom_contrarian": "反向底部",
        "top_bottom_divergence": "头尾背离",
    }
    lines = [
        "|策略|分位|合格参数组|年化P25|年化中位|年化P75|正年化占比|",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for strategy in ("top_follow", "bottom_contrarian", "top_bottom_divergence"):
        for rank_band in (10, 25):
            values = sorted(
                float(row["annualized_return_10bps"])
                for row in rows
                if row["strategy"] == strategy
                and row["rank_band_pct"] == rank_band
                and row["position_mode"] == "long_short"
                and row["n_trades"] >= 20
                and row["trading_days"] >= 126
                and row["annualized_return_10bps"] is not None
            )
            if not values:
                continue
            lines.append(
                "|{strategy}|{rank}%|{count}|{p25}|{median}|{p75}|{positive}|".format(
                    strategy=labels[strategy],
                    rank=rank_band,
                    count=len(values),
                    p25=_pct(values[len(values) // 4]),
                    median=_pct(statistics.median(values)),
                    p75=_pct(values[(len(values) * 3) // 4]),
                    positive=_pct(sum(value > 0 for value in values) / len(values)),
                )
            )
    return lines


def write_portfolio_backtest_reports(
    report_dir: Path,
    collective_rows: list[dict[str, Any]],
    author_rows: list[dict[str, Any]],
    rank_strategy_rows: list[dict[str, Any]],
    profile: dict[str, Any],
) -> dict[str, int]:
    report_dir.mkdir(parents=True, exist_ok=True)
    collective_count = _write_csv(
        report_dir / "x_sv_collective_strategy_annualized.csv",
        collective_rows,
    )
    author_count = _write_csv(
        report_dir / "x_author_annualized.csv",
        author_rows,
    )
    canonical_rows = [
        row for row in author_rows if row["holding_policy"] == "call_horizon_or_20D"
    ]
    canonical_count = _write_csv(
        report_dir / "x_author_annualized_canonical.csv",
        canonical_rows,
    )
    rank_strategy_count = _write_csv(
        report_dir / "x_sv_rank_event_strategy_annualized.csv",
        rank_strategy_rows,
    )

    robust_collective = [
        row
        for row in collective_rows
        if row["n_trades"] >= 20 and row["trading_days"] >= 126
    ]
    robust_collective.sort(
        key=lambda row: (
            row["annualized_return_10bps"]
            if row["annualized_return_10bps"] is not None
            else float("-inf")
        ),
        reverse=True,
    )
    standard = [
        row
        for row in collective_rows
        if row["indicator"] == "weighted_net"
        and row["signal_window_days"] == 7
        and row["holding_days"] == 20
        and row["position_mode"] == "long_short"
    ]

    ranked_authors = [
        row
        for row in author_rows
        if row["eligibility_mode"] == "point_in_time_qualified"
        and row["holding_policy"] == "call_horizon_or_20D"
        and row["rank_eligible"]
    ]
    ranked_authors.sort(
        key=lambda row: (
            row["annualized_return_10bps"]
            if row["annualized_return_10bps"] is not None
            else float("-inf")
        ),
        reverse=True,
    )
    top_authors = ranked_authors[:10]
    bottom_authors = list(reversed(ranked_authors[-10:]))

    lines = [
        "# X Smart Voice 年化回测",
        "",
        "## 数据范围",
        "",
        f"- X actionable Call：{profile['actionable_calls']:,} 条，{profile['call_authors']:,} 位作者。",
        f"- X 已结算周期结果：{profile['settled_rows']:,} 条。",
        f"- 历史时点正式 SV 作者：{profile['asof_authors']:,} 位。",
        f"- 价格：{profile['price_min_day']} 至 {profile['price_max_day']}，"
        f"{profile['price_tickers']:,} 个标的。",
        "",
        "## 计算口径",
        "",
        "- 集体策略只使用 X，并使用观点发布当日的历史时点平台 SV 排名，不回填当前排名。",
        "- 信号后的下一交易日调整开盘入场；同一策略同一标的不重叠加仓；活跃标的等权；无信号时持有现金。",
        "- 分别计算多空、只做多、只做空，以及 1/5/20/60/90/180 个交易日持有期。",
        "- 年化以 252 个交易日计算；10bps 和 25bps 是每笔完整往返成本。",
        "- 作者的 `all_actionable` 是描述性历史；`point_in_time_qualified` 只跟随作者当时已进入正式 SV 池后的帖子，属于可执行口径。",
        "- 每位作者的代表年化按帖子自己的 `horizon_bucket` 持有；未说明周期的帖子统一按 20 个交易日。",
        "- 作者排名要求当前满足 X 正式池门槛、至少 10 笔非重叠交易且回测跨度不少于 126 个交易日。",
        "",
        "## 标准场景",
        "",
    ]
    lines.extend(_collective_table(standard))
    lines.extend(
        [
            "",
            "## 净年化最高的稳健场景",
            "",
            "以下仅保留至少 20 笔交易、跨度至少 126 个交易日的场景。"
            "大量参数组合会产生数据挖掘偏差，不能把最高一行直接视为未来预期。",
            "",
        ]
    )
    lines.extend(_collective_table(robust_collective[:15]))
    lines.extend(["", "## 作者年化 Top 10", ""])
    lines.extend(_author_table(top_authors))
    lines.extend(["", "## 作者年化 Bottom 10", ""])
    lines.extend(_author_table(bottom_authors))
    lines.extend(
        [
            "",
            "## 解释限制",
            "",
            "- 当前只有约一年 X 历史；CAGR 对短样本和极端行情敏感。",
            "- 集体策略是历史时点无泄漏；作者全帖子口径仍是对同一批历史观点的描述，不是独立样本外验证。",
            "- 未计入滑点、借券可用性、融资利息、税费和盘中成交差异。",
            "- 该报告用于研究 SV 信号，不构成投资建议。",
        ]
    )
    (report_dir / "x_sv_annualized_report.md").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )

    baseline_rank = [
        row
        for row in rank_strategy_rows
        if row["signal_window_days"] == 7
        and row["holding_days"] == 20
        and row["position_mode"] == "long_short"
    ]
    baseline_rank.sort(key=lambda row: (row["rank_band_pct"], row["strategy"]))
    top10_holding = [
        row
        for row in rank_strategy_rows
        if row["rank_band_pct"] == 10
        and row["signal_window_days"] == 7
        and row["position_mode"] == "long_short"
    ]
    top10_holding.sort(key=lambda row: (row["strategy"], row["holding_days"]))
    best_by_strategy: list[dict[str, Any]] = []
    for strategy in ("top_follow", "bottom_contrarian", "top_bottom_divergence"):
        candidates = [
            row
            for row in rank_strategy_rows
            if row["strategy"] == strategy
            and row["position_mode"] == "long_short"
            and row["n_trades"] >= 20
            and row["trading_days"] >= 126
            and row["annualized_return_10bps"] is not None
        ]
        candidates.sort(
            key=lambda row: row["annualized_return_10bps"],
            reverse=True,
        )
        best_by_strategy.extend(candidates[:1])
    rank_lines = [
        "# X SV 头部、底部与背离事件年化",
        "",
        "三类事件均使用观点发布当日的平台内历史排名：",
        "",
        "- `跟随头部`：头部作者达到至少 2 人且 65% 同向共识，按其方向交易。",
        "- `反向底部`：底部作者达到同样门槛，交易其相反方向。",
        "- `头尾背离`：头部和底部均达到门槛且方向相反，跟随头部方向。",
        "",
        "统一采用下一交易日调整开盘入场、同标的不重叠、活跃持仓等权、"
        "空窗持有现金和每笔 10bps 完整往返成本。",
        "",
        "## 标准 7D 信号窗口、20D 持有",
        "",
    ]
    rank_lines.extend(_rank_strategy_table(baseline_rank))
    rank_lines.extend(
        [
            "",
            "## Top/Bottom 10% 在不同持有期下",
            "",
        ]
    )
    rank_lines.extend(_rank_strategy_table(top10_holding))
    rank_lines.extend(
        [
            "",
            "## 每类策略历史最优稳健场景",
            "",
            "只在至少 20 笔交易且跨度不少于 126 个交易日的组合中选择；"
            "该表仍存在参数搜索偏差，不能作为未来收益承诺。",
            "",
        ]
    )
    rank_lines.extend(_rank_strategy_table(best_by_strategy))
    rank_lines.extend(
        [
            "",
            "## 参数稳健性",
            "",
            "统计所有至少 20 笔交易且跨度不少于 126 个交易日的多空参数组。"
            "中位数比单个历史最优值更适合判断信号是否稳定。",
            "",
        ]
    )
    rank_lines.extend(_rank_robustness_table(rank_strategy_rows))
    rank_lines.extend(
        [
            "",
            "## 限制",
            "",
            "- 当前历史只有约一年，且覆盖的是已完成结构化和价格结算的 X Call。",
            "- 头部和底部定义为当时的平台内正式池分位，不能使用当前榜单回填。",
            "- 未计入盘中滑点、借券费、融资利率、税费和无法成交的极端情况。",
        ]
    )
    (report_dir / "x_sv_rank_event_strategy_report.md").write_text(
        "\n".join(rank_lines) + "\n",
        encoding="utf-8",
    )
    return {
        "collective_rows": collective_count,
        "author_rows": author_count,
        "canonical_author_rows": canonical_count,
        "rank_strategy_rows": rank_strategy_count,
        "markdown_reports": 2,
    }
