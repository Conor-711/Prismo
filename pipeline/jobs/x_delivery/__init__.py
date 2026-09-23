"""Durable local queue for supplied X packages; no crawler or production DDL."""
from __future__ import annotations

import fcntl
import json
import os
import re
import signal
import subprocess
import tempfile
from datetime import datetime, timezone, timedelta
from pathlib import Path
import shutil
from urllib.request import getproxies

from ...platforms.x.daily_package import stage_package
from ..x_daily import write_json

ROOT = Path(__file__).resolve().parents[3]
MIN_FREE = 4 * 1024**3
MAX_ATTEMPTS = 3


def now():
    return datetime.now(timezone.utc).isoformat()


def retry(inbox, package_hash, reason):
    inbox = Path(inbox).resolve()
    if not re.fullmatch(r'[0-9a-f]{64}', package_hash) or not reason.strip():
        raise ValueError('A package hash and retry reason are required')
    with (inbox / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        path = inbox / (package_hash + '.json')
        item = json.loads(path.read_text())
        if item['status'] != 'needs_attention':
            raise ValueError('Only a needs_attention job can be retried')
        item.update(status='queued', totalAttempts=item.get('totalAttempts', item['attempts']),
                    attempts=0, retryCycle=item.get('retryCycle', 0) + 1,
                    lastRetryReason=reason.strip(), updatedAt=now())
        item.pop('error', None)
        item.pop('reason', None)
        write_json(path, item)
        return item


def enqueue(package, inbox, *, workers=2, max_calls=1000, skip_translation=False):
    source, inbox = Path(package).resolve(), Path(inbox).resolve()
    if not source.is_file() or source.is_symlink() or source.suffix.lower() not in {'.zip', '.jsonl'}:
        raise ValueError('Expected a completed ZIP or JSONL file')
    if not 1 <= workers <= 16 or max_calls < 1:
        raise ValueError('Invalid processing limits')
    if shutil.disk_usage(source.parent).free < MIN_FREE:
        raise ValueError('At least 4 GiB free disk space is required')
    inbox.mkdir(parents=True, exist_ok=True)
    with (inbox / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = source.stat()
        with tempfile.TemporaryDirectory(prefix='inspect-', dir=inbox) as staging:
            info = stage_package(source, Path(staging))
        after = source.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise ValueError('Package changed during inspection')
        path = inbox / (info['packageHash'] + '.json')
        if path.exists():
            saved = json.loads(path.read_text())
            if saved['status'] != 'verified':
                saved['package'] = str(source)
                write_json(path, saved)
            return saved
        item = {k: info[k] for k in ['packageHash', 'rows', 'sourceFrom', 'sourceThrough']}
        item.update(package=str(source), status='queued', attempts=0, enqueuedAt=now(),
                    workers=workers, maxCalls=max_calls, skipTranslation=skip_translation)
        write_json(path, item)
        return item


def command(args, log, *, timeout=9000, env=None, pass_fds=()):
    """Bound the whole subprocess tree; don't leave a worker holding the DB lock."""
    timed_out = False
    with log.open('wb') as output:
        process = subprocess.Popen(args, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True, pass_fds=pass_fds)
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            timed_out = True
            status = process.returncode
    # Keep useful recent diagnostics without unbounded local logs.
    if log.stat().st_size > 1024**2:
        with log.open('rb') as stream:
            stream.seek(-1024**2, 2)
            tail = stream.read()
        log.write_bytes(tail)
    if timed_out:
        raise RuntimeError('worker_timeout')
    if status:
        raise RuntimeError('worker_failed')


def _publication_environment():
    environment = {**os.environ, 'BSMART_CONTENT_PUBLISH_TARGET': 'supabase', 'X_INGEST_ENABLED': 'false'}
    for scheme, proxy in getproxies().items():
        if scheme in {'http', 'https'} and proxy:
            environment.setdefault(f'{scheme.upper()}_PROXY', proxy)
    return environment


def process(item, inbox):
    if shutil.disk_usage(ROOT).free < MIN_FREE:
        raise RuntimeError('low_disk_space')
    # Re-read the complete source; a different file must never inherit a queued identity.
    with tempfile.TemporaryDirectory(prefix='verify-', dir=inbox) as staging:
        info = stage_package(Path(item['package']), Path(staging))
    if info['packageHash'] != item['packageHash']:
        raise ValueError('package_changed')
    through = datetime.fromisoformat(info['sourceThrough'])
    if through < datetime.now(timezone.utc) - timedelta(hours=96):
        raise ValueError('stale_package')
    environment = _publication_environment()
    args = [str(ROOT / 'pipeline/.venv/bin/python'), '-m', 'pipeline.manage', 'x-daily',
            '--package', item['package'], '--apply', '--workers', str(item['workers']),
            '--max-calls', str(item['maxCalls']), '--reading-package-only']
    if item['skipTranslation']:
        args.append('--skip-translation')
    command(args, inbox / (item['packageHash'] + '.log'), env=environment,
            timeout=int(os.environ.get('BSMART_X_DELIVERY_TIMEOUT', '9000')))
    release = ROOT / 'data/runtime/x-daily' / item['packageHash'] / 'release'
    python = str(ROOT / 'services/client_api/.venv/bin/python')
    # Publisher is idempotent; a crash after commit is recovered by the next run.
    command([python, '-m', 'services.client_api.content_release', '--input-dir', str(release), '--apply'],
            inbox / (item['packageHash'] + '.publish.log'), timeout=600, env=environment)
    receipt = json.loads((release / 'supabase-publication.json').read_text())
    if receipt['status'] not in {'published', 'already-published'}:
        raise RuntimeError('publication_unconfirmed')
    verification = inbox / (item['packageHash'] + '.verified.json')
    command([python, '-m', 'services.client_api.content_release.verify_database', '--revision', receipt['revision'],
             '--output', str(verification)], inbox / (item['packageHash'] + '.verify.log'), timeout=600, env=environment)
    return json.loads(verification.read_text())


def run(inbox, *, processor=process):
    inbox = Path(inbox).resolve()
    inbox.mkdir(parents=True, exist_ok=True)
    with (inbox / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'status': 'busy'}
        jobs = []
        blocked = 0
        for path in inbox.glob('*.json'):
            if len(path.stem) != 64 or any(c not in '0123456789abcdef' for c in path.stem):
                continue
            item = json.loads(path.read_text())
            if item['status'] in {'queued', 'running', 'retry'}:
                jobs.append((path, item))
            elif item['status'] == 'needs_attention':
                blocked += 1
        if not jobs:
            if blocked:
                return {'status': 'needs_attention', 'blocked': blocked}
            return {'status': 'idle'}
        # One package per wake; chronology and bounded work prevent overlap/starvation.
        path, item = min(jobs, key=lambda pair: (pair[1]['sourceThrough'], pair[1]['enqueuedAt']))
        if item['attempts'] >= MAX_ATTEMPTS:
            item.update(status='needs_attention', error='retry_limit', updatedAt=now())
            write_json(path, item)
            return item
        item.update(status='running', attempts=item['attempts'] + 1,
                    totalAttempts=item.get('totalAttempts', item['attempts']) + 1, updatedAt=now())
        write_json(path, item)
        try:
            result = processor(item, inbox)
            if result.get('databaseVerified') is not True:
                raise RuntimeError('verification_incomplete')
            item.update(status='verified', revision=result['revision'], databaseVerified=True,
                        publicAPIVerified=False, updatedAt=now())
            item.pop('error', None)
            item.pop('reason', None)
        except Exception as error:
            # Keep credentials/server exception bodies out of the queue receipt.
            item.update(status='needs_attention' if isinstance(error, (ValueError, FileNotFoundError))
                        or item['attempts'] >= MAX_ATTEMPTS else 'retry',
                        error=type(error).__name__, reason=str(error) if str(error) in {
                            'stale_package', 'package_changed', 'low_disk_space', 'verification_incomplete',
                            'worker_failed', 'worker_timeout', 'publication_unconfirmed'} else 'inspect_local_log', updatedAt=now())
        write_json(path, item)
        return item
