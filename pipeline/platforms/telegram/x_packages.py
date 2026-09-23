"""Read channel document updates and stage one bounded package at a time."""
from __future__ import annotations

import os
import shutil
import time
from pathlib import Path

import requests

from ..x.daily_package import MAX_BYTES

REMOTE_FILE_LIMIT = 20 * 1024 * 1024
LOCAL_SERVER_ROOT = Path('/var/lib/telegram-bot-api')
MIN_FREE = 6 * 1024**3


class TelegramTransportError(RuntimeError):
    pass


class TelegramBot:
    def __init__(self, token: str, *, base_url: str = 'https://api.telegram.org',
                 local_files: Path | None = None, session=None):
        if not token:
            raise ValueError('Telegram bot token is required')
        self.token = token
        self.base_url = base_url.rstrip('/')
        self.local_files = Path(local_files).resolve() if local_files else None
        self.session = session or requests.Session()

    def call(self, method: str, payload: dict) -> object:
        attempts = 3 if method in {'getUpdates', 'getFile'} else 1
        for attempt in range(attempts):
            try:
                response = self.session.post(f'{self.base_url}/bot{self.token}/{method}',
                                             json=payload, timeout=(10, 35))
                response.raise_for_status()
                body = response.json()
                if not body.get('ok'):
                    raise TelegramTransportError(f'telegram_{method}_rejected_{body.get("error_code", "unknown")}')
                return body['result']
            except requests.RequestException as exc:
                retryable = not isinstance(exc, requests.HTTPError) or (
                    exc.response is not None and exc.response.status_code in {429, 500, 502, 503, 504})
                if retryable and attempt + 1 < attempts:
                    time.sleep(0.5 * 2 ** attempt)
                    continue
                raise TelegramTransportError(f'telegram_{method}_unavailable') from None
            except (ValueError, KeyError):
                raise TelegramTransportError(f'telegram_{method}_unavailable') from None

    def updates(self, offset: int | None) -> list[dict]:
        payload = {'limit': 100, 'timeout': 0, 'allowed_updates': ['channel_post']}
        if offset is not None:
            payload['offset'] = offset
        return self.call('getUpdates', payload)

    def download(self, document: dict, target: Path) -> Path | None:
        size = int(document.get('file_size') or 0)
        if size < 1 or size > MAX_BYTES:
            raise TelegramTransportError('telegram_package_size_invalid')
        if self.local_files is None and size > REMOTE_FILE_LIMIT:
            raise TelegramTransportError('telegram_local_api_required')
        if shutil.disk_usage(target.parent).free < MIN_FREE + size * 3:
            raise TelegramTransportError('telegram_low_disk_space')
        info = self.call('getFile', {'file_id': document['file_id']})
        file_path = str(info.get('file_path') or '')
        if not file_path:
            raise TelegramTransportError('telegram_file_path_missing')
        temporary = target.with_suffix(target.suffix + '.part')
        temporary.unlink(missing_ok=True)
        cache_path = None
        try:
            if self.local_files:
                remote = Path(file_path)
                try:
                    relative = remote.relative_to(LOCAL_SERVER_ROOT)
                    cache_path = (self.local_files / relative).resolve(strict=True)
                    cache_path.relative_to(self.local_files)
                except (ValueError, OSError):
                    raise TelegramTransportError('telegram_local_file_path_invalid') from None
                if not cache_path.is_file() or cache_path.stat().st_size != size:
                    raise TelegramTransportError('telegram_local_file_incomplete')
                try:
                    os.link(cache_path, temporary)
                except OSError:
                    shutil.copyfile(cache_path, temporary)
            else:
                if file_path.startswith('/') or '..' in Path(file_path).parts:
                    raise TelegramTransportError('telegram_file_path_invalid')
                try:
                    with self.session.get(f'{self.base_url}/file/bot{self.token}/{file_path}',
                                          stream=True, timeout=(10, 90)) as response:
                        response.raise_for_status()
                        with temporary.open('wb') as output:
                            for chunk in response.iter_content(chunk_size=1024 * 1024):
                                output.write(chunk)
                except requests.RequestException:
                    raise TelegramTransportError('telegram_download_unavailable') from None
            if temporary.stat().st_size != size:
                raise TelegramTransportError('telegram_download_size_mismatch')
            temporary.replace(target)
            return cache_path
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
