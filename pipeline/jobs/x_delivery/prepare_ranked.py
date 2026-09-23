"""Prepare bounded manual X packages against one already-approved ranking snapshot."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

from ...domain.smart_voice.x_delivery_scope import frozen_x_authors
from ...platforms.x.daily_package import stage_package
from ..x_daily import write_json
from . import ROOT


def freeze_from_receipt(receipt_path: Path, snapshot_path: Path) -> dict:
    receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
    selection = receipt['selection']
    snapshot = {'rankingAt': selection['rankingAt'],
                'rankedAuthorIds': selection['rankedAuthorIds'],
                'sourceHash': selection['sourceHash']}
    if snapshot_path.exists():
        existing = json.loads(snapshot_path.read_text(encoding='utf-8'))
        if existing != snapshot:
            raise ValueError('Frozen ranking already exists with different authors')
    else:
        snapshot_path.parent.mkdir(parents=True, exist_ok=True)
        write_json(snapshot_path, snapshot)
    frozen_x_authors(snapshot_path)
    return snapshot


def prepare(package: Path, snapshot_path: Path, output_root: Path, *, chunk_rows: int = 900) -> dict:
    if not 1 <= chunk_rows <= 1000:
        raise ValueError('chunk_rows must be 1..1000')
    if package.is_symlink():
        raise ValueError('Expected an unchanged source package')
    package = package.resolve()
    if not package.is_file():
        raise ValueError('Expected an unchanged source package')
    ids, handles = frozen_x_authors(snapshot_path)
    ranking_hash = hashlib.sha256(snapshot_path.read_bytes()).hexdigest()
    output_root.mkdir(parents=True, exist_ok=True)
    before = package.stat()
    temporary = Path(tempfile.mkdtemp(prefix='ranked-x-', dir=output_root))
    try:
        info = stage_package(package, temporary / 'stage')
        if (before.st_size, before.st_mtime_ns) != (package.stat().st_size, package.stat().st_mtime_ns):
            raise ValueError('Source package changed during selection')
        target = output_root / info['packageHash']
        if target.exists():
            saved = json.loads((target / 'manifest.json').read_text(encoding='utf-8'))
            if saved['rankingHash'] != ranking_hash or saved['sourceHash'] != info['packageHash']:
                raise ValueError('Prepared package has a different ranking or source')
            for part in saved['parts']:
                path = target / part['name']
                if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != part['sha256']:
                    raise ValueError('Prepared package is incomplete or modified')
            return saved

        selected = 0
        seen = set()
        parts = []
        output = None
        prepared = temporary / 'prepared'
        prepared.mkdir()
        try:
            for path in sorted((temporary / 'stage').glob('tweets_*.jsonl')):
                with path.open('rb') as stream:
                    for line in stream:
                        if not line.strip():
                            continue
                        post = json.loads(line)
                        author_id = str(post.get('author_id') or '')
                        handle = str(post.get('author_handle') or '').casefold().lstrip('@')
                        if author_id not in ids and (author_id or handle not in handles):
                            continue
                        tweet_id = str(post['tweet_id'])
                        if tweet_id in seen:
                            continue
                        seen.add(tweet_id)
                        if selected % chunk_rows == 0:
                            if output:
                                output.close()
                            name = f'part_{len(parts):03}.jsonl'
                            output = (prepared / name).open('wb')
                            parts.append({'name': name, 'rows': 0})
                        output.write(line if line.endswith(b'\n') else line + b'\n')
                        parts[-1]['rows'] += 1
                        selected += 1
        finally:
            if output:
                output.close()
        for part in parts:
            part['sha256'] = hashlib.sha256((prepared / part['name']).read_bytes()).hexdigest()
        manifest = {'source': str(package), 'sourceHash': info['packageHash'],
                    'sourceRows': info['rows'], 'selectedRows': selected,
                    'rankingHash': ranking_hash, 'rankedAuthors': len(ids), 'parts': parts}
        write_json(prepared / 'manifest.json', manifest)
        prepared.replace(target)
        return manifest
    finally:
        shutil.rmtree(temporary, ignore_errors=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--freeze-from', type=Path)
    parser.add_argument('--snapshot', type=Path, default=ROOT / 'data/inbox/x/ranking-snapshot.json')
    parser.add_argument('--output-root', type=Path, default=ROOT / 'data/inbox/x/manual')
    parser.add_argument('--chunk-rows', type=int, default=900)
    args = parser.parse_args()
    if args.freeze_from:
        freeze_from_receipt(args.freeze_from, args.snapshot)
    print(json.dumps(prepare(args.package, args.snapshot, args.output_root,
                             chunk_rows=args.chunk_rows), ensure_ascii=False))
