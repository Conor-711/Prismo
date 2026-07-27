"""CSV and Markdown exports for vertical sub-SV backtests."""
from __future__ import annotations

import csv
import sqlite3
from pathlib import Path
from typing import Any, Iterable


def _write_rows(path: Path, rows: Iterable[sqlite3.Row], columns: list[str]) -> int:
    materialized = list(rows)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(columns)
        writer.writerows(tuple(row[column] for column in columns) for row in materialized)
    return len(materialized)


def _pct(value: Any) -> str:
    return "-" if value is None else f"{float(value) * 100:.1f}%"


def _num(value: Any, digits: int = 3) -> str:
    return "-" if value is None else f"{float(value):.{digits}f}"


def _stat_table(rows: list[sqlite3.Row], include_match: bool = False) -> list[str]:
    columns = [
        "子类别 | 信号窗 | 排名池 | 后续周期 | 事件 | 超额胜率 | 95%区间 | 平均方向超额 | 超额盈亏比 | 超额利润因子",
        "---|---:|---|---:|---:|---:|---|---:|---:|---:",
    ]
    for row in rows:
        key = str(row["segment_key"])
        if include_match:
            key = f"{key}（匹配）"
        columns.append(
            " | ".join(
                (
                    key,
                    f"{int(row['window_days'])}D",
                    str(row["rank_band"]),
                    str(row["outcome_horizon"]),
                    str(row["n_events"]),
                    _pct(row["excess_hit_rate"]),
                    f"{_pct(row['excess_hit_ci_low'])}–{_pct(row['excess_hit_ci_high'])}",
                    _pct(row["avg_directional_excess_pct"]),
                    _num(row["excess_payoff_ratio"]),
                    _num(row["excess_profit_factor"]),
                )
            )
        )
    return columns


def write_segment_reports(con: sqlite3.Connection, report_path: Path) -> dict[str, int]:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    stats = con.execute(
        """SELECT * FROM sv_segment_stat
           ORDER BY source_scope,segment_type,segment_key,window_days,rank_band,outcome_horizon,direction"""
    ).fetchall()
    stat_columns = [str(row[1]) for row in con.execute("PRAGMA table_info(sv_segment_stat)")]
    stat_rows = _write_rows(report_path, stats, stat_columns)

    event_path = report_path.parent / "sv_segment_event_results.csv"
    events = con.execute(
        """SELECT e.*,o.outcome_horizon,o.exit_day,o.exit_price,o.directional_return_pct,
                  o.directional_excess_pct,o.raw_hit,o.excess_hit,o.max_favorable_excess,
                  o.max_adverse_excess,o.status AS outcome_status
             FROM sv_segment_event e JOIN sv_segment_outcome o ON o.event_id=e.event_id
            ORDER BY e.signal_day,e.event_id,o.outcome_horizon"""
    ).fetchall()
    event_columns = [str(key) for key in events[0].keys()] if events else [
        "event_id","ticker","source_scope","segment_type","segment_key","window_days",
        "rank_band","direction","signal_day","outcome_horizon","status",
    ]
    event_rows = _write_rows(event_path, events, event_columns)

    coverage_path = report_path.parent / "sv_segment_rank_coverage.csv"
    coverage = con.execute(
        """SELECT asof_day,source,segment_type,segment_key,MAX(population) AS population,
                  COUNT(*) AS ranked_rows
             FROM sv_segment_score_asof
            GROUP BY asof_day,source,segment_type,segment_key
            ORDER BY asof_day,source,segment_type,segment_key"""
    ).fetchall()
    coverage_columns = ["asof_day","source","segment_type","segment_key","population","ranked_rows"]
    coverage_rows = _write_rows(coverage_path, coverage, coverage_columns)

    horizon_rows = con.execute(
        """SELECT * FROM sv_segment_stat
            WHERE direction='all' AND segment_type='horizon'
              AND segment_key=outcome_horizon
            ORDER BY segment_key,window_days,rank_band"""
    ).fetchall()
    narrative_rows = con.execute(
        """SELECT * FROM sv_segment_stat
            WHERE direction='all' AND segment_type='narrative' AND outcome_horizon='20D'
            ORDER BY segment_key,window_days,rank_band"""
    ).fetchall()
    style_rows = con.execute(
        """SELECT * FROM sv_segment_stat
            WHERE direction='all' AND segment_type='investor_type' AND outcome_horizon='20D'
            ORDER BY segment_key,window_days,rank_band"""
    ).fetchall()
    latest_coverage = con.execute(
        """SELECT source,segment_type,segment_key,MAX(population) AS max_population,
                  MIN(asof_day) AS first_qualified_day,MAX(asof_day) AS last_day
             FROM sv_segment_score_asof
            GROUP BY source,segment_type,segment_key
            ORDER BY segment_type,max_population DESC"""
    ).fetchall()
    summary_path = report_path.parent / "sv_segment_backtest_summary.md"
    lines = [
        "# X 子 SV 垂直集中效果回测",
        "",
        "## 口径",
        "",
        "- 作者子 SV 只使用信号日前已经到期的结算证据，禁止使用当前排名回填历史。",
        "- 每个滚动窗口内按作者最新 Call 去重；至少 3 位作者、同向度 65%、有效声音 2.5。",
        "- 比较子 SV Top 10% 与 Top 25%；下一交易日调整后开盘入场，相对 SPY 计算方向超额。",
        "- 周期子 SV 的主结果使用同名后续周期；赛道和投资类型表统一展示 20D，完整周期见 CSV。",
        "",
        "## 子 SV 历史池覆盖",
        "",
        "来源 | 子类 | key | 最大合格作者数 | 首次形成 | 最后日期",
        "---|---|---|---:|---|---",
    ]
    lines.extend(
        f"{row['source']} | {row['segment_type']} | {row['segment_key']} | {row['max_population']} | {row['first_qualified_day']} | {row['last_day']}"
        for row in latest_coverage
    )
    lines.extend(["", "## 时间周期子 SV：匹配周期", ""])
    lines.extend(_stat_table(horizon_rows, include_match=True))
    lines.extend(["", "## 赛道子 SV：20D 后续表现", ""])
    lines.extend(_stat_table(narrative_rows))
    lines.extend(["", "## 投资类型子 SV：20D 后续表现", ""])
    lines.extend(_stat_table(style_rows))
    lines.extend(
        [
            "",
            "## 文件",
            "",
            f"- 完整统计：`{report_path.name}`",
            f"- 逐事件及作者原链：`{event_path.name}`",
            f"- 历史排名池覆盖：`{coverage_path.name}`",
            "",
            "少于 10 个事件的结果只作观察；不同标的、窗口和子类别可能重叠，不能把 Wilson 区间解释为独立组合的显著性。",
        ]
    )
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {
        "report_rows": stat_rows,
        "event_report_rows": event_rows,
        "coverage_report_rows": coverage_rows,
    }

