"""Bounded public Arctic Shift crawler. Fail closed on gaps and stale mirror."""
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import time
import requests

from .arctic import BASE


def fetch_window(selector, since, until, *, session=None, max_pages=20):
    session = session or requests.Session()
    session.headers['User-Agent'] = 'bSmart-content-refresh/1.0 (public market research)'
    before = int(until.timestamp()) + 1
    result = {}
    for _ in range(max_pages):
        response = None
        for attempt in range(3):
            try:
                response = session.get(BASE, params={**selector, 'after': int(since.timestamp()) - 1,
                    'before': before, 'sort': 'desc', 'limit': 100}, timeout=30)
                if response.status_code == 200:
                    break
                # The mirror occasionally returns 422 for an otherwise valid
                # author/window query (the identical query can then return 200).
                # Retry it only within the same bounded request budget.
                if response.status_code not in {422, 429, 500, 502, 503, 504}:
                    raise RuntimeError('reddit_http_' + str(response.status_code))
            except requests.RequestException:
                response = None
            time.sleep(2 ** attempt)
        if response is None:
            raise RuntimeError('reddit_unavailable')
        if response.status_code != 200:
            raise RuntimeError('reddit_http_' + str(response.status_code))
        items = response.json().get('data')
        if not isinstance(items, list):
            raise ValueError('reddit_invalid_response')
        for item in items:
            created = datetime.fromtimestamp(item['created_utc'], timezone.utc)
            if since <= created <= until:
                result[item['id']] = item
        if len(items) < 100:
            return list(result.values())
        next_before = min(int(item['created_utc']) for item in items) + 1
        if next_before >= before:
            raise RuntimeError('reddit_pagination_stalled')
        before = next_before  # Overlap the boundary second, then deduplicate IDs.
        time.sleep(1)
    raise RuntimeError('reddit_window_truncated')


def collect(since, until, authors, *, subreddits, session=None, checkpoint=None):
    session = session or requests.Session()
    selectors = ([('subreddit', s) for s in subreddits] + [('author', a) for a in authors])
    fingerprint = hashlib.sha256(json.dumps([since.isoformat(), until.isoformat(), selectors],
                                    separators=(',', ':')).encode()).hexdigest()
    posts, completed = {}, set()
    if checkpoint is not None:
        checkpoint = Path(checkpoint)
        try:
            saved = json.loads(checkpoint.read_text())
            age = datetime.now(timezone.utc) - datetime.fromisoformat(saved['savedAt'])
            if saved['fingerprint'] == fingerprint and timedelta(0) <= age <= timedelta(hours=4):
                posts = {item['id']: item for item in saved['items']}
                completed = set(saved['completed'])
        except (OSError, ValueError, KeyError, TypeError):
            pass
    # An empty tracked author feed is normal; a lagging global mirror is not.
    health = fetch_window({'subreddit': 'stocks'}, until - timedelta(hours=6), until, session=session)
    if not health or max(p['created_utc'] for p in health) < until.timestamp() - 3 * 3600:
        raise RuntimeError('reddit_mirror_stale')
    for kind, value in selectors:
        selector_key = kind + ':' + value
        if selector_key in completed:
            continue
        for item in fetch_window({kind: value}, since, until, session=session):
            posts[item['id']] = item
        completed.add(selector_key)
        if checkpoint is not None:
            temporary = checkpoint.with_suffix(checkpoint.suffix + '.tmp')
            temporary.write_text(json.dumps({'fingerprint': fingerprint, 'savedAt':
                datetime.now(timezone.utc).isoformat(), 'completed': sorted(completed),
                'items': list(posts.values())}, ensure_ascii=False))
            temporary.replace(checkpoint)
        time.sleep(.6)
    return {'provider': 'arctic-shift', 'complete': True, 'items': list(posts.values()),
            'checkedAt': until.isoformat(), 'sourceThrough': datetime.fromtimestamp(
                max((p['created_utc'] for p in posts.values()), default=0), timezone.utc).isoformat() if posts else None}


def store(items):
    from ...common.db import session_scope
    from ...common.ticker_extraction import load_ticker_dict
    from .realtime import upsert_subreddit, upsert_author, upsert_post, store_mentions
    with session_scope() as session:
        tickers = load_ticker_dict(session)
        if not tickers.tickers:
            raise RuntimeError('ticker_dictionary_empty')
        for item in items:
            sid = upsert_subreddit(session, item['subreddit'])
            aid = upsert_author(session, item.get('author'))
            created = datetime.fromtimestamp(item['created_utc'], timezone.utc).replace(tzinfo=None)
            body = item.get('selftext') or ''
            if body in {'[removed]', '[deleted]'}:
                body = ''
            upsert_post(session, id=item['id'], subreddit_id=sid, author_id=aid,
                title=item.get('title') or '', selftext=body, url=item.get('url'),
                permalink=item.get('permalink') or '', flair=item.get('link_flair_text'),
                is_self=bool(item.get('is_self')), created_utc=created, score=int(item.get('score') or 0),
                upvote_ratio=float(item.get('upvote_ratio') or 0), num_comments=int(item.get('num_comments') or 0),
                total_awards=int(item.get('total_awards_received') or 0))
            store_mentions(session, tickers, item_id=item['id'], item_type='post',
                text=(item.get('title') or '') + '\n' + body, subreddit_id=sid, author_id=aid, created_utc=created)
