"""Prepare a reviewed YouTube delta while an older video awaits analysis."""
import argparse
import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from ...domain.smart_voice.client_read_model import build_smart_account_client_collections
from ..x_daily import write_json


def prepare(run_path: Path, output: Path, processed: set[str], deferred: set[str]) -> dict:
    state = json.loads(run_path.read_text())
    raw_path = run_path.parent / 'raw.json'
    raw = json.loads(raw_path.read_text())
    available = {item['video_id'] for item in raw['items']}
    if (state['source'] != 'youtube' or state['status'] != 'deferred' or
            not raw['complete'] or not processed or not deferred or
            processed & deferred or not processed | deferred <= available):
        raise ValueError('Invalid reviewed YouTube batch')
    with sqlite3.connect(state['database']) as connection:
        connection.row_factory = sqlite3.Row
        placeholders = ','.join('?' for _ in processed)
        fulltext = {row[0] for row in connection.execute(
            f'SELECT video_id FROM yt_fulltext WHERE video_id IN ({placeholders})', sorted(processed))}
        if fulltext != processed:
            raise ValueError('A processed video has no complete transcript')
        documents = build_smart_account_client_collections(
            connection, as_of=datetime.fromisoformat(state['until']), update_limit=0)

    output.mkdir(parents=True, exist_ok=True)
    entries = {}
    for name, rows in documents.items():
        items = [row for row in rows if row['platform'] == 'YouTube']
        if name == 'smart-account-updates':
            items = [row for row in items if row['sourcePostId'] in processed]
        path = output / (name + '.json')
        write_json(path, items)
        entries[name] = {'count': len(items), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    if not entries['smart-account-updates']['count']:
        raise ValueError('No displayable updates from the processed videos')
    manifest = {
        'version': 1, 'status': 'ready', 'platform': 'youtube',
        'partial': True, 'analysisComplete': False, 'crawlComplete': True,
        'processedVideoIds': sorted(processed), 'deferredVideoIds': sorted(deferred),
        'asOf': datetime.now(timezone.utc).isoformat(),
        'sourceThrough': raw['sourceThrough'], 'crawlFrom': state['since'],
        'crawlThrough': state['until'], 'provider': raw['provider'],
        'rawSha256': hashlib.sha256(raw_path.read_bytes()).hexdigest(),
        'collections': entries,
    }
    write_json(output / 'platform-manifest.json', manifest)
    return {'updates': entries['smart-account-updates']['count'], 'manifest': str(output / 'platform-manifest.json')}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--processed', nargs='+', required=True)
    parser.add_argument('--deferred', nargs='+', required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.run, args.output, set(args.processed), set(args.deferred))))


if __name__ == '__main__':
    main()
