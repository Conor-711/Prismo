from __future__ import annotations

import json

from ...jobs.investor_ability.research import build_research_snapshot


def _run(args) -> None:
    result = build_research_snapshot(
        args.db, args.output, args.congress_file, args.institutional_dir
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


def register_commands(sub, root) -> None:
    parser = sub.add_parser("investor-ability-research")
    parser.add_argument("--db", default=str(root / "data" / "dev.db"))
    parser.add_argument(
        "--output", default=str(root / "data" / "reports" / "investor_ability")
    )
    parser.add_argument(
        "--congress-file",
        default=str(
            root / "data" / "exports" / "congress" / "congress_trades_1y_research.jsonl"
        ),
    )
    parser.add_argument(
        "--institutional-dir",
        default=str(root / "data" / "exports" / "institutional_holdings"),
    )
    parser.set_defaults(func=_run)
