import sqlite3
from datetime import datetime, timezone

import pytest

from pipeline.domain.opinions.translation_completeness import numeric_tokens, validate_translation
from pipeline.jobs.social_delivery import readings
from pipeline.platforms.reddit.profile_assets import ProfileImages, refresh_avatars


def test_feed_avatar_lookup_uses_identity_not_display_handle():
    from pipeline.domain.smart_voice.client_read_model import _profile_metadata
    con = sqlite3.connect(':memory:')
    con.execute('CREATE TABLE author_avatar(source TEXT,handle TEXT,url TEXT)')
    con.execute("INSERT INTO author_avatar VALUES('reddit','alice','https://i.redd.it/alice.png')")
    assert _profile_metadata(con, source='reddit', investor_id='reddit:alice',
                             handle='u/Alice')['avatar_url'] == 'https://i.redd.it/alice.png'


def test_markdown_inside_numbers_preserves_actual_numeric_value():
    assert numeric_tokens('09/2*9*, premium **2.80** and $1,000') == {'09', '29', '2.80', '1000'}
    assert numeric_tokens('2*9*3 and 4*8') == {'2', '9', '3', '4', '8'}
    assert validate_translation('09/2*9*: $37 Call', {'zh': '09/29: $37 看涨期权', 'en': '09/29: $37 Call'})
    assert not validate_translation('09/2*9*: $37 Call', {'zh': '09/29: $38 看涨期权', 'en': '09/29: $37 Call'})


def test_profile_parser_rejects_other_users_and_untrusted_hosts():
    parser = ProfileImages('alice')
    parser.feed('<img alt="u/bob avatar" src="https://i.redd.it/bob.png">'
                '<img alt="u/alice avatar" src="https://evil.example/alice.png">')
    assert parser.url is None
    parser.feed('<img alt="Alice u/alice avatar" src="https://i.redd.it/alice.png?s=x&amp;width=256">')
    assert parser.url == 'https://i.redd.it/alice.png?s=x&width=256'


def test_avatar_failure_preserves_cache_and_throttles_empty_results(monkeypatch):
    from pipeline.platforms.reddit import profile_assets
    monkeypatch.setattr(profile_assets, 'reddit_token', lambda: (None, 'test'))
    monkeypatch.setattr(profile_assets, 'avatar_url', lambda _: None)
    con = sqlite3.connect(':memory:')
    con.execute('CREATE TABLE author_avatar(source TEXT,handle TEXT,url TEXT,fetched_at TEXT,PRIMARY KEY(source,handle))')
    con.execute("INSERT INTO author_avatar VALUES('reddit','alice','https://i.redd.it/alice.png','2020-01-01')")
    calls = []
    def fail(handle, *args):
        calls.append(handle)
        raise OSError('unavailable')
    clock = lambda: datetime(2026, 10, 1, tzinfo=timezone.utc)
    result = refresh_avatars(con, {'reddit:alice', 'reddit:bobby'}, fetch=fail, clock=clock)
    assert result == {'resolved': 0, 'cached': 1, 'unavailable': 1}
    refresh_avatars(con, {'reddit:bobby'}, fetch=fail, clock=clock)
    assert calls == ['bobby']
    assert con.execute("SELECT url FROM author_avatar WHERE handle='alice'").fetchone()[0].endswith('alice.png')


def test_readings_use_complete_body_and_fail_closed(monkeypatch):
    view = {'source': 'reddit', 'source_post_id': 'p1', 'ticker': 'TLT',
            'investor_id': 'reddit:alice', 'original_text': 'Hold $37 until 2027.', 'created_at': '2026-10-01'}
    monkeypatch.setattr(readings, '_update_rows', lambda *a, **k:
                        [view, {**view, 'source_post_id': 'outside'}])
    seen = []
    monkeypatch.setattr(readings.kol_refine, 'refine', lambda **k: seen.append(k))
    monkeypatch.setattr(readings.kol_translate, 'translate', lambda **k: seen.append(k))
    monkeypatch.setattr(readings, 'refresh_avatars', lambda *a: {'resolved': 1})
    con = sqlite3.connect(':memory:')
    con.execute('CREATE TABLE kol_refined(source TEXT,item_id TEXT,ticker TEXT,trans_zh TEXT,trans_en TEXT)')
    con.execute("INSERT INTO kol_refined VALUES('reddit','p1','TLT','持有 $37 直到 2027。','Hold $37 until 2027.')")
    assert readings.prepare_readings(con, {'p1'}, None, 10)['readyViews'] == 1
    assert all(k['rows'][0]['txt'] == view['original_text'] and k['complete_text']
               and not k['initialize_schema'] for k in seen)
    con.execute("UPDATE kol_refined SET trans_zh='看多'")
    with pytest.raises(RuntimeError, match='translation_incomplete'):
        readings.prepare_readings(con, {'p1'}, None, 10)
    with pytest.raises(RuntimeError, match='budget_exceeded'):
        readings.prepare_readings(con, {'p1'}, None, 0)
