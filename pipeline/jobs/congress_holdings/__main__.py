from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path

from .workflows import run


def main() -> None:
    root = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description="Mark disclosed buys without later disclosed exits to market")
    parser.add_argument("--snapshot", type=Path, default=root / "data/exports/congress/disclosed_capitol.json")
    parser.add_argument("--db", type=Path, default=root / "data/dev.db")
    parser.add_argument("--output", type=Path, default=root / "data/exports/congress/open_buy_returns")
    parser.add_argument("--as-of", type=dt.date.fromisoformat, default=dt.datetime.now(dt.timezone.utc).date())
    parser.add_argument("--fetch-prices", action="store_true")
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()
    print(run(args.snapshot, args.db, args.output, args.as_of, fetch_prices=args.fetch_prices, workers=args.workers))


if __name__ == "__main__":
    main()
