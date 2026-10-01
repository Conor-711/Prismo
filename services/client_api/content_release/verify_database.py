"""Read back a committed revision; never substitute this for real-user API acceptance."""
import argparse
import json
import time
from pathlib import Path
from sqlalchemy import create_engine, select, func
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session
from .__main__ import publication_database_url
from ..config import normalize_database_url
from .contract import SCHEMAS, digest, pages
from .models import Active, Release, Page
from . import cache
from .publisher import read_collections


def _read_with_retry(engine, operation, *, attempts=3):
    for attempt in range(attempts):
        try:
            with Session(engine) as session:
                return operation(session)
        except OperationalError:
            engine.dispose()
            if attempt == attempts - 1:
                raise
            time.sleep(attempt + 1)


def verify(engine, revision):
    def load_release(session):
        active = session.get(Active, 'production')
        release = session.get(Release, revision)
        if not active or active.revision != revision or not release:
            raise ValueError('Active revision differs')
        return release.manifest

    manifest = _read_with_retry(engine, load_release)
    collections = cache.load(revision, manifest) if engine.dialect.name == 'postgresql' else None
    if collections is not None:
        expected_pages = {(name, owner, page): payload
                          for name, items in collections.items() for owner, page, payload in pages(revision, name, items)}
        count = _read_with_retry(engine, lambda session: session.scalar(
            select(func.count()).select_from(Page).where(Page.revision == revision)))
        if count != len(expected_pages):
            raise ValueError('Stored page count mismatch')
        for offset in range(0, count, 50):
            stored_pages = _read_with_retry(engine, lambda session: session.execute(
                select(Page.collection, Page.owner, Page.page, Page.payload)
                .where(Page.revision == revision)
                .order_by(Page.collection, Page.owner, Page.page)
                .limit(50).offset(offset)).all())
            if len(stored_pages) != min(50, count - offset) or any(
                expected_pages.get((name, owner, page)) != payload
                for name, owner, page, payload in stored_pages
            ):
                raise ValueError('Stored page mismatch')
    else:
        collections = _read_with_retry(engine, lambda session: read_collections(session, revision, use_cache=False))
    for name in SCHEMAS:
        items = sorted(collections[name], key=lambda row: row.get('id', row.get('ticker', '')))
        expected = manifest['collections'][name]
        if len(items) != expected['count'] or digest(items) != expected['sha256']:
            raise ValueError('Content readback mismatch: ' + name)
    active_revision = _read_with_retry(engine, lambda session: session.get(Active, 'production').revision)
    if active_revision != revision:
        raise ValueError('Active revision changed during verification')
    return {'revision': revision, 'databaseVerified': True, 'publicAPIVerified': False,
            'counts': {name: len(items) for name, items in collections.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    engine = create_engine(normalize_database_url(publication_database_url()), pool_pre_ping=True,
                           connect_args={'connect_timeout': 10, 'prepare_threshold': None, 'tcp_user_timeout': 600000, 'keepalives_idle': 10, 'keepalives_interval': 5, 'keepalives_count': 3, 'options': '-c statement_timeout=600000 -c lock_timeout=10000'})
    try:
        result = verify(engine, args.revision)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_suffix('.tmp')
        temporary.write_text(json.dumps(result, indent=2) + '\n')
        temporary.replace(args.output)
        print(json.dumps(result))
    except Exception as error:
        print(json.dumps({'status': 'failed', 'errorType': type(error).__name__}))
        raise SystemExit(1) from None
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
