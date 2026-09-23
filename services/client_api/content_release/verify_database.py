"""Read back a committed revision; never substitute this for real-user API acceptance."""
import argparse
import json
from pathlib import Path
from sqlalchemy import create_engine, text, select, func
from sqlalchemy.orm import Session
from .__main__ import publication_database_url
from ..config import normalize_database_url
from .contract import SCHEMAS, digest, pages
from .models import Active, Release, Page
from . import cache
from .publisher import read_collections


def verify(engine, revision):
    with Session(engine) as session:
        active = session.get(Active, 'production')
        release = session.get(Release, revision)
        if not active or active.revision != revision or not release:
            raise ValueError('Active revision differs')
        collections = cache.load(revision, release.manifest) if engine.dialect.name == 'postgresql' else None
        if collections is not None:
            expected = [dict(collection=name, owner=owner, page=page, payload=payload)
                        for name, items in collections.items() for owner, page, payload in pages(revision,name,items)]
            for offset in range(0,len(expected),5):
                batch=expected[offset:offset+5]
                matched=session.scalar(text("""
                    with expected as (
                      select * from jsonb_to_recordset(cast(:batch as jsonb))
                      as x(collection text, owner text, page integer, payload jsonb)
                    ) select count(*) from expected e join public.bsmart_content_pages p
                      on p.revision=:revision and p.collection=e.collection and p.owner=e.owner and p.page=e.page
                    where p.payload=e.payload
                """), {'batch':json.dumps(batch), 'revision':revision})
                if matched != len(batch):
                    raise ValueError('Stored page mismatch')
            if session.scalar(select(func.count()).select_from(Page).where(Page.revision==revision)) != len(expected):
                raise ValueError('Stored page count mismatch')
        else:
            collections = read_collections(session, revision, use_cache=False)
        for name in SCHEMAS:
            items = sorted(collections[name], key=lambda row: row.get('id', row.get('ticker', '')))
            expected = release.manifest['collections'][name]
            if len(items) != expected['count'] or digest(items) != expected['sha256']:
                raise ValueError('Content readback mismatch: ' + name)
        session.expire(active)
        if active.revision != revision:
            raise ValueError('Active revision changed during verification')
        return {'revision': revision, 'databaseVerified': True, 'publicAPIVerified': False,
                'counts': {name: len(items) for name, items in collections.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    engine = create_engine(normalize_database_url(publication_database_url()), pool_pre_ping=True,
                           connect_args={'connect_timeout': 10, 'prepare_threshold': None, 'tcp_user_timeout': 20000, 'keepalives_idle': 10, 'keepalives_interval': 5, 'keepalives_count': 3, 'options': '-c statement_timeout=30000 -c lock_timeout=10000'})
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
