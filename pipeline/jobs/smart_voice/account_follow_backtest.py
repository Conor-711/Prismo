"""Run per-account Smart Account follow-strategy backtests."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from ...domain.smart_voice.account_follow_backtest import (
    build_account_follow_backtest,
)
from ...domain.smart_voice.account_follow_backtest_reporting import (
    write_account_follow_reports,
)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="data/dev.db")
    parser.add_argument(
        "--output-dir",
        default="data/reports/smart_account_follow_backtest",
    )
    return parser


def run(args: argparse.Namespace) -> dict[str, object]:
    executable, descriptive, trades, profile = build_account_follow_backtest(
        db_path=Path(args.db).resolve(),
    )
    return write_account_follow_reports(
        Path(args.output_dir).resolve(),
        executable,
        descriptive,
        trades,
        profile,
    )


def main() -> None:
    print(json.dumps(run(_parser().parse_args()), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
