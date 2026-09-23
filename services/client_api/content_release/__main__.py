import argparse
import json
import os
from pathlib import Path

from sqlalchemy import create_engine
from dotenv import dotenv_values
from ..config import REPO_ROOT, normalize_database_url
from .publisher import publish, rollback
from .push import load_push_environment, enabled, drain


def publication_database_url():
    key = "BSMART_CONTENT_DATABASE_URL"
    if key in os.environ:
        return os.environ[key].strip()
    # Read only the content URL; never reuse the web database or import other secrets.
    for path in (REPO_ROOT / "services/client_api/.env.content.local", REPO_ROOT / ".env"):
        if path.is_file():
            value = dotenv_values(path, interpolate=False).get(key)
            if value:
                return value.strip()
    return ""


def main():
    parser = argparse.ArgumentParser(description="Publish reviewed research to Supabase, without schema changes")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--input-dir", type=Path)
    action.add_argument("--rollback", metavar="REVISION")
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--reencode-baseline", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-drop", action="store_true")
    parser.add_argument("--historical-test", action="store_true", help="Explicit operator test with old data; preserve source dates and suppress push")
    parser.add_argument("--restore-rankings", action="store_true", help="Restore and freeze ranking fields from the reviewed baseline, preserving current content")
    args = parser.parse_args()
    load_push_environment()
    url = publication_database_url()
    if not url.startswith(("postgresql", "postgres://")):
        parser.error("Set protected BSMART_CONTENT_DATABASE_URL to Supabase PostgreSQL")
    engine = create_engine(normalize_database_url(url), pool_pre_ping=True,
                           connect_args={"connect_timeout": 10, "prepare_threshold": None, "tcp_user_timeout": 20000, "keepalives_idle": 10, "keepalives_interval": 5, "keepalives_count": 3, "options": "-c statement_timeout=30000 -c lock_timeout=10000"})
    try:
        result = rollback(engine, args.rollback, apply=args.apply) if args.rollback else publish(
            engine, args.input_dir.resolve(), baseline=args.baseline, apply=args.apply,
            allow_drop=args.allow_drop, reencode_baseline=args.reencode_baseline, historical_test=args.historical_test,
            restore_rankings=args.restore_rankings)
        catalog_failed = False
        if args.apply and result['status'] in {'published', 'already-published'} and not args.historical_test:
            from ..opinion_trades.publish_catalog import sync_active_content
            try:
                result['tradeCatalog'] = sync_active_content(engine, apply=True)
            except Exception:
                result['tradeCatalog'] = {
                    'status': 'failed',
                    'message': 'Content is active, but trade catalog sync failed; retry --active-content --apply',
                }
                catalog_failed = True
        if args.apply and not args.baseline and not args.restore_rankings and not args.rollback and not args.historical_test and enabled():
            try:
                result["notifications"] = drain(engine)
            except Exception:
                result["notifications"] = {"status": "pending", "message": "Publication committed; retry the APNs worker after checking configuration"}
        if args.input_dir:
            path = args.input_dir / ("supabase-publication.json" if args.apply else "supabase-validation.json")
            temporary = path.with_suffix(".tmp")
            temporary.write_text(json.dumps(result, indent=2) + "\n")
            temporary.replace(path)
        print(json.dumps(result, indent=2))
        if catalog_failed:
            raise SystemExit(1)
    except Exception as error:
        # SQLAlchemy/driver errors may include database addresses or connection details.
        print(json.dumps({"status": "failed", "errorType": type(error).__name__,
                          "message": str(error) if isinstance(error, ValueError) else "Publication failed; inspect locally without sharing credentials"}))
        raise SystemExit(1) from None
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
