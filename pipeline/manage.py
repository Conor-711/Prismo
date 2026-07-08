"""Compatibility CLI entrypoint.

The implementation lives in :mod:`pipeline.cli.registry`; keep this module so
existing Makefile targets and `python -m pipeline.manage` continue to work.
"""
from __future__ import annotations

from .cli.registry import build_parser, main


if __name__ == "__main__":
    main()
