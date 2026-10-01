"""Recalculate three-year open-position win rate and mark-to-market return."""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from pipeline.domain.institutional_holdings.registry import SUBJECTS
from pipeline.jobs.congress_capture.cusip_tickers import tickers as mapped_tickers
from pipeline.jobs.congress_capture.refresh_cycle import ROOT, three_year_start
from pipeline.jobs.congress_follow.workflows import load_prices, supplement_yahoo_prices
from pipeline.jobs.congress_holdings.workflows import (
    build_unclosed_buys,
    mark_to_market,
)
from pipeline.jobs.subject_open_returns.directional import (
    calculate,
    collect_signals,
    fill_price_cache,
    read_prices,
)
from pipeline.jobs.subject_open_returns.identities import app_politician_ids
from pipeline.jobs.subject_open_returns.reports import reports_by_cik
from pipeline.platforms.congress.disclosures import load_disclosures

ARCHIVE = ROOT / "data/exports/congress/congress-trading-monitor-current.zip"
HISTORY = ROOT / "data/exports/institutional_holdings/history"
OUTPUT = ROOT / "data/reports/subject-open-returns-three-year"


def political_lots(archive: Path, since: date, as_of: date) -> tuple[list[dict], dict]:
    members, disclosures = load_disclosures(archive, start_date=since, end_date=as_of)
    identities = app_politician_ids(members, disclosures)
    rows = []
    excluded: Counter[str] = Counter()
    for item in disclosures:
        subject_key = identities.get(item.member.member_id)
        if not subject_key:
            excluded["unpublished_identity"] += 1
            continue
        if not item.filing_date:
            excluded["missing_filing_date"] += 1
            continue
        action = {
            "Purchase": "Buy",
            "Sale (Full)": "Sell",
            "Sale (Partial)": "Sell",
            "Exchange": "Exchange",
        }.get(item.transaction_type)
        if action is None:
            excluded["other_action"] += 1
            continue
        rows.append(
            {
                "id": item.trade_id,
                "politician_id": subject_key,
                "politician_name": item.member.name,
                "chamber": item.member.chamber,
                "party": item.member.party or "",
                "ticker": item.ticker,
                "asset_type": "Stock"
                if item.asset_type in {"ST", "Stock"}
                else item.asset_type,
                "trade_type": action,
                "transaction_date": item.transaction_date.isoformat(),
                "disclosure_date": item.filing_date.isoformat(),
            }
        )
    lots, rejected = build_unclosed_buys(rows, as_of)
    excluded.update(rejected)
    for lot in lots:
        lot.update(
            subject_id=f"politician:{lot['politician_id']}",
            subject_type="politician",
            entry_basis="transaction_date_adjusted_close",
            latest_disclosure_date=lot["first_disclosure_date"],
        )
    return lots, {"source_trades": len(disclosures), "excluded": dict(excluded)}


def institutional_lots(
    history: Path, since: date, as_of: date, mapping: dict[str, str], *, subjects: tuple | None = None
) -> tuple[list[dict], dict]:
    lots = []
    excluded: Counter[str] = Counter()
    subjects = SUBJECTS if subjects is None else subjects
    by_cik = {
        cik: reports_by_cik(history, cik, since, as_of)
        for cik in {s.filer_cik for s in subjects}
    }
    coverage = {}
    for subject in subjects:
        reports, errors = by_cik[subject.filer_cik]
        if not reports:
            excluded["missing_reports"] += 1
            continue
        latest = reports[-1]
        coverage[subject.id] = {
            "latest_period": latest["periodOfReport"],
            "latest_filing": latest["publicAt"],
            "quarter_count": len(reports),
            "report_type": latest["reportType"],
            "report_errors": errors,
        }
        if errors and any(
            error.split(":", 1)[0] >= latest["periodOfReport"] for error in errors
        ):
            excluded["latest_report_error_subject"] += 1
            continue
        if latest["reportType"] != "13F HOLDINGS REPORT":
            excluded["incomplete_latest_report_subject"] += 1
            continue
        if (as_of - date.fromisoformat(latest["periodOfReport"])).days > 200:
            excluded["stale_latest_report_subject"] += 1
            continue
        seen_cusips = set()
        for holding in latest["holdings"]:
            if holding.get("option") or holding.get("shareType") != "SH":
                excluded["option_or_non_share"] += 1
                continue
            cusip = holding["cusip"]
            if cusip in seen_cusips:
                continue
            seen_cusips.add(cusip)
            ticker = mapping.get(cusip)
            if not ticker:
                excluded["unmapped_cusip"] += 1
                continue
            if not float(holding.get("reportedShares") or 0) > 0:
                excluded["zero_shares"] += 1
                continue
            first = latest
            current_period = date.fromisoformat(latest["periodOfReport"])
            for prior in reversed(reports[:-1]):
                prior_period = date.fromisoformat(prior["periodOfReport"])
                if not 75 <= (current_period - prior_period).days <= 105:
                    break
                if prior["reportType"] != "13F HOLDINGS REPORT":
                    break
                if not any(
                    row["cusip"] == cusip
                    and not row.get("option")
                    and row.get("shareType") == "SH"
                    and float(row.get("reportedShares") or 0) > 0
                    for row in prior["holdings"]
                ):
                    break
                first = prior
                current_period = prior_period
            lots.append(
                {
                    "subject_id": f"{subject.kind}:{subject.id}",
                    "subject_type": subject.kind,
                    "politician_id": f"{subject.kind}:{subject.id}",
                    "politician_name": subject.title,
                    "chamber": "",
                    "party": "",
                    "ticker": ticker,
                    "cusip": cusip,
                    "transaction_date": first["publicAt"],
                    "first_disclosure_date": first["publicAt"],
                    "latest_disclosure_date": latest["publicAt"],
                    "latest_report_period": latest["periodOfReport"],
                    "entry_basis": "first_continuous_public_13f_filing_adjusted_close",
                    "source_trade_ids": [first["accession"], latest["accession"]],
                }
            )
    return lots, {"excluded": dict(excluded), "subject_coverage": coverage}


def subject_summary(marked: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for row in marked:
        groups[row["subject_id"]].append(row)
    summary = []
    for subject_id, rows in groups.items():
        priced = [row for row in rows if row["status"] == "priced_open_proxy"]
        returns = [row["unrealized_asset_return_pct"] for row in priced]
        summary.append(
            {
                "subject_id": subject_id,
                "subject_type": rows[0]["subject_type"],
                "name": rows[0]["politician_name"],
                "candidate_positions": len(rows),
                "priced_positions": len(priced),
                "open_position_positive_rate_pct": 100
                * sum(value > 0 for value in returns)
                / len(returns)
                if returns
                else None,
                "mean_open_return_pct": statistics.mean(returns) if returns else None,
                "median_open_return_pct": statistics.median(returns)
                if returns
                else None,
                "latest_disclosure_date": max(
                    row["latest_disclosure_date"] for row in rows
                ),
            }
        )
    return sorted(
        summary,
        key=lambda row: (row["subject_type"], -row["priced_positions"], row["name"]),
    )


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def group_summary(marked: list[dict], summary: list[dict]) -> dict[str, dict]:
    output = {}
    for kind in ("politician", "celebrity", "institution"):
        rows = [row for row in marked if row["subject_type"] == kind]
        priced = [row for row in rows if row["status"] == "priced_open_proxy"]
        returns = [row["unrealized_asset_return_pct"] for row in priced]
        output[kind] = {
            "roster_subjects": sum(row["subject_type"] == kind for row in summary),
            "subjects_with_candidate": sum(
                row["subject_type"] == kind and row["candidate_positions"] > 0
                for row in summary
            ),
            "subjects_with_price": sum(
                row["subject_type"] == kind and row["priced_positions"] > 0
                for row in summary
            ),
            "subjects_with_directional": sum(
                row["subject_type"] == kind and row["directional_observations"] > 0
                for row in summary
            ),
            "candidate_positions": len(rows),
            "priced_positions": len(priced),
            "open_position_win_rate_pct": 100
            * sum(value > 0 for value in returns)
            / len(returns)
            if returns
            else None,
            "equal_lot_mean_return_pct": statistics.mean(returns) if returns else None,
            "equal_lot_median_return_pct": statistics.median(returns)
            if returns
            else None,
        }
    return output


def write_report(path: Path, manifest: dict, summary: list[dict]) -> None:
    def percent(value: float | None, *, signed: bool = False) -> str:
        if value is None:
            return "—"
        return f"{value:+.1f}%" if signed else f"{value:.1f}%"

    lines = [
        "# 三年主体方向胜率与未平仓持仓研究",
        "",
        f"披露窗口：{manifest['source_since']} 至 {manifest['as_of']}；行情截至 {manifest['latest_market_date']}。",
        "方向胜率按文件公开后下一个可执行开盘价与最新收盘价比较，以 win / (win + lose) 计算；未平仓跟踪收益从买入/首次连续申报入场价持有至最新市场收盘，**没有 30 天强制退出**。",
        "",
        "| 主体类型 | 有价主体/名册主体 | 有价仓位/候选仓位 | 方向胜率 | 开放仓位正收益率 | 仓位等权平均收益 | 仓位收益中位数 |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for kind, label in (
        ("politician", "政客"),
        ("celebrity", "名人"),
        ("institution", "机构"),
    ):
        row = manifest["by_type"][kind]
        directional = manifest["directional_by_type"][kind]
        lines.append(
            f"| {label} | {row['subjects_with_price']}/{row['roster_subjects']} | "
            f"{row['priced_positions']}/{row['candidate_positions']} | "
            f"{percent(directional['win_rate_pct'])} ({directional['wins']}/{directional['wins'] + directional['losses']}) | "
            f"{percent(row['open_position_win_rate_pct'])} | "
            f"{percent(row['equal_lot_mean_return_pct'], signed=True)} | "
            f"{percent(row['equal_lot_median_return_pct'], signed=True)} |"
        )
    lines += [
        "",
        "## 完整结果",
        "",
        "每主体方向胜率及其胜负数、开放仓位数、正收益比例与等权平均/中位收益见 `subjects.csv`；逐仓入场日期、两端复权价、估值状态见 `positions.csv`。",
        "",
        "## 限制",
        "",
        "- 政客使用交易日收盘价估算未见后续卖出的买入批次；不是公众在申报公开后可复制的收益。任何后续部分卖出也保守剔除整个批次。",
        "- 13F 使用季度申报中仍列示且连续出现的现货持仓；季度内买卖及申报后持仓变化不可见。名人与机构若共用 CIK，结果同源且在跨类型总计中重复。",
        "- 13F 只对有可靠 CUSIP→Ticker 映射的部分标的计算，不代表完整组合；多只涨幅极大的个股会显著抬高算术平均。",
        f"- 行情缺失或过期的候选仓位有 {manifest['candidate_positions'] - manifest['priced_positions']} 个；不存在的市价没有用陈旧价填补。",
        "- 方向胜率包含披露卖出后的下跌方向，但 13F 股数变化不能证明实际交易；未平仓收益只含开放多仓。这两个样本和执行口径不同，不能相互推算。",
        "- 这是研究指标，不是实际交易胜率、账户收益率、可交易跟单组合收益或已审计 Score；发布到 App 也不构成已审计 Score。",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def run(
    *,
    archive: Path = ARCHIVE,
    history: Path = HISTORY,
    output: Path = OUTPUT,
    db: Path = ROOT / "data/dev.db",
    as_of: date | None = None,
    workers: int = 6,
    subject_ids: set[str] | None = None,
) -> dict:
    as_of = as_of or datetime.now(timezone.utc).date()
    since = three_year_start(as_of)
    selected = None
    if subject_ids is not None:
        if not subject_ids or not subject_ids <= {subject.id for subject in SUBJECTS}:
            raise ValueError("Unknown or empty selected subject roster")
        if output.resolve() == OUTPUT.resolve():
            raise ValueError("Scoped research requires a separate output directory")
        selected = tuple(subject for subject in SUBJECTS if subject.id in subject_ids)
    politicians, congress_meta = (political_lots(archive, since, as_of) if selected is None
                                  else ([], {"source_trades": 0, "excluded": {}}))
    institutions, sec_meta = institutional_lots(history, since, as_of, mapped_tickers(),
                                               subjects=SUBJECTS if selected is None else selected)
    lots = politicians + institutions
    if not lots:
        raise ValueError("No eligible open positions")
    output.mkdir(parents=True, exist_ok=True)
    start = min(
        date.fromisoformat(lot["transaction_date"]) for lot in lots
    ) - timedelta(days=7)
    tickers = {lot["ticker"] for lot in lots}
    prices = load_prices(db, tickers, start, as_of)
    failures = supplement_yahoo_prices(
        prices, tickers, start, as_of, output / "yahoo_prices.json", workers
    )
    marked = mark_to_market(lots, prices)
    summary = subject_summary(marked)
    signals, names, signal_exclusions = collect_signals(archive, history, since, as_of, subjects=selected)
    directional_tickers = {
        signal.ticker for rows in signals.values() for signal in rows
    }
    directional_cache = output / "directional_prices.sqlite"
    directional_failures = fill_price_cache(
        directional_cache, directional_tickers, start, as_of, workers
    )
    directional_prices = read_prices(
        directional_cache, db, directional_tickers, start, as_of
    )
    directional = calculate(signals, directional_prices, as_of)
    by_id = {row["subject_id"]: row for row in summary}
    for subject_id, name in names.items():
        if subject_id not in by_id:
            kind = subject_id.split(":", 1)[0]
            by_id[subject_id] = {
                "subject_id": subject_id,
                "subject_type": kind,
                "name": name,
                "candidate_positions": 0,
                "priced_positions": 0,
                "open_position_positive_rate_pct": None,
                "mean_open_return_pct": None,
                "median_open_return_pct": None,
                "latest_disclosure_date": None,
            }
        by_id[subject_id].update(
            directional.get(
                subject_id,
                {
                    "directional_win_rate_pct": None,
                    "directional_wins": 0,
                    "directional_losses": 0,
                    "directional_flat": 0,
                    "directional_observations": 0,
                    "directional_excluded": {},
                },
            )
        )
    summary = sorted(by_id.values(), key=lambda row: (row["subject_type"], row["name"]))
    write_csv(output / "positions.csv", marked)
    write_csv(output / "subjects.csv", summary)
    directional_by_type = {}
    for kind in ("politician", "celebrity", "institution"):
        subset = [row for row in summary if row["subject_type"] == kind]
        wins = sum(row["directional_wins"] for row in subset)
        losses = sum(row["directional_losses"] for row in subset)
        observations = sum(row["directional_observations"] for row in subset)
        directional_by_type[kind] = {
            "subjects": len(subset),
            "wins": wins,
            "losses": losses,
            "observations": observations,
            "win_rate_pct": wins * 100 / (wins + losses) if wins + losses else None,
        }
    manifest = {
        "as_of": as_of.isoformat(),
        "source_since": since.isoformat(),
        "latest_market_date": max(prices["SPY"]).isoformat(),
        "source_trade_count": congress_meta["source_trades"],
        "source_exclusions": {
            "congress": congress_meta["excluded"],
            "sec_13f": sec_meta["excluded"],
        },
        "source_coverage": sec_meta["subject_coverage"],
        "candidate_positions": len(lots),
        "priced_positions": sum(row["status"] == "priced_open_proxy" for row in marked),
        "price_status_counts": dict(Counter(row["status"] for row in marked)),
        "price_fetch_failures": failures,
        "by_type": group_summary(marked, summary),
        "directional_by_type": directional_by_type,
        "directional_signal_exclusions": signal_exclusions,
        "directional_price_failures": directional_failures,
        "methodology": {
            "win_rate": "directional post-disclosure rule: buys/increases win on a rise and sells/decreases win on a fall, from next executable adjusted open to latest close; rate is wins / (wins + losses), with flat observations excluded from its denominator",
            "open_position_positive_rate": "share of priced currently-open proxies with positive absolute asset return; zero counts as non-win",
            "follow_return": "equal-weight mean of position returns from entry until latest common close; no 30-day exit or SPY subtraction",
            "congress_entry": "disclosed buy transaction date adjusted close, or next session; any later disclosed sale/exchange removes whole lot",
            "sec_13f_entry": "earliest uninterrupted quarterly appearance still in latest complete 13F, from public filing date adjusted close",
            "limits": "No position size or realized return; politician partial sales conservatively exclude lot; 13F neither proves a trade nor current ownership and omits non-13F assets; celebrity metrics are attributed institution filings and may duplicate institution metrics",
        },
        "published_score": None,
        "selected_subjects": sorted(subject_ids) if subject_ids is not None else None,
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )
    write_report(output / "report.md", manifest, summary)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ARCHIVE)
    parser.add_argument("--history", type=Path, default=HISTORY)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--db", type=Path, default=ROOT / "data/dev.db")
    parser.add_argument(
        "--as-of", type=date.fromisoformat, default=datetime.now(timezone.utc).date()
    )
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--subject", action="append", choices=[subject.id for subject in SUBJECTS])
    args = parser.parse_args()
    print(
        json.dumps(
            run(
                archive=args.archive,
                history=args.history,
                output=args.output,
                db=args.db,
                as_of=args.as_of,
                workers=args.workers,
                subject_ids=set(args.subject) if args.subject else None,
            ),
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
