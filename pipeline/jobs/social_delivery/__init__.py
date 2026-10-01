"""Serial, bounded YouTube/Reddit refresh with retained last-good cloud content."""
import fcntl
from functools import partial
import json
import os
import shutil
from datetime import datetime, time, timedelta, timezone
from pathlib import Path

from ..x_daily import write_json
from ..x_delivery import ROOT, MIN_FREE, command


def run_source(source, root, *, executor=command, clock=lambda: datetime.now(timezone.utc), max_calls=300,
               lookback_hours=None):
    if lookback_hours is not None and (source != 'reddit' or not 1 <= lookback_hours <= 168):
        raise ValueError('Explicit lookback requires Reddit and 1..168 hours')
    root = Path(root) / source
    root.mkdir(parents=True, exist_ok=True)
    path = root / 'run.json'
    state = json.loads(path.read_text()) if path.exists() else {}
    if lookback_hours is not None and state and state.get('lookbackHours') != lookback_hours:
        raise ValueError('Use a separate run directory for an explicit lookback')
    current = clock()
    target = current - timedelta(hours=1) if source == 'reddit' else current
    if state.get('status') == 'needs_attention':
        return state
    if state.get('status') == 'deferred':
        if current < datetime.fromisoformat(state['retryAfter']):
            return {'source': source, 'status': 'deferred', 'retryAfter': state['retryAfter'],
                    'lastVerifiedRevision': state.get('lastVerifiedRevision')}
        state['status'] = 'retry'
        state.pop('retryAfter', None)
    if state.get('status') == 'verified' and target - datetime.fromisoformat(state['until']) < timedelta(hours=3):
        return {'source': source, 'status': 'unchanged', 'revision': state.get('revision')}
    if not state or state.get('status') == 'verified':
        previous = datetime.fromisoformat(state['until']) if state else None
        since = (target - timedelta(hours=lookback_hours) if lookback_hours is not None else
                 previous - timedelta(hours=3) if previous else target - timedelta(hours=6))
        if target - since > timedelta(days=7):
            return {'source': source, 'status': 'needs_attention', 'reason': 'catchup_exceeds_seven_days'}
        # Catch up by at most six hours per wake so a delayed machine can
        # reduce lag without presenting a huge, unbounded analysis batch.
        until = min(target, previous + timedelta(hours=6)) if previous and lookback_hours is None else target
        state = {'source': source, 'database': str(ROOT / 'data/dev.db'), 'status': 'queued', 'steps': {},
                 'since': since.isoformat(), 'until': until.isoformat(), 'attempts': 0, 'maxCalls': max_calls,
                 'lastVerifiedRevision': state.get('revision'),
                 'lastVerifiedUntil': state.get('until')}
        if lookback_hours is not None:
            state['lookbackHours'] = lookback_hours
    if state.get('attempts', 0) >= 3:
        state.update(status='needs_attention', reason='retry_limit')
        write_json(path, state)
        return state
    if shutil.disk_usage(ROOT).free < MIN_FREE:
        return {'source': source, 'status': 'needs_attention', 'reason': 'low_disk_space'}
    state.update(status='running', attempts=state['attempts'] + 1)
    state.pop('reason', None)
    state.pop('errorType', None)
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
                 root / 'publish.log', timeout=1200, env=env)
        receipt = json.loads((release / 'supabase-publication.json').read_text())
        if receipt['status'] not in {'published', 'already-published'}:
            raise RuntimeError('publication_unconfirmed')
        verification = root / 'verified.json'
        executor([python, '-m', 'services.client_api.content_release.verify_database', '--revision', receipt['revision'],
                 '--output', str(verification)], root / 'verify.log', timeout=1800, env=env)
        verified = json.loads(verification.read_text())
        if verified.get('databaseVerified') is not True or verified.get('revision') != receipt['revision']:
            raise RuntimeError('verification_incomplete')
        state.update(status='verified', revision=receipt['revision'], databaseVerified=True,
                     publicAPIVerified=False, verifiedAt=clock().isoformat())
        state.pop('errorType', None)
        state.pop('reason', None)
        state.pop('retryAfter', None)
    except Exception as error:
        # The worker has persisted completed steps even if a process was terminated.
        state = json.loads(path.read_text())
        if state.get('reason') == 'youtube_rate_limited':
            state['errorType'] = type(error).__name__
            if state['attempts'] >= 3:
                state['status'] = 'needs_attention'
            else:
                next_day = clock().astimezone(timezone.utc).date() + timedelta(days=1)
                state.update(status='deferred',
                             retryAfter=datetime.combine(next_day, time(0, 15), timezone.utc).isoformat())
        else:
            state.update(status='needs_attention' if state['attempts'] >= 3 else 'retry',
                         errorType=type(error).__name__)
    write_json(path, state)
    return state


def run(*, source='all', root=ROOT / 'data/runtime/social-delivery', executor=command, lookback_hours=None):
    if source not in {'all', 'youtube', 'reddit'}:
        raise ValueError('Unknown source')
    if lookback_hours is not None and source != 'reddit':
        raise ValueError('Explicit lookback requires Reddit')
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    with (ROOT / 'data/.x-daily.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'status': 'busy'}
        # The parent holds the same local DB lock as the X workflow through verification.
        locked_executor = partial(executor, pass_fds=(lock.fileno(),))
        results = [run_source(s, root, executor=locked_executor, lookback_hours=lookback_hours)
                   for s in (['youtube', 'reddit'] if source == 'all' else [source])]
        return {'status': 'checked', 'sources': results}
