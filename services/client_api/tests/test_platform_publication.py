import json
import uuid
from datetime import datetime, timezone, timedelta
import pytest
from sqlalchemy.orm import Session
from services.client_api.tests.test_supabase_content import baseline, engine
from services.client_api.content_release.publisher import publish, read_collections
from services.client_api.content_release.contract import encoded
from services.client_api.content_release.models import Active
from services.client_api.content_release.partition import load_partition
import hashlib


def release(tmp_path, source='youtube'):
    base = baseline(tmp_path)
    label = {'youtube': 'YouTube', 'reddit': 'Reddit'}[source]
    output = tmp_path / 'partition'
    output.mkdir()
    entries = {}
    for name in ['smart-accounts', 'smart-account-updates', 'smart-account-evidence']:
        item = json.loads((base / (name + '.json')).read_text())[0]
        item['platform'] = label
        if name == 'smart-accounts':
            item['id'] = source + ':new'
        else:
            item['id'] = str(uuid.uuid4())
            item['authorId'] = source + ':new'
        raw = encoded([item])
        (output / (name + '.json')).write_bytes(raw)
        entries[name] = {'count': 1, 'sha256': hashlib.sha256(raw).hexdigest()}
    manifest = {'version': 1, 'status': 'ready', 'platform': source, 'crawlComplete': True,
                'asOf': datetime.now(timezone.utc).isoformat(), 'sourceThrough': None, 'collections': entries,
                'crawlFrom': (datetime.now(timezone.utc)-timedelta(hours=6)).isoformat(),
                'crawlThrough': datetime.now(timezone.utc).isoformat()}
    (output / 'platform-manifest.json').write_bytes(encoded(manifest))
    return base, output


@pytest.mark.parametrize('source', ['youtube', 'reddit'])
def test_partition_preserves_other_sources_history_and_idempotence(engine, tmp_path, source):
    base, directory = release(tmp_path, source)
    first = publish(engine, base, baseline=True, apply=True)
    result = publish(engine, directory, apply=True)
    assert result['status'] == 'published'
    assert publish(engine, directory, apply=True)['status'] == 'already-published'
    with Session(engine) as session:
        before = read_collections(session, first['revision'])
        after = read_collections(session, result['revision'])
    for name in before:
        assert all(row in after[name] for row in before[name])
    signal = after['portfolio-signals'][0]
    assert ('on Reddit' if source == 'reddit' else 'on YouTube') in signal['evidence'][0]['metric']


def test_invalid_or_stale_partition_does_not_change_active(engine, tmp_path):
    base, directory = release(tmp_path)
    first = publish(engine, base, baseline=True, apply=True)
    path = directory / 'platform-manifest.json'
    manifest = json.loads(path.read_text())
    manifest['asOf'] = (datetime.now(timezone.utc) - timedelta(hours=7)).isoformat()
    path.write_bytes(encoded(manifest))
    with pytest.raises(ValueError, match='stale'):
        publish(engine, directory, apply=True)
    with Session(engine) as session:
        assert session.get(Active, 'production').revision == first['revision']
    manifest['crawlComplete'] = False
    path.write_bytes(encoded(manifest))
    with pytest.raises(ValueError, match='Incomplete'):
        load_partition(directory)
