import json
from datetime import datetime, timezone, timedelta
from pathlib import Path
from types import SimpleNamespace
import pytest
from pipeline.jobs.social_delivery import run_source
from pipeline.platforms.reddit.incremental import fetch_window, collect
from pipeline.platforms.youtube.incremental import channel_window

NOW = datetime.now(timezone.utc)


@pytest.fixture(autouse=True)
def sufficient_disk_for_orchestration_tests(monkeypatch):
    monkeypatch.setattr('pipeline.jobs.social_delivery.shutil.disk_usage',
                        lambda _: SimpleNamespace(free=20 * 1024**3))


def test_explicit_reddit_backfill_uses_48_hours_and_resumes_same_window(tmp_path):
    def stop(*args, **kwargs):
        raise RuntimeError('temporary')
    first = run_source('reddit', tmp_path, executor=stop, clock=lambda: NOW, lookback_hours=48)
    assert datetime.fromisoformat(first['until']) == NOW-timedelta(hours=1)
    assert datetime.fromisoformat(first['since']) == NOW-timedelta(hours=49)
    second = run_source('reddit', tmp_path, executor=stop, clock=lambda: NOW+timedelta(hours=3), lookback_hours=48)
    assert second['since'] == first['since'] and second['until'] == first['until']
    with pytest.raises(ValueError, match='separate run directory'):
        run_source('reddit', tmp_path, lookback_hours=24)


@pytest.mark.parametrize('source,hours', [('youtube',48), ('reddit',0), ('reddit',169)])
def test_explicit_backfill_rejects_invalid_scope(tmp_path, source, hours):
    with pytest.raises(ValueError):
        run_source(source, tmp_path, lookback_hours=hours)


def test_failure_retries_same_window_without_advancing(tmp_path):
    calls = []
    def fail(*args, **kwargs):
        calls.append(args)
        raise RuntimeError('secret must not leak')
    results = [run_source('reddit', tmp_path, executor=fail, clock=lambda: NOW) for _ in range(4)]
    assert len(calls) == 3
    assert [r['status'] for r in results] == ['retry', 'retry', 'needs_attention', 'needs_attention']
    assert len({r['since'] for r in results}) == 1
    assert 'secret' not in (tmp_path / 'reddit/run.json').read_text()


def test_crash_after_publication_recovers_same_release(tmp_path):
    publish_timeouts = []
    verify_timeouts = []
    def execute(args, log, **kwargs):
        root = tmp_path / 'youtube'
        if 'pipeline.jobs.social_delivery.worker' in args:
            p = root / 'run.json'
            state = json.loads(p.read_text())
            state['status'] = 'ready'
            p.write_text(json.dumps(state))
        elif '--apply' in args:
            publish_timeouts.append(kwargs['timeout'])
            (root / 'release').mkdir(exist_ok=True)
            (root / 'release/supabase-publication.json').write_text(json.dumps({'status':'already-published', 'revision':'abc'}))
        else:
            verify_timeouts.append(kwargs['timeout'])
            (root / 'verified.json').write_text(json.dumps({'databaseVerified':True,'revision':'abc'}))
    result = run_source('youtube', tmp_path, executor=execute, clock=lambda: NOW)
    assert result['status'] == 'verified'
    assert publish_timeouts == [1200]
    assert verify_timeouts == [1800]
    assert run_source('youtube', tmp_path, executor=execute, clock=lambda: NOW)['status'] == 'unchanged'
    next_run = run_source('youtube', tmp_path, executor=execute, clock=lambda: NOW + timedelta(hours=3))
    assert datetime.fromisoformat(next_run['since']) == NOW - timedelta(hours=3)


def test_catchup_window_is_bounded_after_sleep(tmp_path):
    path = tmp_path / 'reddit/run.json'
    path.parent.mkdir()
    path.write_text(json.dumps({'source':'reddit', 'status':'verified', 'until':NOW.isoformat(),
                                'revision':'prior'}))
    def stop(*args, **kwargs):
        raise RuntimeError('temporary')
    result = run_source('reddit', tmp_path, executor=stop, clock=lambda: NOW+timedelta(hours=12))
    assert datetime.fromisoformat(result['until']) == NOW+timedelta(hours=6)
    assert datetime.fromisoformat(result['since']) == NOW-timedelta(hours=3)
    assert result['lastVerifiedRevision'] == 'prior'


def test_reddit_window_keeps_one_hour_provider_lag(tmp_path):
    path = tmp_path / 'reddit/run.json'
    path.parent.mkdir()
    path.write_text(json.dumps({'source':'reddit', 'status':'verified',
                                'until':(NOW-timedelta(hours=2)).isoformat(), 'revision':'prior'}))
    assert run_source('reddit', tmp_path, clock=lambda: NOW)['status'] == 'unchanged'
    path.write_text(json.dumps({'source':'reddit', 'status':'verified',
                                'until':(NOW-timedelta(hours=5)).isoformat(), 'revision':'prior'}))
    def stop(*args, **kwargs):
        raise RuntimeError('temporary')
    result = run_source('reddit', tmp_path, executor=stop, clock=lambda: NOW)
    assert datetime.fromisoformat(result['until']) == NOW-timedelta(hours=1)
    assert datetime.fromisoformat(result['since']) == NOW-timedelta(hours=8)


def test_youtube_quota_defers_same_window_until_next_utc_day(tmp_path):
    calls = []
    def rate_limited(args, log, **kwargs):
        calls.append(args)
        path = tmp_path / 'youtube/run.json'
        state = json.loads(path.read_text())
        state['reason'] = 'youtube_rate_limited'
        path.write_text(json.dumps(state))
        raise RuntimeError('worker_failed')
    result = run_source('youtube', tmp_path, executor=rate_limited, clock=lambda: NOW)
    assert result['status'] == 'deferred'
    assert result['attempts'] == 1
    assert datetime.fromisoformat(result['retryAfter']) > NOW
    assert run_source('youtube', tmp_path, executor=rate_limited, clock=lambda: NOW+timedelta(hours=1))['status'] == 'deferred'
    assert len(calls) == 1
    path = tmp_path / 'youtube/run.json'
    state = json.loads(path.read_text())
    state.update(status='retry', attempts=2)
    state.pop('retryAfter')
    path.write_text(json.dumps(state))
    exhausted = run_source('youtube', tmp_path, executor=rate_limited, clock=lambda: NOW+timedelta(days=1))
    assert exhausted['status'] == 'needs_attention'
    assert exhausted['attempts'] == 3


def test_reddit_pagination_overlap_and_truncation():
    class Session:
        headers = {}
        def get(self, *args, **kwargs):
            return SimpleNamespace(status_code=200, json=lambda: {'data':[{'id':str(i), 'created_utc':int(NOW.timestamp())} for i in range(100)]})
    with pytest.raises(RuntimeError, match='pagination_stalled'):
        fetch_window({}, NOW-timedelta(hours=3), NOW, session=Session())


def test_youtube_pagination_limit_is_not_success(monkeypatch):
    monkeypatch.setattr('pipeline.platforms.youtube.incremental._request_json', lambda *args, **kwargs:
        {'items': [], 'nextPageToken':'next'})
    with pytest.raises(RuntimeError, match='truncated'):
        channel_window('c', 'p', NOW-timedelta(hours=3), NOW, 'not-a-key', max_pages=2)


def test_no_new_reddit_posts_is_success():
    class Session:
        headers = {}
        def get(self, *args, **kwargs):
            return SimpleNamespace(status_code=200, json=lambda: {'data':[]})
    assert fetch_window({}, NOW-timedelta(hours=3), NOW, session=Session()) == []


def test_reddit_retry_does_not_turn_403_into_empty_success():
    class Session:
        headers = {}
        def get(self, *args, **kwargs):
            return SimpleNamespace(status_code=403)
    with pytest.raises(RuntimeError, match='http_403'):
        fetch_window({}, NOW-timedelta(hours=3), NOW, session=Session())


def test_reddit_transient_422_retries_without_dropping_window(monkeypatch):
    monkeypatch.setattr('pipeline.platforms.reddit.incremental.time.sleep', lambda _: None)
    class Session:
        headers = {}
        calls = 0
        def get(self, *args, **kwargs):
            self.calls += 1
            if self.calls == 1:
                return SimpleNamespace(status_code=422)
            return SimpleNamespace(status_code=200, json=lambda: {'data': []})
    session = Session()
    assert fetch_window({'author': 'example'}, NOW-timedelta(hours=3), NOW, session=session) == []
    assert session.calls == 2


def test_reddit_crawl_resumes_completed_selectors(monkeypatch, tmp_path):
    calls = []
    fail_once = {'value': True}
    def fetch(selector, since, until, **kwargs):
        value = next(iter(selector.values()))
        calls.append(value)
        if value == 'stocks':
            return [{'id': 'health', 'created_utc': NOW.timestamp()}]
        if value == 'second' and fail_once['value']:
            fail_once['value'] = False
            raise RuntimeError('reddit_http_422')
        return [{'id': value, 'created_utc': NOW.timestamp()}]
    monkeypatch.setattr('pipeline.platforms.reddit.incremental.fetch_window', fetch)
    monkeypatch.setattr('pipeline.platforms.reddit.incremental.time.sleep', lambda _: None)
    checkpoint = tmp_path / 'crawl-checkpoint.json'
    with pytest.raises(RuntimeError, match='422'):
        collect(NOW-timedelta(hours=3), NOW, [], subreddits=['first', 'second'], checkpoint=checkpoint)
    assert calls == ['stocks', 'first', 'second']
    calls.clear()
    result = collect(NOW-timedelta(hours=3), NOW, [], subreddits=['first', 'second'], checkpoint=checkpoint)
    assert calls == ['stocks', 'second']
    assert {row['id'] for row in result['items']} == {'first', 'second'}


def test_youtube_unavailable_playlist_is_distinct_from_network_failure(monkeypatch):
    def unavailable(*args, **kwargs):
        raise RuntimeError('http:404:playlistNotFound')
    monkeypatch.setattr('pipeline.platforms.youtube.incremental._request_json', unavailable)
    assert channel_window('c', 'p', NOW-timedelta(hours=3), NOW, 'key') is None
    def broken(*args, **kwargs):
        raise RuntimeError('http:503:temporary')
    monkeypatch.setattr('pipeline.platforms.youtube.incremental._request_json', broken)
    with pytest.raises(RuntimeError):
        channel_window('c', 'p', NOW-timedelta(hours=3), NOW, 'key')


def test_verification_mismatch_never_advances_watermark(tmp_path):
    def execute(args, log, **kwargs):
        root = tmp_path / 'reddit'
        if 'pipeline.jobs.social_delivery.worker' in args:
            p = root / 'run.json'
            state = json.loads(p.read_text()); state['status'] = 'ready'; p.write_text(json.dumps(state))
        elif '--apply' in args:
            (root / 'release').mkdir(exist_ok=True)
            (root / 'release/supabase-publication.json').write_text(json.dumps({'status':'published','revision':'expected'}))
        else:
            (root / 'verified.json').write_text(json.dumps({'databaseVerified':True,'revision':'wrong'}))
    result = run_source('reddit', tmp_path, executor=execute, clock=lambda: NOW)
    assert result['status'] == 'retry'
    assert 'verifiedAt' not in result


def test_timeout_kills_worker_and_keeps_bounded_log(tmp_path):
    import sys
    from pipeline.jobs.x_delivery import command
    output = tmp_path / 'timed.log'
    with pytest.raises(RuntimeError, match='worker_timeout'):
        command([sys.executable, '-c', 'import sys,time;sys.stdout.write("x"*1200000);sys.stdout.flush();time.sleep(10)'], output, timeout=.2)
    assert output.stat().st_size <= 1024**2


def test_youtube_eligible_author_uses_existing_platform_prefixed_identity(monkeypatch):
    from pipeline.jobs.social_delivery import processing
    from pipeline.domain.smart_voice import v0_impl as score
    from pipeline.domain.smart_voice import client_read_model
    candidate = {'candidate_id':'youtube:v1:NVDA', 'tweet_id':'v1', 'author_id':'youtube:channel-1'}
    class Connection:
        def execute(self, query, params=()):
            if query.startswith('SELECT * FROM sv_call_candidate'):
                return SimpleNamespace(fetchall=lambda: [candidate])
            if query.startswith('SELECT 1 FROM sv_call'):
                return SimpleNamespace(fetchone=lambda: (1,))
            if query.startswith('SELECT * FROM sv_call'):
                return SimpleNamespace(fetchone=lambda: {'is_actionable_call':False})
            raise AssertionError(query)
    monkeypatch.setattr(score, 'build_youtube_candidates', lambda *a, **kw: 1)
    monkeypatch.setattr(client_read_model, '_profile_rows', lambda *a: [{'source':'youtube', 'investor_id':'youtube:channel-1', 'platform_percentile':.2}])
    result = processing.process_candidates(Connection(), 'youtube', {'v1'}, '/unused', 300)
    assert result == {'candidates':1, 'processed':0}


@pytest.mark.parametrize('failure_reason,expected', [
    ('no_segments', 1), ('rate_limited', 'youtube_rate_limited'), ('other', 'transcripts_incomplete')])
def test_youtube_only_skips_confirmed_empty_transcripts(monkeypatch, failure_reason, expected):
    from pipeline.jobs.social_delivery import processing
    from pipeline.domain.smart_voice import v0_impl as score
    from pipeline.domain.smart_voice import client_read_model
    from pipeline.domain.opinions import youtube
    candidate = {'candidate_id':'youtube:v1:NVDA', 'tweet_id':'v1', 'author_id':'youtube:channel-1'}
    fulltext_options = {}
    class Connection:
        def execute(self, query, params=()):
            if query.startswith('SELECT * FROM sv_call_candidate'):
                return SimpleNamespace(fetchall=lambda: [candidate])
            if query.startswith('SELECT 1 FROM yt_fulltext_fail'):
                return SimpleNamespace(fetchone=lambda: (1,) if failure_reason == 'no_segments' else None)
            if query.startswith('SELECT reason FROM yt_fulltext_fail'):
                reason = 'HTTP 429' if failure_reason == 'rate_limited' else 'provider_error'
                return SimpleNamespace(fetchone=lambda: (reason,))
            if query.startswith('SELECT 1 FROM sv_call') or query.startswith('SELECT 1 FROM yt_fulltext'):
                return SimpleNamespace(fetchone=lambda: None)
            raise AssertionError(query)
    monkeypatch.setattr(score, 'build_youtube_candidates', lambda *a, **kw: 1)
    monkeypatch.setattr(score, 'materialize_youtube_transcript_videos', lambda *a: {'v1'})
    monkeypatch.setattr(client_read_model, '_profile_rows', lambda *a: [
        {'source':'youtube', 'investor_id':'youtube:channel-1', 'platform_percentile':.2}])
    monkeypatch.setattr(youtube, 'generate_fulltext', lambda **kw: fulltext_options.update(kw))
    if isinstance(expected, str):
        with pytest.raises(RuntimeError, match=expected):
            processing.process_candidates(Connection(), 'youtube', {'v1'}, '/unused', 300)
    else:
        assert processing.process_candidates(Connection(), 'youtube', {'v1'}, '/unused', 300) == {
            'candidates':0, 'processed':0, 'skippedNoTranscript':expected}
    assert fulltext_options['workers'] == 1
    assert fulltext_options['max_rate_waits'] == 6


def test_cycle_prunes_only_after_new_verified_publication(monkeypatch):
    from pipeline.jobs.social_delivery import cycle
    calls = []
    monkeypatch.setattr(cycle, 'run_social', lambda: {'status':'checked','sources':[{'status':'unchanged'}]})
    monkeypatch.setattr(cycle, 'sync_telegram', lambda: {'status': 'idle'})
    monkeypatch.setattr(cycle, 'cleanup_telegram', lambda: {'status': 'idle'})
    monkeypatch.setattr(cycle, 'run_x', lambda *_: {'status':'idle'})
    monkeypatch.setattr(cycle, 'command', lambda *args, **kwargs: calls.append(args))
    assert 'retention' not in cycle.run() and not calls
    monkeypatch.setattr(cycle, 'run_social', lambda: {'status':'checked','sources':[{'status':'verified'}]})
    assert cycle.run()['retention']['status'] == 'checked'
    assert len(calls) == 1 and calls[0][0][-1] == '--apply'


def test_cycle_exposes_source_failure_to_scheduler(monkeypatch):
    from pipeline.jobs.social_delivery import cycle
    monkeypatch.setattr(cycle, 'run_social', lambda: {'status': 'checked', 'sources': [
        {'source': 'youtube', 'status': 'verified'}, {'source': 'reddit', 'status': 'retry'}]})
    monkeypatch.setattr(cycle, 'sync_telegram', lambda: {'status': 'idle'})
    monkeypatch.setattr(cycle, 'run_x', lambda *_: {'status': 'idle'})
    monkeypatch.setattr(cycle, 'cleanup_telegram', lambda: {'status': 'idle'})
    monkeypatch.setattr(cycle, 'command', lambda *_args, **_kwargs: None)
    assert cycle.run()['status'] == 'retry'


def test_cycle_cli_returns_failure_for_retry(monkeypatch, capsys):
    from pipeline.cli.commands import social_delivery
    monkeypatch.setattr(social_delivery, 'run_cycle', lambda: {'status': 'retry'})
    with pytest.raises(SystemExit) as error:
        social_delivery._run_cycle(None)
    assert error.value.code == 1
    assert 'retry' in capsys.readouterr().out
