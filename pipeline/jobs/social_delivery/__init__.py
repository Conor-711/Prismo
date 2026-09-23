"""Serial, bounded YouTube/Reddit refresh with retained last-good cloud content."""
import fcntl
from functools import partial
import json
import os
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ..x_daily import write_json
from ..x_delivery import ROOT, MIN_FREE, command


def run_source(source, root, *, executor=command, clock=lambda: datetime.now(timezone.utc), max_calls=300):
    root = Path(root) / source
    root.mkdir(parents=True, exist_ok=True)
    path = root / 'run.json'
    state = json.loads(path.read_text()) if path.exists() else {}
    current = clock()
    if state.get('status') == 'needs_attention':
        return state
    if state.get('status') == 'verified' and current - datetime.fromisoformat(state['until']) < timedelta(hours=3):
        return {'source': source, 'status': 'unchanged', 'revision': state.get('revision')}
    if not state or state.get('status') == 'verified':
        previous = datetime.fromisoformat(state['until']) if state else None
        since = previous - timedelta(hours=3) if previous else current - timedelta(hours=6)
        if current - since > timedelta(days=7):
            return {'source': source, 'status': 'needs_attention', 'reason': 'catchup_exceeds_seven_days'}
        # Catch up by at most six hours per wake so a delayed machine can
        # reduce lag without presenting a huge, unbounded analysis batch.
        until = min(current, previous + timedelta(hours=6)) if previous else current
        state = {'source': source, 'database': str(ROOT / 'data/dev.db'), 'status': 'queued', 'steps': {},
                 'since': since.isoformat(), 'until': until.isoformat(), 'attempts': 0, 'maxCalls': max_calls,
                 'lastVerifiedRevision': state.get('revision'),
                 'lastVerifiedUntil': state.get('until')}
    if state.get('attempts', 0) >= 3:
        state.update(status='needs_attention', reason='retry_limit')
        write_json(path, state)
        return state
    if shutil.disk_usage(ROOT).free < MIN_FREE:
        return {'source': source, 'status': 'needs_attention', 'reason': 'low_disk_space'}
    state.update(status='running', attempts=state['attempts'] + 1)
    write_json(path, state)
    env = {**os.environ, 'DATABASE_URL': 'sqlite:///' + state['database'], 'PRICE_DB': state['database'],
           'X_INGEST_ENABLED': 'false'}
    try:
        executor([str(ROOT / 'pipeline/.venv/bin/python'), '-m', 'pipeline.jobs.social_delivery.worker', str(path)],
                 root / 'process.log', timeout=1500, env=env)
        state = json.loads(path.read_text())
        if state.get('status') != 'ready':
            raise RuntimeError('processing_unconfirmed')
        release = root / 'release'
        python = str(ROOT / 'services/client_api/.venv/bin/python')
        executor([python, '-m', 'services.client_api.content_release', '--input-dir', str(release), '--apply'],
                 root / 'publish.log', timeout=600, env=env)
        receipt = json.loads((release / 'supabase-publication.json').read_text())
        if receipt['status'] not in {'published', 'already-published'}:
            raise RuntimeError('publication_unconfirmed')
        verification = root / 'verified.json'
        executor([python, '-m', 'services.client_api.content_release.verify_database', '--revision', receipt['revision'],
                 '--output', str(verification)], root / 'verify.log', timeout=600, env=env)
        verified = json.loads(verification.read_text())
        if verified.get('databaseVerified') is not True or verified.get('revision') != receipt['revision']:
            raise RuntimeError('verification_incomplete')
        state.update(status='verified', revision=receipt['revision'], databaseVerified=True,
                     publicAPIVerified=False, verifiedAt=clock().isoformat())
        state.pop('errorType', None)
        state.pop('reason', None)
    except Exception as error:
        # The worker has persisted completed steps even if a process was terminated.
        state = json.loads(path.read_text())
        state.update(status='needs_attention' if state['attempts'] >= 3 else 'retry', errorType=type(error).__name__)
    write_json(path, state)
    return state


def run(*, source='all', root=ROOT / 'data/runtime/social-delivery', executor=command):
    if source not in {'all', 'youtube', 'reddit'}:
        raise ValueError('Unknown source')
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    with (ROOT / 'data/.x-daily.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'status': 'busy'}
        # The parent holds the same local DB lock as the X workflow through verification.
        locked_executor = partial(executor, pass_fds=(lock.fileno(),))
        results = [run_source(s, root, executor=locked_executor) for s in (['youtube', 'reddit'] if source == 'all' else [source])]
        return {'status': 'checked', 'sources': results}
