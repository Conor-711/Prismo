from datetime import datetime, timedelta, timezone
import pytest
from sqlalchemy import create_engine, select, event
from sqlalchemy.orm import Session
from services.client_api.content_release.models import Base, Active, Release, Page
from services.client_api.content_release.retention import prune
from services.client_api.content_release import retention


def seeded_engine(tmp_path):
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
    return engine, now


def test_prune_keeps_active_baseline_recent_and_grace(tmp_path):
    engine, now = seeded_engine(tmp_path)
    preview = prune(engine, now=now)
    assert preview['eligible'] == 3 and preview['removed'] == 0
    assert prune(engine, apply=True, now=now)['removed'] == 3
    with Session(engine) as session:
        remaining = {r.revision for r in session.scalars(select(Release))}
        assert remaining == {f'{i:064x}' for i in (0,4,5,6,7)}
        assert {p.revision for p in session.scalars(select(Page))} == remaining
        assert session.get(Active,'production').revision == f'{7:064x}'
    engine.dispose()


def test_prune_resumes_after_a_failed_batch(tmp_path):
    engine, now = seeded_engine(tmp_path)
    deletions = 0

    def interrupt(connection, cursor, statement, parameters, context, executemany):
        nonlocal deletions
        if statement.startswith('DELETE FROM bsmart_content_pages'):
            deletions += 1
            if deletions == 2:
                raise RuntimeError('simulated disconnect')

    event.listen(engine, 'before_cursor_execute', interrupt)
    with pytest.raises(RuntimeError, match='simulated disconnect'):
        prune(engine, apply=True, now=now)
    event.remove(engine, 'before_cursor_execute', interrupt)
    with Session(engine) as session:
        assert session.get(Release, f'{1:064x}') is None
        assert session.get(Release, f'{2:064x}') is not None
        assert session.get(Active, 'production').revision == f'{7:064x}'
    assert prune(engine, apply=True, now=now)['removed'] == 2
    assert prune(engine, apply=True, now=now)['removed'] == 0
    engine.dispose()


def test_prune_rechecks_active_between_batches(tmp_path, monkeypatch):
    engine, now = seeded_engine(tmp_path)
    original = retention.plan
    calls = 0

    def changed_active(session, clock):
        nonlocal calls
        calls += 1
        if calls == 2:
            session.get(Active, 'production').revision = f'{1:064x}'
            session.flush()
        return original(session, clock)

    monkeypatch.setattr(retention, 'plan', changed_active)
    result = prune(engine, apply=True, now=now)
    assert result['removed'] == 2
    assert result['activeRevision'] == f'{1:064x}'
    with Session(engine) as session:
        assert session.get(Release, f'{1:064x}') is not None
        assert session.get(Release, f'{0:064x}') is not None
    engine.dispose()
