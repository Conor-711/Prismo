#!/usr/bin/env python3
"""Create the ignored local realtime environment without printing secrets."""
from __future__ import annotations

import argparse
import os
import secrets
import subprocess
from pathlib import Path

from dotenv import dotenv_values


ROOT = Path(__file__).resolve().parents[1]
LOCAL_ENV = ROOT / ".env.x-realtime.local"


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--api-key-from-clipboard", action="store_true")
    source.add_argument("--api-key-stdin", action="store_true")
    return parser.parse_args()


def _api_key(args: argparse.Namespace, existing: dict[str, str | None]) -> str:
    if args.api_key_from_clipboard:
        value = subprocess.run(
            ["pbpaste"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    elif args.api_key_stdin:
        value = os.sys.stdin.read().strip()
    else:
        value = str(existing.get("TWITTERAPI_IO_KEY") or os.environ.get("TWITTERAPI_IO_KEY") or "")
    if not value:
        raise SystemExit(
            "TWITTERAPI_IO_KEY is missing. Copy it from the provider dashboard and rerun "
            "with --api-key-from-clipboard."
        )
    if any(character.isspace() for character in value):
        raise SystemExit("The clipboard does not contain a valid single-line API key.")
    return value


def _quoted(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    args = _arguments()
    existing = dotenv_values(LOCAL_ENV) if LOCAL_ENV.exists() else {}
    values = {
        "X_INGEST_ENABLED": "true",
        "TWITTERAPI_IO_KEY": _api_key(args, existing),
        "BSMART_X_WEBHOOK_TOKEN": str(
            existing.get("BSMART_X_WEBHOOK_TOKEN") or secrets.token_urlsafe(32)
        ),
        "BSMART_X_STREAM_ENABLED": "true",
        "BSMART_X_STREAM_RECONNECT_SECONDS": "90",
        "BSMART_X_POOL_LIMIT": str(existing.get("BSMART_X_POOL_LIMIT") or "0"),
        "BSMART_X_FREEZE_AUTHOR_POOL": "true",
        "BSMART_READ_MODEL_MODE": "database",
    }
    content = "# Generated locally; ignored by Git.\n" + "".join(
        f"{key}={_quoted(value)}\n" for key, value in values.items()
    )
    LOCAL_ENV.write_text(content, encoding="utf-8")
    LOCAL_ENV.chmod(0o600)
    print(f"Configured {LOCAL_ENV.name}; secrets were not printed.")


if __name__ == "__main__":
    main()
