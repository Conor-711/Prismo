from datetime import datetime, timedelta, timezone
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from services.client_api.content_release.models import Base, Active, Release, Page
from services.client_api.content_release.retention import prune


def test_prune_keeps_active_baseline_recent_and_grace(tmp_path):
    engine = create_engine('sqlite:///' + str(tmp_path/'db.sqlite'))
    Base.metadata.create_all(engine)  # Disposable test database only.
    now = datetime.now(timezone.utc)
    with Session(engine) as session, session.begin():
        for idx in range(8):
            old = now-timedelta(hours=96-idx*12)
            revision = f'{idx:064x}'
            session.add(Release(revision=revision, manifest={},
                provenance={'kind':'baseline' if idx == 0 else 'platform-refresh'}, created_at=old))
            session.add(Page(revision=revision, collection='smart-accounts', owner='a', page=0, payload={}))
        session.add(Active(channel='production', revision=f'{7:064x}', activated_at=now))
    preview = prune(engine, now=now)
    assert preview['eligible'] == 3 and preview['removed'] == 0
    assert prune(engine, apply=True, now=now)['removed'] == 3
    with Session(engine) as session:
        remaining = {r.revision for r in session.scalars(select(Release))}
        assert remaining == {f'{i:064x}' for i in (0,4,5,6,7)}
        assert {p.revision for p in session.scalars(select(Page))} == remaining
        assert session.get(Active,'production').revision == f'{7:064x}'
    engine.dispose()
