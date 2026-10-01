import json
import zipfile
from datetime import datetime, timezone

import pytest

from pipeline.jobs.telegram_x_delivery import _filter_ranked_posts
from pipeline.jobs import telegram_x_delivery as telegram
from pipeline.jobs.x_delivery.prepare_ranked import freeze_from_receipt, prepare


def post(tweet_id, author_id):
    return {'tweet_id': tweet_id, 'author_id': author_id, 'author_handle': author_id,
            'created_at': datetime.now(timezone.utc).isoformat(),
            'text': '$AAPL view', 'cashtags': ['AAPL']}


def test_manual_packages_reuse_frozen_ranking_and_split_atomically(tmp_path):
    receipt = tmp_path / 'receipt.json'
    receipt.write_text(json.dumps({'selection': {'rankingAt': '2026-09-23T00:00:00Z',
        'rankedAuthorIds': ['top'], 'sourceHash': 'old-release'}}))
    snapshot = tmp_path / 'ranking.json'
    freeze_from_receipt(receipt, snapshot)
    package = tmp_path / 'incoming.zip'
    with zipfile.ZipFile(package, 'w') as archive:
        archive.writestr('tweets.jsonl', '\n'.join(json.dumps(post(str(n), author))
            for n, author in enumerate(['top', 'other', 'top', 'top', 'top'], 1)) + '\n')
    result = prepare(package, snapshot, tmp_path / 'prepared', chunk_rows=2)
    assert result['sourceRows'] == 5
    assert result['selectedRows'] == 4
    assert [part['rows'] for part in result['parts']] == [2, 2]
    assert prepare(package, snapshot, tmp_path / 'prepared', chunk_rows=2) == result
    assert package.is_file()
    changed_receipt = tmp_path / 'other-receipt.json'
    changed_receipt.write_text(json.dumps({'selection': {'rankingAt': '2026-09-23T01:00:00Z',
        'rankedAuthorIds': ['other'], 'sourceHash': 'new-release'}}))
    with pytest.raises(ValueError, match='different authors'):
        freeze_from_receipt(changed_receipt, snapshot)


def test_telegram_uses_frozen_snapshot_without_recomputing_rank(tmp_path, monkeypatch):
    monkeypatch.setattr(telegram, 'ROOT', tmp_path)
    snapshot = tmp_path / 'data/inbox/x/ranking-snapshot.json'
    snapshot.parent.mkdir(parents=True)
    snapshot.write_text(json.dumps({'rankingAt': '2026-09-23T00:00:00Z',
        'rankedAuthorIds': ['top']}))
    monkeypatch.setattr(telegram, 'top_quartile_x_authors', lambda _db: (_ for _ in ()).throw(AssertionError()))
    raw = tmp_path / 'source.jsonl'
    raw.write_text('\n'.join(json.dumps(post(str(n), author))
        for n, author in enumerate(['top', 'other'], 1)) + '\n')
    selected = tmp_path / 'selected.jsonl'
    receipt = _filter_ranked_posts(raw, selected, tmp_path)
    assert receipt['selectedRows'] == 1
    assert receipt['rankingAt'] == '2026-09-23T00:00:00Z'
    assert json.loads(selected.read_text())['author_id'] == 'top'


def test_expanded_roster_selects_each_new_top_quartile_and_keeps_legacy_snapshot(tmp_path, monkeypatch):
    monkeypatch.setattr(telegram, 'ROOT', tmp_path)
    snapshot = tmp_path / 'data/inbox/x/ranking-snapshot.json'
    snapshot.parent.mkdir(parents=True)
    snapshot.write_text(json.dumps({'rankingAt': '2026-09-23T00:00:00Z',
                                    'rankedAuthorIds': ['legacy']}))
    package = tmp_path / 'expanded.zip'
    authors = ['legacy', 'stock1', 'stock2', 'stock3', 'stock4',
               'crypto1', 'crypto2', 'crypto3', 'crypto4']
    roster = 'user_id,selection_group,rank,language\n' + ''.join(
        f'{group}{rank},{group},{rank},{"zh" if group == "stock" else "en"}\n'
        for group in ('stock', 'crypto') for rank in range(1, 5))
    with zipfile.ZipFile(package, 'w') as archive:
        archive.writestr('roster.csv', roster)
        archive.writestr('tweets.jsonl', '\n'.join(
            json.dumps(post(str(index), author)) for index, author in enumerate(authors, 1)) + '\n')

    selected = tmp_path / 'selected.jsonl'
    receipt = _filter_ranked_posts(package, selected, tmp_path)
    assert receipt['selectedRowsByCohort'] == {
        'english_stock': 1, 'chinese_stock': 1, 'crypto': 1}
    assert receipt['rankedAuthorsByCohort'] == {
        'english_stock': 1, 'chinese_stock': 1, 'crypto': 1}
    assert {json.loads(line)['author_id'] for line in selected.read_text().splitlines()} == {
        'legacy', 'stock1', 'crypto1'}

    manual = prepare(package, snapshot, tmp_path / 'prepared', chunk_rows=2)
    assert manual['selectedRows'] == 3
    assert manual['selectedRowsByCohort'] == receipt['selectedRowsByCohort']
    assert [part['rows'] for part in manual['parts']] == [2, 1]


def test_expanded_roster_rejects_duplicate_ranks(tmp_path):
    from pipeline.domain.smart_voice.x_delivery_scope import ranked_expanded_cohorts

    with pytest.raises(ValueError, match='Invalid stock cohort roster'):
        ranked_expanded_cohorts([{'user_id': 'one', 'selection_group': 'stock', 'rank': '1'},
                                 {'user_id': 'two', 'selection_group': 'stock', 'rank': '1'}])

    from pipeline.platforms.x.expanded_roster import read_expanded_roster
    package = tmp_path / 'incomplete.zip'
    with zipfile.ZipFile(package, 'w') as archive:
        archive.writestr('roster.csv', 'user_id,selection_group\none,stock\n')
    with pytest.raises(ValueError, match='Incomplete X cohort roster columns'):
        read_expanded_roster(package)
