import json
import sqlite3
from datetime import datetime, timezone

import requests

from pipeline.domain.smart_voice.x_delivery_scope import top_quartile_x_authors
from pipeline.jobs import telegram_x_delivery as job
from pipeline.platforms.telegram.x_packages import TelegramTransportError


def _post(tweet_id, author_id, handle):
    return {
        'tweet_id': tweet_id,
        'created_at': datetime.now(timezone.utc).isoformat(),
        'author_id': author_id,
        'author_handle': handle,
        'text': '$AAPL looks interesting',
        'cashtags': ['AAPL'],
    }


class FakeBot:
    def __init__(self, root, *, fail=False):
        self.local_files = root / 'cache'
        self.local_files.mkdir()
        self.cache = self.local_files / 'document.jsonl'
        self.cache.write_text('\n'.join(json.dumps(item) for item in [
            _post('1', 'top', 'TopAuthor'), _post('2', 'other', 'OtherAuthor')]) + '\n')
        self.fail = fail
        self.calls = []

    def updates(self, offset):
        self.calls.append(offset)
        if offset is not None and offset > 101:
            return []
        return [{'update_id': 101, 'channel_post': {
            'chat': {'id': job.DEFAULT_CHANNEL_ID},
            'document': {'file_name': 'tweets_today.jsonl', 'file_size': self.cache.stat().st_size},
        }}]

    def download(self, document, target):
        if self.fail:
            raise TelegramTransportError('telegram_download_unavailable')
        target.write_bytes(self.cache.read_bytes())
        return self.cache


def test_rank_before_filter_uses_formal_score(tmp_path):
    database = tmp_path / 'ranking.db'
    connection = sqlite3.connect(database)
    connection.execute('''CREATE TABLE sv_investor_score
        (investor_id TEXT, handle TEXT, source TEXT, n_eff INTEGER, settled_calls INTEGER,
         platform_scores_json TEXT, sv REAL)''')
    for rank in range(4):
        connection.execute('INSERT INTO sv_investor_score VALUES (?,?,?,?,?,?,?)',
                           (str(rank), f'Author{rank}', 'x', 8, 10,
                            json.dumps({'x': 100-rank}), 100-rank))
    connection.commit()
    connection.close()
    assert top_quartile_x_authors(str(database)) == ({'0'}, {'author0'})


def test_only_ranked_posts_enqueue_full_translation_and_cleanup_after_verification(tmp_path, monkeypatch):
    monkeypatch.setattr(job, 'ROOT', tmp_path)
    monkeypatch.setattr(job, 'top_quartile_x_authors', lambda _db: ({'top'}, {'topauthor'}))
    bot = FakeBot(tmp_path)
    inbox, x_inbox = tmp_path / 'telegram', tmp_path / 'x'
    result = job.sync(inbox, x_inbox, bot=bot, channel_id=job.DEFAULT_CHANNEL_ID)
    assert result == {'status': 'queued', 'updateId': 101, 'selectedRows': 1}
    receipt = json.loads((inbox / '101.json').read_text())
    assert receipt['selection']['rankedAuthorIds'] == ['top']
    assert receipt['selection']['rankingAt']
    queued_path = x_inbox / f"{receipt['packageHash']}.json"
    queued = json.loads(queued_path.read_text())
    assert queued['skipTranslation'] is False
    assert queued['rows'] == 1
    assert json.loads((inbox / 'tweets_101.jsonl').read_text())['author_id'] == 'top'
    assert job.sync(inbox, x_inbox, bot=bot, channel_id=job.DEFAULT_CHANNEL_ID)['status'] == 'idle'
    assert job.cleanup(inbox, x_inbox, local_files=bot.local_files)['cleaned'] == 0
    assert bot.cache.exists()
    queued.update(status='verified', databaseVerified=True, revision='a'*64)
    queued_path.write_text(json.dumps(queued))
    assert job.cleanup(inbox, x_inbox, local_files=None)['cleaned'] == 0
    assert json.loads((inbox / '101.json').read_text())['status'] == 'cleanup_pending'
    assert job.cleanup(inbox, x_inbox, local_files=bot.local_files)['cleaned'] == 1
    assert not bot.cache.exists()
    assert not (inbox / '101.jsonl').exists()
    assert not (inbox / 'tweets_101.jsonl').exists()
    assert job.cleanup(inbox, x_inbox, local_files=bot.local_files)['cleaned'] == 0


def test_retry_is_bounded_and_requires_explicit_release(tmp_path, monkeypatch):
    monkeypatch.setattr(job, 'ROOT', tmp_path)
    bot = FakeBot(tmp_path, fail=True)
    inbox, x_inbox = tmp_path / 'telegram', tmp_path / 'x'
    for status in ['retry', 'retry', 'needs_attention']:
        assert job.sync(inbox, x_inbox, bot=bot, channel_id=job.DEFAULT_CHANNEL_ID)['status'] == status
    assert job.sync(inbox, x_inbox, bot=bot, channel_id=job.DEFAULT_CHANNEL_ID)['status'] == 'needs_attention'
    assert len(bot.calls) == 3
    assert job.retry(inbox)['status'] == 'retry'


def test_remote_large_document_requires_local_bot_api(tmp_path):
    class Session:
        def post(self, *_args, **_kwargs):
            raise AssertionError('Oversized remote file must fail before getFile')

        def get(self, *_args, **_kwargs):
            raise AssertionError('Remote download must not run')

    from pipeline.platforms.telegram.x_packages import TelegramBot
    bot = TelegramBot('secret', session=Session())
    try:
        bot.download({'file_size': 21 * 1024 * 1024, 'file_id': 'f'}, tmp_path / 'file.jsonl')
    except TelegramTransportError as exc:
        assert str(exc) == 'telegram_local_api_required'
    else:
        raise AssertionError('Expected size guard')


def test_config_defaults_to_public_bot_api(tmp_path, monkeypatch):
    monkeypatch.setattr(job, 'ROOT', tmp_path)
    monkeypatch.setenv('TELEGRAM_BOT_TOKEN', 'test-token')
    monkeypatch.delenv('TELEGRAM_BOT_API_URL', raising=False)
    monkeypatch.setenv('TELEGRAM_LOCAL_FILES_DIR', './unused-local-cache')
    bot, channel_id = job._config()
    assert bot.base_url == 'https://api.telegram.org'
    assert bot.local_files is None
    assert channel_id == job.DEFAULT_CHANNEL_ID


def test_read_only_bot_call_retries_transient_connection_error(monkeypatch):
    from pipeline.platforms.telegram import x_packages

    class Session:
        calls = 0

        def post(self, *_args, **_kwargs):
            self.calls += 1
            if self.calls == 1:
                raise requests.exceptions.SSLError('temporary TLS failure')

            class Response:
                def raise_for_status(self):
                    pass

                def json(self):
                    return {'ok': True, 'result': []}

            return Response()

    monkeypatch.setattr(x_packages.time, 'sleep', lambda _seconds: None)
    session = Session()
    assert x_packages.TelegramBot('secret', session=session).updates(None) == []
    assert session.calls == 2
