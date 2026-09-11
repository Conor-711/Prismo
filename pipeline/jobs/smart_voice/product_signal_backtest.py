"""Run the leakage-free Smart Consensus / Smart Alpha product backtest."""
from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

from ...domain.smart_voice.product_signal_backtest import (
    build_alpha_events,
    build_consensus_events,
    calculate_outcomes,
    database_coverage,
    load_point_in_time_calls,
    load_price_book,
    summarize_outcomes,
    summarize_subgroups,
    write_dataclass_csv,
    write_dict_csv,
)
from ...domain.smart_voice.product_signal_backtest_reporting import write_product_signal_report


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="data/dev.db")
    parser.add_argument("--start-day", default="2025-07-28")
    parser.add_argument("--end-day", default="2026-07-27")
    parser.add_argument("--output-dir", default="data/reports/smart_signal_backtest")
    return parser


def run(args: argparse.Namespace) -> dict[str, object]:
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(Path(args.db).resolve())
    try:
        calls = load_point_in_time_calls(
            connection,
            start_day=args.start_day,
            end_day=args.end_day,
        )
        consensus = build_consensus_events(
            calls,
            start_day=args.start_day,
            end_day=args.end_day,
        )
        alpha = build_alpha_events(
            calls,
            start_day=args.start_day,
            end_day=args.end_day,
            consensus_events=consensus,
        )
        events = sorted(
            [*consensus, *alpha],
            key=lambda event: (event.signal_day, event.signal_type, event.ticker, event.event_id),
        )
        price_book = load_price_book(connection, (event.ticker for event in events))
        outcomes = calculate_outcomes(events, price_book)
        summary = summarize_outcomes(outcomes)
        subgroups = summarize_subgroups(
            outcomes,
            start_day=args.start_day,
            end_day=args.end_day,
        )
        coverage = database_coverage(connection)
    finally:
        connection.close()

    write_dataclass_csv(output_dir / "smart_signal_events.csv", events)
    write_dataclass_csv(output_dir / "smart_signal_outcomes.csv", outcomes)
    write_dict_csv(output_dir / "smart_signal_summary.csv", summary)
    write_dict_csv(output_dir / "smart_signal_subgroups.csv", subgroups)
    write_product_signal_report(
        output_dir / "smart_consensus_alpha_backtest.md",
        start_day=args.start_day,
        end_day=args.end_day,
        events=events,
        summary=summary,
        subgroups=subgroups,
        coverage=coverage,
    )
    manifest = {
        "start_day": args.start_day,
        "end_day": args.end_day,
        "point_in_time_calls": len(calls),
        "events": len(events),
        "event_first_day": min((event.signal_day for event in events), default=None),
        "event_last_day": max((event.signal_day for event in events), default=None),
        "outcomes": len(outcomes),
        "coverage": coverage,
    }
    (output_dir / "run_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    manifest = run(_parser().parse_args())
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
