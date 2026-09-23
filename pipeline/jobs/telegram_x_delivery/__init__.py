"""Durable Telegram intake for the existing X publication queue."""
from __future__ import annotations

import fcntl
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

from ...domain.smart_voice.x_delivery_scope import frozen_x_authors, top_quartile_x_authors
from ...jobs.x_daily import write_json
from ...jobs.x_delivery import enqueue
from ...platforms.telegram.x_packages import TelegramBot, TelegramTransportError
from ...platforms.x.daily_package import stage_package

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CHANNEL_ID = -1004310606552
MAX_ATTEMPTS = 3


def _config() -> tuple[TelegramBot, int] | None:
    load_dotenv(ROOT / '.env')
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '').strip()
    if not token:
        return None
    channel_id = int(os.environ.get('TELEGRAM_CHANNEL_ID', str(DEFAULT_CHANNEL_ID)))
    base_url = os.environ.get('TELEGRAM_BOT_API_URL', 'https://api.telegram.org').strip().rstrip('/')
    local_files = None
    if base_url != 'https://api.telegram.org':
        configured = os.environ.get('TELEGRAM_LOCAL_FILES_DIR', '').strip()
        local_files = Path(configured) if configured else ROOT / 'data/runtime/telegram-bot-api'
    return TelegramBot(token, base_url=base_url, local_files=local_files), channel_id


def _receipt_path(inbox: Path, update_id: int) -> Path:
    return inbox / f'{update_id}.json'


def _identity(path: Path | None) -> dict | None:
    if not path or not path.is_file():
        return None
    stat = path.stat()
    return {'path': str(path.resolve()), 'device': stat.st_dev, 'inode': stat.st_ino, 'size': stat.st_size}


def _remove_owned_file(record: dict | None, parent: Path) -> bool:
    if not record:
        return True
    path = Path(record['path'])
    try:
        path.resolve().relative_to(parent.resolve())
        stat = path.stat()
    except FileNotFoundError:
        return True
    except (ValueError, OSError):
        return False
    if (stat.st_dev, stat.st_ino, stat.st_size) == (record['device'], record['inode'], record['size']):
        path.unlink()
        return True
    return False


def _filter_ranked_posts(raw: Path, selected: Path, inbox: Path) -> dict:
    snapshot = ROOT / 'data/inbox/x/ranking-snapshot.json'
    if snapshot.exists():
        ids, handles = frozen_x_authors(snapshot)
        ranking_at = json.loads(snapshot.read_text(encoding='utf-8'))['rankingAt']
    else:
        ids, handles = top_quartile_x_authors(str(ROOT / 'data/dev.db'))
        ranking_at = datetime.now(timezone.utc).isoformat()
    kept = 0
    selected.parent.mkdir(parents=True, exist_ok=True)
    temporary = selected.with_suffix('.part')
    with tempfile.TemporaryDirectory(prefix='telegram-stage-', dir=inbox) as staging:
        info = stage_package(raw, Path(staging))
        with temporary.open('wb') as output:
            for file in sorted(Path(staging).glob('tweets_*.jsonl')):
                with file.open('rb') as source:
                    for line in source:
                        if not line.strip():
                            continue
                        post = json.loads(line)
                        author_id = str(post.get('author_id') or '')
                        handle = str(post.get('author_handle') or '').casefold().lstrip('@')
                        if author_id in ids or (not author_id and handle in handles):
                            output.write(line if line.endswith(b'\n') else line + b'\n')
                            kept += 1
    if kept:
        temporary.replace(selected)
    else:
        temporary.unlink()
    return {'sourceHash': info['packageHash'], 'sourceRows': info['rows'],
            'selectedRows': kept, 'rankedAuthors': len(ids),
            'rankingAt': ranking_at,
            'rankedAuthorIds': sorted(ids)}


def sync(inbox: Path = ROOT / 'data/inbox/telegram', x_inbox: Path = ROOT / 'data/inbox/x',
         *, bot: TelegramBot | None = None, channel_id: int | None = None) -> dict:
    if bot is None:
        configured = _config()
        if configured is None:
            return {'status': 'unconfigured'}
        bot, channel_id = configured
    if channel_id is None:
        raise ValueError('Telegram channel ID is required')
    inbox = Path(inbox).resolve()
    inbox.mkdir(parents=True, exist_ok=True)
    with (inbox / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'status': 'busy'}
        state_path = inbox / 'state.json'
        state = json.loads(state_path.read_text()) if state_path.exists() else {}
        if state.get('status') == 'needs_attention':
            return {'status': 'needs_attention', 'updateId': state.get('failedUpdateId'),
                    'reason': state.get('reason')}
        updates = bot.updates(state.get('nextOffset'))
        if not isinstance(updates, list):
            raise TelegramTransportError('telegram_updates_invalid')
        for update in updates:
            update_id = int(update['update_id'])
            post = update.get('channel_post') or {}
            document = post.get('document') or {}
            name = str(document.get('file_name') or '')
            extension = Path(name).suffix.lower()
            if post.get('chat', {}).get('id') != channel_id or extension not in {'.zip', '.jsonl'}:
                state['nextOffset'] = update_id + 1
                write_json(state_path, state)
                continue
            raw = inbox / f'{update_id}{extension}'
            filtered = inbox / f'tweets_{update_id}.jsonl'
            receipt_path = _receipt_path(inbox, update_id)
            receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
            try:
                if not raw.exists():
                    cache_path = bot.download(document, raw)
                    receipt.update(raw=_identity(raw), cache=_identity(cache_path))
                    write_json(receipt_path, receipt)
                if not receipt.get('selected'):
                    selection = _filter_ranked_posts(raw, filtered, inbox)
                    receipt.update(selection=selection, raw=_identity(raw), selected=_identity(filtered))
                    write_json(receipt_path, receipt)
                if receipt['selection']['selectedRows']:
                    limit = int(os.environ.get('TELEGRAM_X_MAX_CALLS', '1000'))
                    item = enqueue(filtered, x_inbox, workers=2, max_calls=limit, skip_translation=False)
                    receipt.update(status='queued', packageHash=item['packageHash'])
                else:
                    receipt['status'] = 'no_ranked_posts'
                write_json(receipt_path, receipt)
                state.update(nextOffset=update_id + 1, status='ready', attempts=0)
                state.pop('failedUpdateId', None)
                state.pop('reason', None)
                write_json(state_path, state)
                if receipt['status'] == 'no_ranked_posts':
                    _cleanup_receipt(receipt_path, receipt, inbox, bot.local_files)
                return {'status': 'no_ranked_posts' if receipt['selection']['selectedRows'] == 0 else receipt['status'], 'updateId': update_id,
                        'selectedRows': receipt['selection']['selectedRows']}
            except Exception as exc:
                attempts = state.get('attempts', 0) + 1 if state.get('failedUpdateId') == update_id else 1
                reason = str(exc) if str(exc) in {
                    'telegram_local_api_required', 'telegram_low_disk_space', 'telegram_package_size_invalid'} else type(exc).__name__
                state.update(status='needs_attention' if attempts >= MAX_ATTEMPTS else 'retry',
                             attempts=attempts, failedUpdateId=update_id, reason=reason)
                write_json(state_path, state)
                return {'status': state['status'], 'updateId': update_id, 'reason': reason}
        return {'status': 'idle'}


def _cleanup_receipt(path: Path, receipt: dict, inbox: Path, local_files: Path | None) -> None:
    done = _remove_owned_file(receipt.get('selected'), inbox)
    done = _remove_owned_file(receipt.get('raw'), inbox) and done
    if receipt.get('cache'):
        done = bool(local_files) and _remove_owned_file(receipt['cache'], local_files) and done
    receipt['status'] = 'cleaned' if done else 'cleanup_pending'
    write_json(path, receipt)


def cleanup(inbox: Path = ROOT / 'data/inbox/telegram', x_inbox: Path = ROOT / 'data/inbox/x',
            *, local_files: Path | None = None) -> dict:
    inbox, x_inbox = Path(inbox).resolve(), Path(x_inbox).resolve()
    if not inbox.exists():
        return {'status': 'idle', 'cleaned': 0}
    if local_files is None:
        configured = _config()
        local_files = configured[0].local_files if configured else None
    cleaned = 0
    with (inbox / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {'status': 'busy', 'cleaned': 0}
        for receipt_path in inbox.glob('[0-9]*.json'):
            receipt = json.loads(receipt_path.read_text())
            if receipt.get('status') not in {'queued', 'cleanup_pending'}:
                continue
            if receipt.get('selection', {}).get('selectedRows') == 0:
                _cleanup_receipt(receipt_path, receipt, inbox, local_files)
                cleaned += receipt['status'] == 'cleaned'
                continue
            package_hash = receipt.get('packageHash', '')
            queue_path = x_inbox / f'{package_hash}.json'
            if not queue_path.exists():
                continue
            item = json.loads(queue_path.read_text())
            if item.get('status') != 'verified' or item.get('databaseVerified') is not True:
                continue
            _cleanup_receipt(receipt_path, receipt, inbox, local_files)
            cleaned += receipt['status'] == 'cleaned'
    return {'status': 'cleaned' if cleaned else 'idle', 'cleaned': cleaned}


def retry(inbox: Path = ROOT / 'data/inbox/telegram') -> dict:
    inbox = Path(inbox).resolve()
    state_path = inbox / 'state.json'
    if not state_path.exists():
        return {'status': 'idle'}
    with (inbox / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = json.loads(state_path.read_text())
        if state.get('status') != 'needs_attention':
            return {'status': state.get('status', 'idle')}
        state.update(status='retry', attempts=0)
        write_json(state_path, state)
        return {'status': 'retry', 'updateId': state.get('failedUpdateId')}


def cutover() -> dict:
    load_dotenv(ROOT / '.env')
    token = os.environ.get('TELEGRAM_BOT_TOKEN', '').strip()
    if not token:
        raise ValueError('TELEGRAM_BOT_TOKEN is not configured')
    result = TelegramBot(token).call('logOut', {})
    return {'status': 'logged_out' if result is True else 'unchanged'}
