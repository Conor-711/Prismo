"""Markdown reporting for the leakage-free product signal backtest."""
from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Sequence

from .product_signal_backtest import ProductSignalEvent


SIGNAL_LABELS = {
    "smart_consensus": "聪明共识",
    "smart_alpha_ui": "聪明阿尔法账户分支（当前规则）",
    "smart_alpha_pure": "聪明阿尔法账户分支（严格语义）",
}


def _pct(value: object, digits: int = 2) -> str:
    if value is None:
        return "-"
    return f"{float(value) * 100:.{digits}f}%"


def _summary_row(
    rows: Sequence[dict[str, object]],
    signal_type: str,
    horizon: int,
    sample: str = "all_events",
) -> dict[str, object]:
    return next(
        row
        for row in rows
        if row["sample"] == sample
        and row["signal_type"] == signal_type
        and int(row["horizon_sessions"]) == horizon
    )


def _main_table(rows: Sequence[dict[str, object]], sample: str) -> list[str]:
    output = [
        "| 信号 | 持有期 | 样本 / SPY样本 | 方向命中率 | 扣 10bp 命中率 | 平均方向收益 | 中位数 | 相对 SPY 超额 | 超额 95% CI |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for signal_type in ("smart_consensus", "smart_alpha_ui", "smart_alpha_pure"):
        for horizon in (1, 5, 20, 60):
            row = _summary_row(rows, signal_type, horizon, sample)
            interval = f"{_pct(row['mean_excess_ci_low'])} 至 {_pct(row['mean_excess_ci_high'])}"
            output.append(
                "| {label} | {horizon}D | {n} | {hit} | {net_hit} | {mean} | {median} | {excess} | {interval} |".format(
                    label=SIGNAL_LABELS[signal_type],
                    horizon=horizon,
                    n=f"{row['n']} / {row['benchmark_n']}",
                    hit=_pct(row["raw_match_rate"]),
                    net_hit=_pct(row["net_match_rate_10bps"]),
                    mean=_pct(row["mean_directional_return"]),
                    median=_pct(row["median_directional_return"]),
                    excess=_pct(row["mean_directional_excess"]),
                    interval=interval,
                )
            )
    return output


def _subgroup_table(
    rows: Sequence[dict[str, object]],
    *,
    signal_type: str,
    dimension: str,
    horizon: int = 5,
) -> list[str]:
    selected = [
        row
        for row in rows
        if row["sample"] == "all_events"
        and row["signal_type"] == signal_type
        and int(row["horizon_sessions"]) == horizon
        and row["dimension"] == dimension
    ]
    output = [
        "| 分组 | 样本 / SPY样本 | 命中率 | 平均方向收益 | 中位数 | 相对 SPY 超额 | 超额 95% CI |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in selected:
        output.append(
            "| {bucket} | {n} | {hit} | {mean} | {median} | {excess} | {low} 至 {high} |".format(
                bucket=row["bucket"],
                n=f"{row['n']} / {row['benchmark_n']}",
                hit=_pct(row["raw_match_rate"]),
                mean=_pct(row["mean_directional_return"]),
                median=_pct(row["median_directional_return"]),
                excess=_pct(row["mean_directional_excess"]),
                low=_pct(row["mean_excess_ci_low"]),
                high=_pct(row["mean_excess_ci_high"]),
            )
        )
    return output


def write_product_signal_report(
    path: Path,
    *,
    start_day: str,
    end_day: str,
    events: Sequence[ProductSignalEvent],
    summary: Sequence[dict[str, object]],
    subgroups: Sequence[dict[str, object]],
    coverage: dict[str, object],
) -> None:
    counts = Counter(event.signal_type for event in events)
    mixed = Counter(event.signal_type for event in events if event.direction == "mixed")
    alpha_ui = [event for event in events if event.signal_type == "smart_alpha_ui"]
    overlap_count = sum(event.overlaps_consensus for event in alpha_ui)
    overlap_rate = overlap_count / len(alpha_ui) if alpha_ui else 0
    first_event_day = min(event.signal_day for event in events)
    last_event_day = max(event.signal_day for event in events)
    consensus_5d = _summary_row(summary, "smart_consensus", 5)
    consensus_60d = _summary_row(summary, "smart_consensus", 60)
    alpha_ui_5d = _summary_row(summary, "smart_alpha_ui", 5)
    alpha_pure_5d = _summary_row(summary, "smart_alpha_pure", 5)

    lines = [
        "# 聪明共识与聪明阿尔法一年无前视回测",
        "",
        f"回测区间：`{start_day}` 至 `{end_day}`。报告衡量信号出现后 1、5、20、60 个交易日的方向收益与相对 SPY 超额收益。",
        "",
        "## 结论",
        "",
        "**当前两类信号都未通过作为直接交易信号的验证。** 它们可以继续作为研究与发现入口，但现阶段不应仅凭卡片出现就触发交易。",
        "",
        "本报告中的一年聪明阿尔法结果特指 **Smart Account 分支**。Smart Money 分支缺少一年历史快照，不能在无前视条件下回填。",
        "",
        f"- 聪明共识 5 日共有 {consensus_5d['n']} 个可结算方向事件，命中率 {_pct(consensus_5d['raw_match_rate'])}，平均方向收益 {_pct(consensus_5d['mean_directional_return'])}，相对 SPY 超额 {_pct(consensus_5d['mean_directional_excess'])}。其 ticker 聚类 bootstrap 95% 区间为 {_pct(consensus_5d['mean_excess_ci_low'])} 至 {_pct(consensus_5d['mean_excess_ci_high'])}，整体偏负。",
        f"- 当前 UI 版聪明阿尔法 5 日命中率 {_pct(alpha_ui_5d['raw_match_rate'])}，但平均方向收益仍为 {_pct(alpha_ui_5d['mean_directional_return'])}、相对 SPY 超额 {_pct(alpha_ui_5d['mean_directional_excess'])}。命中次数略多不等于有正期望，亏损事件的幅度更大。",
        f"- 排除已有共识后的纯阿尔法 5 日命中率 {_pct(alpha_pure_5d['raw_match_rate'])}、平均方向收益 {_pct(alpha_pure_5d['mean_directional_return'])}、相对 SPY 超额 {_pct(alpha_pure_5d['mean_directional_excess'])}，置信区间跨越 0，接近随机。",
        f"- 聪明共识 60 日平均方向收益虽为 {_pct(consensus_60d['mean_directional_return'])}，但中位数为 {_pct(consensus_60d['median_directional_return'])}，超额收益区间很宽（{_pct(consensus_60d['mean_excess_ci_low'])} 至 {_pct(consensus_60d['mean_excess_ci_high'])}），结果由少数极端上涨标的驱动，不能视为稳定能力。",
        f"- 当前 UI 版阿尔法事件中有 {overlap_count}/{len(alpha_ui)}（{_pct(overlap_rate, 1)}）在当日已经存在活跃聪明共识，和“共识形成前发现”的产品语义不一致。",
        "",
        "## 信号复刻",
        "",
        "### 聪明共识",
        "",
        "- 使用过去 30 个自然日内的可执行 Call。",
        "- 作者必须在 Call 发布当日属于对应平台历史时点 Top 25%。",
        "- 每个标的保留每位作者最新一条 Call，至少 2 位不同作者，最多 5 位。",
        "- 仅回测当日新 Call 改变首页可见共识包的时点，避免把同一静态状态每天重复计算。",
        "- 多空票数相同记为 mixed，不强行赋予方向，也不进入方向收益统计。",
        "",
        "### 聪明阿尔法",
        "",
        "- 使用过去 30 个自然日内、带原始证据链接的 Top 10% 作者 Call。",
        "- 只接受首次、加强、反转三类生命周期，每个标的最多 2 位作者。",
        "- `smart_alpha_ui` 复刻当前 UI 的每日最高优先级 Smart Account 机会。历史用户持仓不可重建，因此没有执行个性化持仓排除。",
        "- `smart_alpha_pure` 额外排除当日已经形成聪明共识的标的，用于检验“共识前发现”这一严格语义。",
        "",
        "## 全部事件",
        "",
        *_main_table(summary, "all_events"),
        "",
        "`方向收益`已按看多/看空翻转；`相对 SPY 超额`同样按信号方向计算。样本列同时列出方向收益样本与具备同日 SPY 基准的样本；10bp 为一次完整进出成本。",
        "",
        "## 非重叠样本",
        "",
        "同一信号、标的与持有期在上一笔退出前不再开新样本，用于降低连续 Call 对统计量的重复放大。",
        "",
        *_main_table(summary, "non_overlapping"),
        "",
        "## 稳定性检查",
        "",
        "### 聪明共识 5 日：多空方向",
        "",
        *_subgroup_table(subgroups, signal_type="smart_consensus", dimension="direction"),
        "",
        "看空共识在 1 至 5 日有一定短期表现，但在 20 至 60 日反转；不能把短期结果外推到中长期。",
        "",
        "### 聪明共识 5 日：一致程度",
        "",
        *_subgroup_table(subgroups, signal_type="smart_consensus", dimension="agreement"),
        "",
        "一致票数更多没有带来更高收益，说明当前规则主要描述观点状态，并未提取可交易的边际变化。",
        "",
        "### 聪明共识 5 日：前后半年",
        "",
        *_subgroup_table(subgroups, signal_type="smart_consensus", dimension="period"),
        "",
        "### 聪明阿尔法 5 日：前后半年",
        "",
        *_subgroup_table(subgroups, signal_type="smart_alpha_ui", dimension="period"),
        "",
        "阿尔法前半段的正表现未在后半段延续，存在明显时段不稳定性。",
        "",
        "## 前视偏差控制",
        "",
        "1. 作者排名不是使用今天的最终排名回填历史。每条 Call 只连接其发布日期的 `sv_investor_score_asof` 快照。",
        "2. 该快照的底层生成条件是 `settlement.exit_day < signal_day`；信号日当天及之后才完成的结果不会进入作者分数。",
        "3. 信号在发布日结束后才视为已知，统一在下一可交易日的复权开盘价入场，不使用信号日收盘价成交。",
        "4. 退出使用第 1、5、20、60 个交易日复权收盘价；基准使用同一入场/退出时点的 SPY。",
        "5. 同时给出全部事件与同标的非重叠事件，置信区间按 ticker 聚类 bootstrap，降低单一热门股票与密集发帖造成的伪精度。",
        "6. 规则、阈值和持有期均来自当前产品定义，不根据本次回测结果反向调参。",
        "",
        "## 数据边界",
        "",
        f"- 可回测 Call 总表覆盖 `{coverage['calls']['first_day']}` 至 `{coverage['calls']['last_day']}`；历史时点作者排名覆盖 `{coverage['scores']['first_day']}` 至 `{coverage['scores']['last_day']}`。因此选择完整可审计的一年 `{start_day}` 至 `{end_day}`。",
        f"- SPY 基准已补齐至 `{coverage['benchmark_prices']['last_day']}`。20/60 日结果只纳入截至运行日已经到期的事件，尚未走满持有期的尾部信号不结算，因此各持有期样本数不同。",
        f"- 共生成聪明共识 {counts['smart_consensus']} 次（其中 mixed {mixed['smart_consensus']} 次）、当前 UI 聪明阿尔法 {counts['smart_alpha_ui']} 次、纯阿尔法 {counts['smart_alpha_pure']} 次。",
        f"- 一年观察窗口内，首个满足完整规则的产品事件出现在 `{first_event_day}`，最后一个事件为 `{last_event_day}`；窗口开始后的无事件日期不会被伪造为信号。",
        f"- Smart Money 钱包评分只有 {coverage['wallet_scores']['days']} 个快照日（`{coverage['wallet_scores']['first_day']}` 至 `{coverage['wallet_scores']['last_day']}`），链上成交仅覆盖 `{coverage['wallet_fills']['first_day']}` 至 `{coverage['wallet_fills']['last_day']}`。因此本报告不能提供一年 Smart Money 阿尔法结论；强行回填会产生生存偏差与前视偏差。",
        "- 当前 UI 会按用户持仓排除阿尔法候选，但历史持仓不可用。本报告衡量的是公共信号本身，不是某个用户过去实际能看到的个性化序列。",
        "- 多平台 Call 的历史采集完整度并非每天完全一致，结果只代表数据库内可观测样本。",
        "",
        "## 产品与算法建议",
        "",
        "1. 暂时把聪明共识定位为“高排名账户正在形成什么判断”，不要标注为已经验证的买卖信号。",
        "2. 聪明阿尔法应在代码层排除活跃共识标的，否则名称和规则不一致。",
        "3. 下一版重点回测状态变化而非静态多空：新进入共识、净方向突变、首次出现反对者、Top 作者反转、共识扩散速度。",
        "4. 预先冻结下一版规则，再用本次区间之后的数据做真正 holdout；达到正超额、收益中位数为正且前后阶段一致后，再强化 Trade CTA。",
        "5. Smart Money 至少积累 6 至 12 个月不可变快照后，再按同一无前视框架单独回测，不能用当前地址排名回填历史。",
        "",
        "## 可复现文件",
        "",
        "- `smart_signal_events.csv`：信号事件与组成作者。",
        "- `smart_signal_outcomes.csv`：每个事件在各持有期的入场、退出、收益、MFE/MAE。",
        "- `smart_signal_summary.csv`：总体与非重叠样本统计。",
        "- `smart_signal_subgroups.csv`：方向、人数、一致性、时段、共识重叠分组。",
        "- `run_manifest.json`：运行区间和数据库覆盖审计。",
        "",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")
