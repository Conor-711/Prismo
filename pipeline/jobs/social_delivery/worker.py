"""One checkpointed source run, launched with the local DB configured first."""
import hashlib
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

from ..x_daily import write_json


def run(path):
    from ...common.db import engine
    from ...common.config import settings
    from ...domain.smart_voice import v0_impl as score
    from ...domain.smart_voice.client_read_model import build_smart_account_client_collections
    from ...platforms.market_data.daily_prices import refresh
    from .processing import process_candidates
    state = json.loads(path.read_text())
    if engine.url.get_backend_name() != 'sqlite' or Path(engine.url.database).resolve() != Path(state['database']):
        raise RuntimeError('local_database_required')
    pooled = engine.raw_connection()
    con = pooled.driver_connection
    con.row_factory = sqlite3.Row
    source = state['source']
    since, until = (datetime.fromisoformat(state[key]) for key in ('since', 'until'))

    def step(name, action):
        if name not in state['steps']:
            state['activeStep'] = name
            write_json(path, state)
            print('[social-delivery]', source, name, flush=True)
            state['steps'][name] = action()
            write_json(path, state)
        return state['steps'][name]

    try:
        def crawl():
            if source == 'youtube':
                from ...platforms.youtube.incremental import collect
                pool = con.execute('SELECT pool_version FROM yt_author_pool_run ORDER BY created_at DESC LIMIT 1').fetchone()[0]
                channels = [r[0] for r in con.execute('SELECT channel_id FROM yt_author_pool WHERE pool_version=? AND selected=1 ORDER BY pool_rank', (pool,))]
                if not channels:
                    raise RuntimeError('youtube_pool_empty')
                payload = collect(since, until, channels, settings.youtube_api_key)
                payload['poolVersion'] = pool
            else:
                from ...platforms.reddit.incremental import collect
                from ...platforms.reddit.realtime import load_subreddit_config
                authors = [r[0].split(':', 1)[1] for r in con.execute("SELECT investor_id FROM sv_investor_score WHERE source='reddit'")]
                subs = [s['name'] for s in load_subreddit_config() if s.get('market', 'us') == 'us']
                payload = collect(since, until, authors, subreddits=subs,
                                  checkpoint=path.parent / 'crawl-checkpoint.json')
            if not payload['complete']:
                raise RuntimeError('crawl_incomplete')
            write_json(path.parent / 'raw.json', payload)
            if source == 'reddit':
                (path.parent / 'crawl-checkpoint.json').unlink(missing_ok=True)
            return {'items': len(payload['items']), 'sourceThrough': payload['sourceThrough'], 'provider': payload['provider']}

        step('crawl', crawl)
        raw = json.loads((path.parent / 'raw.json').read_text())
        ids = {r['video_id' if source == 'youtube' else 'id'] for r in raw['items']}

        def ingest():
            if source == 'youtube':
                from ...platforms.youtube.incremental import store
                from ...domain.tickers.youtube_uploads import map_author_uploads
                store(con, raw['items'], raw['poolVersion'])
                map_author_uploads(state['database'], pool_version=raw['poolVersion'], video_ids=ids, initialize_schema=False)
            else:
                from ...platforms.reddit.incremental import store
                store(raw['items'])
            return {'items': len(ids)}
        step('ingest', ingest)
        step('analysis', lambda: process_candidates(con, source, ids, state['database'], state['maxCalls']))

        def prices():
            tickers = {r[0] for r in con.execute("SELECT DISTINCT ticker FROM sv_call WHERE source=? AND is_actionable_call=1 AND datetime(created_at)>=datetime('now','-370 days')", (source,))}
            tickers |= {'SPY', 'QQQ', 'XLK', 'XLF', 'XLE', 'XLV', 'XLY', 'XLP', 'XLI', 'XLB', 'XLU', 'XLRE', 'XLC', 'SMH'}
            return refresh(con, sorted(tickers))
        step('prices', prices)
        step('settle', lambda: score.settle_calls(con, {source}, initialize_schema=False))
        rankings_frozen = os.environ.get('BSMART_RANKINGS_FROZEN', 'true').lower() not in {'0', 'false', 'no'}
        step('score', (lambda: {'status': 'frozen'}) if rankings_frozen else
             (lambda: score.score_investors(con, sources={source}, initialize_schema=False)))

        def export():
            release = path.parent / 'release'
            release.mkdir(exist_ok=True)
            label = {'youtube': 'YouTube', 'reddit': 'Reddit'}[source]
            documents = build_smart_account_client_collections(con, as_of=until, update_limit=0)
            entries = {}
            for name, rows in documents.items():
                items = [r for r in rows if r['platform'] == label]
                # Only source items actually observed in this successful crawl enter the new feed.
                if name == 'smart-account-updates':
                    items = [r for r in items if r['sourcePostId'] in ids]
                output = release / (name + '.json')
                write_json(output, items)
                entries[name] = {'count': len(items), 'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
            write_json(release / 'platform-manifest.json', {'version': 1, 'status': 'ready', 'platform': source,
                'asOf': datetime.now(timezone.utc).isoformat(), 'sourceThrough': raw['sourceThrough'],
                'crawlComplete': True, 'crawlFrom': state['since'], 'crawlThrough': state['until'],
                'provider': raw['provider'], 'collections': entries})
            return entries
        step('export', export)
        state.update(status='ready', activeStep=None)
        write_json(path, state)
    finally:
        pooled.close()


if __name__ == '__main__':
    try:
        run(Path(sys.argv[1]))
    except Exception as error:
        # Provider URLs may contain keys. Persist only a non-sensitive error type.
        reason = str(error) if re.fullmatch(r'[a-z][a-z0-9_]{2,79}', str(error)) else 'inspect_provider_locally'
        path = Path(sys.argv[1])
        if path.is_file():
            failed = json.loads(path.read_text())
            failed.update(errorType=type(error).__name__, reason=reason)
            write_json(path, failed)
        print(json.dumps({'status': 'failed', 'errorType': type(error).__name__, 'reason': reason}), flush=True)
        raise SystemExit(1) from None
