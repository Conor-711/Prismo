"""Private notification ranking mirrors the App's observed follow-backtest return."""
import csv
import os
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

from sqlalchemy import text

from ..config import REPO_ROOT

REPORT = REPO_ROOT / "data/reports/smart_account_follow_backtest/smart_account_follow_returns_full_history.csv"


def read_returns(path: Path = REPORT):
    rows = {}
    with path.open(encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)
        required = {"investor_id", "total_return", "end_day", "trade_count"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError("Follow-return report has missing columns")
        for row in reader:
            actor = row["investor_id"].strip().lower()
            try:
                value = Decimal(row["total_return"])
                as_of = date.fromisoformat(row["end_day"])
                trades = int(row["trade_count"])
            except (ValueError, InvalidOperation):
                continue
            if not 1 <= len(actor) <= 160 or not value.is_finite() or trades <= 0 or as_of > date.today():
                continue
            if actor in rows:
                raise ValueError("Duplicate actor in follow-return report")
            rows[actor] = {"actor_id": actor, "follow_return": value, "as_of": as_of,
                           "method": "full_history_follow_backtest"}
    return list(rows.values())


def sync_returns(session, path: Path = REPORT):
    rows = read_returns(path)
    if rows:
        session.execute(text("""insert into public.bsmart_push_return_metrics
            (actor_id,follow_return,as_of,method) values(:actor_id,:follow_return,:as_of,:method)
            on conflict(actor_id) do update set follow_return=excluded.follow_return,
              as_of=excluded.as_of,method=excluded.method
            where excluded.as_of>=bsmart_push_return_metrics.as_of"""), rows)
    return len(rows)


def sync_if_enabled(session):
    if os.environ.get("BSMART_ACTIVITY_PUSH_ENABLED", "false").lower() in {"true", "1", "yes"}:
        if session.get_bind().dialect.name != "postgresql":
            raise ValueError("Immediate push requires the native PostgreSQL project")
        return sync_returns(session)
    return 0
