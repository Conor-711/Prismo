#!/usr/bin/env python3
"""Audit MVP Smart Account and Smart Money coverage for launch tickers."""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT / "data" / "dev.db"
DEFAULT_TICKERS = ("MU", "MSTR", "NVDA")

SMART_ACCOUNT_FRESH_DAYS = 2
SMART_ACCOUNT_MIN_AUTHORS = 3
SMART_ACCOUNT_MIN_N_EFF = 8
YOUTUBE_TRANSCRIPT_TARGET = 0.95
SMART_MONEY_FRESH_DAYS = 1
SMART_MONEY_MIN_WALLETS = 3
SMART_MONEY_MIN_DAY_VOLUME = 1_000_000


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--tickers", nargs="+", default=list(DEFAULT_TICKERS))
    parser.add_argument("--as-of", type=date.fromisoformat, default=date.today())
    parser.add_argument("--report", type=Path)
    parser.add_argument("--json", dest="json_path", type=Path)
    return parser.parse_args()


def iso_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def age_days(value: str | None, as_of: date) -> int | None:
    parsed = iso_datetime(value)
    if parsed is None:
        return None
    return max(0, (as_of - parsed.date()).days)


def placeholders(values: list[str]) -> str:
    return ",".join("?" for _ in values)


def query_rows(connection: sqlite3.Connection, sql: str, parameters: tuple[Any, ...]) -> list[dict[str, Any]]:
    return [dict(row) for row in connection.execute(sql, parameters).fetchall()]


def audit_smart_account(
    connection: sqlite3.Connection,
    ticker: str,
    as_of: date,
) -> dict[str, Any]:
    cutoff = (as_of - timedelta(days=30)).isoformat()
    sources = query_rows(
        connection,
        """
        SELECT cc.source,
               COUNT(*) AS candidates,
               COUNT(c.candidate_id) AS labeled,
               SUM(CASE WHEN c.is_actionable_call=1 THEN 1 ELSE 0 END) AS actionable,
               COUNT(DISTINCT CASE WHEN c.is_actionable_call=1 THEN c.investor_id END) AS actionable_authors,
               MAX(CASE WHEN c.is_actionable_call=1 THEN c.created_at END) AS latest_actionable_at
          FROM sv_call_candidate cc
          LEFT JOIN sv_call c ON c.candidate_id=cc.candidate_id
         WHERE cc.ticker=?
         GROUP BY cc.source
         ORDER BY cc.source
        """,
        (ticker,),
    )
    for source in sources:
        source["freshness_days"] = age_days(source["latest_actionable_at"], as_of)

    qualified_recent_authors = connection.execute(
        """
        SELECT COUNT(DISTINCT c.investor_id)
          FROM sv_call c
          JOIN sv_investor_score score ON score.investor_id=c.investor_id
         WHERE c.ticker=?
           AND c.is_actionable_call=1
           AND c.created_at>=?
           AND score.n_eff>=?
        """,
        (ticker, cutoff, SMART_ACCOUNT_MIN_N_EFF),
    ).fetchone()[0]

    youtube = dict(
        connection.execute(
            """
            SELECT COUNT(DISTINCT v.id) AS videos,
                   COUNT(DISTINCT f.video_id) AS fulltexts,
                   COUNT(DISTINCT a.video_id) AS analyses,
                   COUNT(DISTINCT CASE WHEN LENGTH(f.content_zh)>200 THEN f.video_id END) AS translated_fulltexts
              FROM yt_video v
              LEFT JOIN yt_fulltext f ON f.video_id=v.id
              LEFT JOIN yt_analysis a ON a.video_id=v.id
             WHERE v.ticker=?
            """,
            (ticker,),
        ).fetchone()
    )
    youtube_calls = dict(
        connection.execute(
            """
            SELECT COUNT(*) AS actionable_calls,
                   SUM(CASE WHEN COALESCE(evidence_span, '')<>''
                                  OR evidence_segment_start IS NOT NULL THEN 1 ELSE 0 END) AS evidence_located,
                   SUM(CASE WHEN COALESCE(transcript_version, '')<>'' THEN 1 ELSE 0 END) AS transcript_versioned
              FROM sv_call
             WHERE ticker=? AND source='youtube' AND is_actionable_call=1
            """,
            (ticker,),
        ).fetchone()
    )
    actionable_youtube = youtube_calls["actionable_calls"] or 0
    transcript_ratio = (
        (youtube_calls["transcript_versioned"] or 0) / actionable_youtube if actionable_youtube else 0.0
    )
    evidence_ratio = (
        (youtube_calls["evidence_located"] or 0) / actionable_youtube if actionable_youtube else 0.0
    )

    latest_actionable_at = max(
        (source["latest_actionable_at"] for source in sources if source["latest_actionable_at"]),
        default=None,
    )
    freshness = age_days(latest_actionable_at, as_of)
    reasons: list[str] = []
    if freshness is None or freshness > SMART_ACCOUNT_FRESH_DAYS:
        reasons.append(f"最新有效观点滞后 {freshness if freshness is not None else '未知'} 天")
    if qualified_recent_authors < SMART_ACCOUNT_MIN_AUTHORS:
        reasons.append(f"近 30 天仅 {qualified_recent_authors} 位达到 n_eff 门槛的独立作者")
    if actionable_youtube and evidence_ratio < 1:
        reasons.append(f"YouTube 证据定位完整率仅 {evidence_ratio:.0%}")
    if actionable_youtube and transcript_ratio < YOUTUBE_TRANSCRIPT_TARGET:
        reasons.append(f"YouTube 口播版本绑定率仅 {transcript_ratio:.0%}")

    return {
        "latest_actionable_at": latest_actionable_at,
        "freshness_days": freshness,
        "qualified_recent_authors": qualified_recent_authors,
        "sources": sources,
        "youtube": {**youtube, **youtube_calls, "evidence_ratio": evidence_ratio, "transcript_ratio": transcript_ratio},
        "ready": not reasons,
        "blocking_reasons": reasons,
    }


def audit_smart_money(
    connection: sqlite3.Connection,
    ticker: str,
    as_of: date,
) -> dict[str, Any]:
    instrument = dict(
        connection.execute(
            """
            SELECT COUNT(*) AS instruments,
                   SUM(CASE WHEN is_active=1 THEN 1 ELSE 0 END) AS active_instruments,
                   MAX(day_notional_volume) AS max_day_notional_volume,
                   MAX(last_seen_at) AS latest_instrument_at
              FROM hl_tradfi_instrument
             WHERE symbol=?
            """,
            (ticker,),
        ).fetchone()
    )
    fills = dict(
        connection.execute(
            """
            SELECT COUNT(*) AS fills,
                   COUNT(DISTINCT address) AS wallets,
                   SUM(notional) AS total_notional,
                   MAX(created_at) AS latest_fill_at
              FROM hl_fill
             WHERE symbol=?
            """,
            (ticker,),
        ).fetchone()
    )
    signal_row = connection.execute(
        """
        SELECT as_of_day, window_days, qualified_wallets, long_wallets, short_wallets,
               signal, day_notional_volume, open_interest_notional
          FROM hl_asset_signal
         WHERE symbol=? AND window_days=7
         ORDER BY as_of_day DESC
         LIMIT 1
        """,
        (ticker,),
    ).fetchone()
    signal = dict(signal_row) if signal_row else None

    latest_score_day_row = connection.execute("SELECT MAX(as_of_day) FROM hl_wallet_score").fetchone()
    latest_score_day = latest_score_day_row[0] if latest_score_day_row else None
    eligible_history = {"wallets": 0, "fills": 0, "notional": 0, "latest_fill_at": None}
    if latest_score_day:
        eligible_history = dict(
            connection.execute(
                """
                SELECT COUNT(DISTINCT f.address) AS wallets,
                       COUNT(*) AS fills,
                       SUM(f.notional) AS notional,
                       MAX(f.created_at) AS latest_fill_at
                  FROM hl_fill f
                  JOIN hl_wallet_score score
                    ON score.address=f.address AND score.as_of_day=? AND score.eligible=1
                 WHERE f.symbol=?
                """,
                (latest_score_day, ticker),
            ).fetchone()
        )

    signal_age = age_days(f"{signal['as_of_day']}T00:00:00+00:00" if signal else None, as_of)
    fill_age = age_days(fills["latest_fill_at"], as_of)
    qualified_wallets = signal["qualified_wallets"] if signal else 0
    day_volume = instrument["max_day_notional_volume"] or 0
    reasons: list[str] = []
    if not instrument["active_instruments"]:
        reasons.append("没有活跃的代币化美股市场")
    if day_volume < SMART_MONEY_MIN_DAY_VOLUME:
        reasons.append(f"日成交额仅 ${day_volume:,.0f}")
    if signal_age is None or signal_age > SMART_MONEY_FRESH_DAYS:
        reasons.append(f"最新资金信号滞后 {signal_age if signal_age is not None else '未知'} 天")
    if fill_age is None or fill_age > SMART_MONEY_FRESH_DAYS:
        reasons.append(f"最新链上成交滞后 {fill_age if fill_age is not None else '未知'} 天")
    if qualified_wallets < SMART_MONEY_MIN_WALLETS:
        reasons.append(f"7 日窗口仅 {qualified_wallets} 个当前合格账户")
    if not signal or signal["signal"] == "insufficient":
        reasons.append("派生资金信号仍为 insufficient")

    return {
        "instrument": instrument,
        "fills": fills,
        "latest_7d_signal": signal,
        "latest_signal_age_days": signal_age,
        "latest_fill_age_days": fill_age,
        "latest_wallet_score_day": latest_score_day,
        "eligible_wallet_history": eligible_history,
        "ready": not reasons,
        "blocking_reasons": reasons,
    }


def audit(connection: sqlite3.Connection, tickers: list[str], as_of: date) -> dict[str, Any]:
    result: dict[str, Any] = {"as_of": as_of.isoformat(), "tickers": {}}
    for raw_ticker in tickers:
        ticker = raw_ticker.upper()
        smart_account = audit_smart_account(connection, ticker, as_of)
        smart_money = audit_smart_money(connection, ticker, as_of)
        if smart_account["ready"] and smart_money["ready"]:
            readiness = "dual_ready"
        elif smart_account["ready"]:
            readiness = "account_only"
        else:
            readiness = "blocked"
        result["tickers"][ticker] = {
            "readiness": readiness,
            "smart_account": smart_account,
            "smart_money": smart_money,
        }
    return result


def render_markdown(result: dict[str, Any], db_path: Path) -> str:
    lines = [
        "# MVP 首发标的数据覆盖审计",
        "",
        f"> 审计日期：{result['as_of']}  ",
        f"> 数据库：`{db_path}`  ",
        "> 结论口径：历史数据量不等于当前可用信号；发布门槛同时检查新鲜度、独立样本和证据完整度。",
        "",
        "## 1. 发布门槛",
        "",
        f"- Smart Account：最新有效观点不超过 {SMART_ACCOUNT_FRESH_DAYS} 天；近 30 天至少 "
        f"{SMART_ACCOUNT_MIN_AUTHORS} 位 `n_eff >= {SMART_ACCOUNT_MIN_N_EFF}` 作者；YouTube 正式 Call "
        f"证据定位 100%，口播版本绑定至少 {YOUTUBE_TRANSCRIPT_TARGET:.0%}。",
        f"- Smart Money：活跃市场日成交额至少 ${SMART_MONEY_MIN_DAY_VOLUME:,.0f}；成交与派生信号不超过 "
        f"{SMART_MONEY_FRESH_DAYS} 天；7 日窗口至少 {SMART_MONEY_MIN_WALLETS} 个当前合格独立账户；"
        "派生结果不能是 `insufficient`。",
        "- 双侧未通过时不能生成确认或背离。Smart Account 单侧通过时可以展示，但必须标注“暂无资金验证”。",
        "",
        "## 2. 总览",
        "",
        "| 标的 | 当前状态 | SA 最新 | 近30天合格作者 | YouTube 证据/口播绑定 | SM 最新 | 7日合格账户 | 资金信号 |",
        "|---|---|---:|---:|---:|---:|---:|---|",
    ]
    for ticker, row in result["tickers"].items():
        sa = row["smart_account"]
        sm = row["smart_money"]
        yt = sa["youtube"]
        signal = sm["latest_7d_signal"] or {}
        lines.append(
            f"| {ticker} | `{row['readiness']}` | {sa['freshness_days']} 天 | "
            f"{sa['qualified_recent_authors']} | {yt['evidence_ratio']:.0%} / {yt['transcript_ratio']:.0%} | "
            f"{sm['latest_signal_age_days']} 天 | {signal.get('qualified_wallets', 0)} | "
            f"`{signal.get('signal', 'missing')}` |"
        )

    lines.extend(["", "## 3. 分标的证据", ""])
    for ticker, row in result["tickers"].items():
        sa = row["smart_account"]
        sm = row["smart_money"]
        lines.extend([
            f"### {ticker}",
            "",
            "**Smart Account 来源**",
            "",
            "| 来源 | 候选 | 已打标 | 有效 Call | 作者 | 最新有效观点 | 滞后 |",
            "|---|---:|---:|---:|---:|---|---:|",
        ])
        for source in sa["sources"]:
            lines.append(
                f"| {source['source']} | {source['candidates']} | {source['labeled']} | "
                f"{source['actionable'] or 0} | {source['actionable_authors']} | "
                f"{source['latest_actionable_at'] or '-'} | {source['freshness_days']} 天 |"
            )
        yt = sa["youtube"]
        lines.extend([
            "",
            f"YouTube：{yt['videos']} 个视频，{yt['fulltexts']} 份完整口播，{yt['analyses']} 份分析；"
            f"{yt['actionable_calls']} 条有效 Call 中，证据定位 {yt['evidence_located']} 条，"
            f"口播版本绑定 {yt['transcript_versioned']} 条。",
            "",
            "**Smart Money 证据**",
            "",
            f"- 历史成交：{sm['fills']['fills']:,} 笔、{sm['fills']['wallets']} 个账户、"
            f"名义金额 ${sm['fills']['total_notional'] or 0:,.0f}；最新成交 {sm['fills']['latest_fill_at'] or '-'}。",
            f"- 最新 Score 快照中的合格账户历史上有 {sm['eligible_wallet_history']['wallets']} 个曾交易该标的；"
            f"但最新 7 日派生信号只有 {(sm['latest_7d_signal'] or {}).get('qualified_wallets', 0)} 个当前合格账户。",
            "- Smart Account 阻塞项：" + ("；".join(sa["blocking_reasons"]) if sa["blocking_reasons"] else "无"),
            "- Smart Money 阻塞项：" + ("；".join(sm["blocking_reasons"]) if sm["blocking_reasons"] else "无"),
            "",
        ])

    lines.extend([
        "## 4. 开发决策",
        "",
        "1. 当前 MU、MSTR、NVDA 均不能进入真实双侧 Closed Beta；历史成交和历史观点只能证明可研究，不能证明当前事件可用。",
        "2. 第一优先级是恢复增量抓取、Call/口播版本绑定和 Hyperliquid 快照，不是继续扩充历史总量。",
        "3. Smart Money 需要把“历史上合格且交易过”与“当前窗口有效”分开；产品只使用后者生成确认、背离和领先。",
        "4. 每次扩充股票池前运行本审计；未通过双侧门槛的标的只能降级为 Smart Account-only，或不进入首发池。",
        "5. 生产监控必须直接复用这些门槛，避免数据库有数据但 App 对用户展示过期或伪中性的状态。",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    if not args.db.exists():
        raise SystemExit(f"Database not found: {args.db}")
    connection = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        result = audit(connection, args.tickers, args.as_of)
    finally:
        connection.close()

    markdown = render_markdown(result, args.db)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(markdown + "\n", encoding="utf-8")
    if args.json_path:
        args.json_path.parent.mkdir(parents=True, exist_ok=True)
        args.json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not args.report:
        print(markdown)


if __name__ == "__main__":
    main()
