from __future__ import annotations

import argparse
from pathlib import Path

from .commands import core, global_retail, kol, narratives, smart_voice, youtube

ROOT = Path(__file__).resolve().parents[2]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pipeline.manage")
    subparsers = parser.add_subparsers(dest="cmd", required=True)

    for module in (core, global_retail, youtube, kol, smart_voice, narratives):
        module.register_commands(subparsers, ROOT)

    return parser


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
