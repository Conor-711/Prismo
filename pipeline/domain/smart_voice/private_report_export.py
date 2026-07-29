"""File exporters for the Private Smart Voice MVP report."""
from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any


def render_markdown(report: dict[str, Any]) -> str:
    channel = report["channel"]
    score = report["score"]
    data = report["data_quality"]
    performance = report["performance"]
    portfolio = report["portfolio_backtest"]["base"]
    lines = [
        f"# Private Smart Voice MVP: @{channel['handle']}",
        "",
        f"- 频道：{channel['title']}",
        f"- 公开历史：{channel['first_message_at'][:10]} 至 {channel['last_message_at'][:10]}",
        f"- 已保存消息：{channel['message_count']:,}",
        f"- 归属作者的可结算 Call：{data['settled_primary_calls']}",
        f"- Private SE/SV：**{score['sv']}**（{score['confidence']}）",
        f"- 公域标尺位置：从高到低前 {score['reference_percentile']:.1f}%，"
        f"参考作者 {score['calibration']['population']} 位",
        "",
        "## 评分解释",
        "",
        score["explanation_zh"],
        "",
        "## 整体结算表现",
        "",
        f"- 相对 SPY 方向命中率：{performance['spy_excess_hit_rate'] * 100:.1f}%"
        f"（{performance['calls']} 条）",
        f"- 平均 / 中位方向超额："
        f"{performance['mean_directional_spy_excess_pct']:+.2f}% / "
        f"{performance['median_directional_spy_excess_pct']:+.2f}%",
        f"- 平均盈利 / 平均亏损："
        f"{performance['average_positive_excess_pct']:+.2f}% / "
        f"{performance['average_negative_excess_pct']:+.2f}%",
        f"- 盈亏比 / 利润因子：{performance['payoff_ratio']:.2f} / "
        f"{performance['profit_factor']:.2f}",
        f"- 相对行业 ETF 方向命中率："
        f"{performance['industry_excess_hit_rate'] * 100:.1f}%"
        f"（{performance['industry_calls']} 条）",
        f"- 方向结构：看多 {performance['bull_calls']} / 看空 {performance['bear_calls']}",
        f"- 投资风格：{report['style']['dominant']}；样本年份分布 "
        + "，".join(
            f"{year}: {count}"
            for year, count in performance["calls_by_year"].items()
        ),
        "",
        "## 跟随观点组合回测",
        "",
        f"- 回测区间：{portfolio['startDay']} 至 {portfolio['endDay']}；"
        f"交易 {portfolio['tradeCount']} 次，组合活跃率 "
        f"{portfolio['exposurePct'] * 100:.1f}%。",
        f"- 累计收益 / 年化收益：{portfolio['totalReturn'] * 100:+.1f}% / "
        f"{portfolio['annualizedReturn'] * 100:+.1f}%。",
        f"- 同期 SPY 累计 / 年化：{portfolio['benchmarkTotalReturn'] * 100:+.1f}% / "
        f"{portfolio['benchmarkAnnualizedReturn'] * 100:+.1f}%；"
        f"年化超额 {portfolio['annualizedExcessReturn'] * 100:+.1f}%。",
        f"- 年化波动 / Sharpe / Sortino："
        f"{portfolio['annualizedVolatility'] * 100:.1f}% / "
        f"{portfolio['sharpe']:.2f} / {portfolio['sortino']:.2f}。",
        f"- 最大回撤：{portfolio['maxDrawdown'] * 100:.1f}%"
        f"（{portfolio['drawdownPeakDay']} 至 {portfolio['drawdownTroughDay']}）；"
        f"Beta {portfolio['beta']:.2f}。",
        "- 口径：下一交易日复权开盘入场；同一标的只保留最新有效方向；"
        "活跃标的每日等权；无信号时持有现金；计入单次往返 10 bps 成本；"
        "不含税费、融券约束和市场冲击。",
        "",
        "| 年份 | 跟随组合 | SPY |",
        "|---|---:|---:|",
    ]
    for item in portfolio["yearReturns"]:
        lines.append(
            f"| {item['year']} | {item['return'] * 100:+.1f}% | "
            f"{item['benchmarkReturn'] * 100:+.1f}% |"
        )
    lines.extend(
        [
        "",
        "## 主要标的",
        "",
        "| 标的 | 已结算 | 多 / 空 | 命中率 | 平均方向超额 | 最新方向 |",
        "|---|---:|---:|---:|---:|---|",
        ]
    )
    for item in report["ticker_report"][:20]:
        lines.append(
            f"| {item['ticker']} | {item['settled_calls']} | "
            f"{item['bull_calls']} / {item['bear_calls']} | "
            f"{item['hit_rate'] * 100:.1f}% | "
            f"{item['mean_directional_spy_excess_pct']:+.2f}% | "
            f"{item['latest_direction']} |"
        )
    lines.extend(["", "## 最佳证据案例", ""])
    for index, case in enumerate(report["best_cases"], 1):
        lines.append(
            f"{index}. **{case['ticker']} {case['direction']} · {case['horizon']}** "
            f"方向超额 {case['directional_spy_excess_pct']:+.2f}%："
            f"{case['summary_zh'] or case['evidence']} "
            f"([原帖]({case['url']}))"
        )
    lines.extend(["", "## 失败证据案例", ""])
    for index, case in enumerate(report["weak_cases"], 1):
        lines.append(
            f"{index}. **{case['ticker']} {case['direction']} · {case['horizon']}** "
            f"方向超额 {case['directional_spy_excess_pct']:+.2f}%："
            f"{case['summary_zh'] or case['evidence']} "
            f"([原帖]({case['url']}))"
        )
    lines.extend(
        [
            "",
            "## 口径与限制",
            "",
            "- 只纳入频道自身发布且可归属给频道主的公开消息；转发内容不计入作者能力。",
            "- 使用与公域 Smart Voice 相同的 Call 抽取、下一交易日入场、SPY/行业 ETF 积分路径、时间衰减、样本置信度与集中度上限。",
            "- 单一 Telegram 作者无法形成平台内相对分布，因此分数使用现有公域合格作者作为固定标尺；这不是 Telegram 平台排名。",
            "- 这是历史证据评估，不是实时荐股或收益承诺。",
            "",
        ]
    )
    return "\n".join(lines)


def write_report_exports(
    report: dict[str, Any],
    output_dir: str | Path,
) -> None:
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (out / "report.md").write_text(render_markdown(report), encoding="utf-8")
    cases = report["calls"]
    if not cases:
        return
    with (out / "calls.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(cases[0].keys()))
        writer.writeheader()
        writer.writerows(cases)
