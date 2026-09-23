"""Bound redundant immutable release snapshots after a verified publication."""
import argparse
import json
from datetime import datetime, timedelta, timezone
from sqlalchemy import create_engine, select, text, delete
from sqlalchemy.orm import Session
from .__main__ import publication_database_url
from ..config import normalize_database_url
from .models import Active, Release, Page


def plan(session, now, *, keep_recent=4, grace_hours=48):
    active = session.get(Active, 'production')
    if not active:
        raise ValueError('No active content release')
    releases = session.scalars(select(Release).order_by(Release.created_at.desc(), Release.revision.desc())).all()
    cutoff = now - timedelta(hours=grace_hours)
    protected = {active.revision, *(release.revision for release in releases[:keep_recent])}
    protected.update(release.revision for release in releases
                     if release.provenance.get('kind') == 'baseline')
    eligible = [release.revision for release in releases
                if (release.created_at.replace(tzinfo=timezone.utc)
                    if release.created_at.tzinfo is None else release.created_at) < cutoff
                and release.revision not in protected]
    return {'activeRevision': active.revision, 'eligible': eligible,
            'retained': len(releases) - len(eligible)}


def prune(engine, *, apply=False, now=None):
    now = now or datetime.now(timezone.utc)
    with Session(engine) as session, session.begin():
        if engine.dialect.name == 'postgresql':
            session.execute(text('select pg_advisory_xact_lock(721534915)'))
        result = plan(session, now)
        if apply:
            for revision in result['eligible']:
                session.execute(delete(Page).where(Page.revision == revision))
                session.execute(delete(Release).where(Release.revision == revision))
    return {'status': 'pruned' if apply else 'planned',
            'activeRevision': result['activeRevision'],
            'removed': len(result['eligible']) if apply else 0,
            'eligible': len(result['eligible']), 'retained': result['retained']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    url = publication_database_url()
    if not url.startswith(('postgresql', 'postgres://')):
        parser.error('Set protected BSMART_CONTENT_DATABASE_URL')
    engine = create_engine(normalize_database_url(url), pool_pre_ping=True,
        connect_args={'connect_timeout':10, 'prepare_threshold':None, 'tcp_user_timeout':20000,
                      'options':'-c statement_timeout=30000 -c lock_timeout=10000'})
    try:
        print(json.dumps(prune(engine, apply=args.apply)))
    except Exception as error:
        print(json.dumps({'status':'failed', 'errorType':type(error).__name__}))
        raise SystemExit(1) from None
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
