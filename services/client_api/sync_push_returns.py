"""Seed ranking metrics using DML only, after the user applies the migration."""
import argparse
import json
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from .config import normalize_database_url
from .content_release.__main__ import publication_database_url
from .content_release.push_returns import read_returns, sync_returns


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    count = len(read_returns())
    if args.apply:
        url = make_url(normalize_database_url(publication_database_url()))
        if "dzyitinagewdfkzjkuiz" not in ((url.host or "") + (url.username or "")):
            raise ValueError("Expected the native iOS database")
        engine = create_engine(url, connect_args={"connect_timeout": 10, "options": "-c statement_timeout=15000"})
        if engine.dialect.name != "postgresql":
            raise ValueError("Use the native publication database")
        try:
            with Session(engine) as session, session.begin():
                count = sync_returns(session)
        finally:
            engine.dispose()
    print(json.dumps({"status": "synced" if args.apply else "validated", "metrics": count}))


if __name__ == "__main__":
    main()
