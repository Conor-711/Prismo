"""Generate balanced success/failure case studies with original evidence links."""
from __future__ import annotations

import collections
import csv
from pathlib import Path
from typing import Any

INDICATOR_LABELS = {
    "weighted_net": "加权净强度",
    "author_net": "作者净人数",
    "author_net_shift": "作者净人数突变",
    "high_low_divergence": "高低 SV 分歧",
}


def _load(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def _number(value: str | None) -> float | None:
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


def _pct(value: str | None) -> str:
    number = _number(value)
    return "-" if number is None else f"{number * 100:+.2f}%"


def _price(value: str | None) -> str:
    number = _number(value)
    return "-" if number is None else f"${number:,.2f}"


def _text(value: str | None, limit: int = 180) -> str:
    clean = " ".join(str(value or "").split()).replace("|", "\\|")
    return clean if len(clean) <= limit else clean[: limit - 1] + "..."


def _select_distinct_tickers(rows: list[dict[str, str]], *, success: bool, limit: int) -> list[dict[str, str]]:
    def matches(row: dict[str, str]) -> bool:
        value = _number(row["directional_excess_pct"]) or 0
        return value > 0 if success else value < 0

    eligible = [
        row for row in rows
        if matches(row)
    ]
    eligible.sort(
        key=lambda row: _number(row["directional_excess_pct"]) or 0,
        reverse=success,
    )
    selected: list[dict[str, str]] = []
    tickers: set[str] = set()
    for row in eligible:
        if row["ticker"] in tickers:
            continue
        selected.append(row)
        tickers.add(row["ticker"])
        if len(selected) >= limit:
            break
    return selected


def _pick_evidence(rows: list[dict[str, str]], indicator: str, limit: int = 4) -> list[dict[str, str]]:
    linked = [row for row in rows if row.get("url")]
    linked.sort(
        key=lambda row: (
            row.get("evidence_window") != "current",
            -abs(_number(row.get("weighted_contribution")) or 0),
            row.get("created_at") or "",
        )
    )
    if indicator == "high_low_divergence":
        selected: list[dict[str, str]] = []
        for band in ("top", "bottom"):
            authors: set[str] = set()
            for row in [item for item in linked if item["band"] == band]:
                if row["author"] in authors:
                    continue
                selected.append(row)
                authors.add(row["author"])
                if len(authors) >= 2:
                    break
        return selected[:limit]
    if indicator == "author_net_shift":
        selected = []
        for period, cap in (("current", 3), ("previous", 2)):
            authors = set()
            for row in [item for item in linked if item["evidence_window"] == period]:
                if row["author"] in authors:
                    continue
                selected.append(row)
                authors.add(row["author"])
                if len(authors) >= cap:
                    break
        return selected[:limit + 1]
    selected = []
    authors = set()
    for row in linked:
        if row["author"] in authors:
            continue
        selected.append(row)
        authors.add(row["author"])
        if len(selected) >= limit:
            break
    return selected


def _evidence_line(row: dict[str, str]) -> str:
    summary = _text(row.get("summary_zh") or row.get("original_evidence"))
    rank = f"{row['platform_rank_no']}/{row['platform_population']}"
    period = "当前窗" if row["evidence_window"] == "current" else "前一窗"
    flags = f"；审计：`{row['audit_flags']}`" if row.get("audit_flags") else ""
    return (
        f"- {period} · {row['band'].upper()} · {row['source']} · **{_text(row['author'], 60)}** "
        f"({row['direction']}，平台排名 {rank})：{summary} "
        f"[原帖/视频]({row['url']}){flags}"
    )


def _case_section(index: int, outcome: str, row: dict[str, str], evidence: list[dict[str, str]]) -> list[str]:
    direction = "看多" if row["direction"] == "bull" else "看空"
    flags = row.get("audit_flags") or "无"
    lines = [
        f"### {index}. {row['ticker']} · {outcome} · {direction}",
        "",
        f"- 事件：`{row['event_id']}`",
        f"- 信号日 `{row['signal_day']}`；入场 `{row['entry_day']}` {_price(row['entry_price'])}；"
        f"退出 `{row['exit_day']}` {_price(row['exit_price'])}。",
        f"- 20D 方向收益 **{_pct(row['directional_return_pct'])}**；相对 SPY 超额 "
        f"**{_pct(row['directional_excess_pct'])}**。",
        f"- Top 加权净强度 `{(_number(row['top_net']) or 0):+.2f}`；Bottom `{(_number(row['bottom_net']) or 0):+.2f}`；"
        f"作者净人数 `{row['top_author_net']}`，前期 `{row['previous_top_author_net']}`，"
        f"变化 `{row['author_net_delta']}` / `{(_number(row['author_net_shift_pct']) or 0):+.1f}%`。",
        f"- 事件审计标记：`{flags}`。",
        "",
        "实际参与计算的证据：",
        "",
    ]
    lines.extend(_evidence_line(item) for item in evidence)
    lines.append("")
    return lines


def write_indicator_casebook(report_dir: str | Path, per_side: int = 5) -> int:
    report_dir = Path(report_dir)
    results = [
        row for row in _load(report_dir / "sv_indicator_event_results.csv")
        if row["source_scope"] == "all"
        and row["window_days"] == "7"
        and row["outcome_horizon"] == "20D"
        and row["status"] == "settled"
        and row["directional_excess_pct"]
    ]
    selected: list[tuple[str, str, dict[str, str]]] = []
    for indicator in INDICATOR_LABELS:
        indicator_rows = [row for row in results if row["indicator"] == indicator]
        selected.extend(
            (indicator, "成功", row)
            for row in _select_distinct_tickers(indicator_rows, success=True, limit=per_side)
        )
        selected.extend(
            (indicator, "失败", row)
            for row in _select_distinct_tickers(indicator_rows, success=False, limit=per_side)
        )
    selected_ids = {row["event_id"] for _, _, row in selected}
    evidence: dict[str, list[dict[str, str]]] = collections.defaultdict(list)
    with (report_dir / "sv_indicator_event_evidence_compact.csv").open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            if row["event_id"] in selected_ids and row["used_by_indicator"] == "1":
                evidence[row["event_id"]].append(row)

    lines = [
        "# Smart Voice 成功/失败证据案例集",
        "",
        f"固定口径：全平台合并、7 个自然日信号窗口、20 个交易日持有。每个指标分别选择相对 SPY 超额最好和最差的 {per_side} 个不同标的，共 {len(INDICATOR_LABELS) * per_side * 2} 个案例。所有链接均来自实际参与该事件计算的 Call。",
        "",
        "> 这是极端案例审计集，不代表平均收益；总体统计请同时查看 `sv_indicator_backtest_methodology.md`。",
        "",
    ]
    case_count = 0
    for indicator in INDICATOR_LABELS:
        lines.extend((f"## {INDICATOR_LABELS[indicator]}", ""))
        for _, outcome, row in [item for item in selected if item[0] == indicator]:
            case_count += 1
            picked = _pick_evidence(evidence.get(row["event_id"], []), indicator)
            lines.extend(_case_section(case_count, outcome, row, picked))
    (report_dir / "sv_indicator_casebook.md").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return case_count
