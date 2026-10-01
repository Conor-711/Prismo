"""Freeze the existing formal X ranking before selecting incoming posts."""
from __future__ import annotations

import sqlite3
import json
from pathlib import Path

from .client_read_model import QUALIFIED_FILTER


def frozen_x_authors(path: Path) -> tuple[set[str], set[str]]:
    snapshot = json.loads(path.read_text(encoding='utf-8'))
    ids = snapshot.get('rankedAuthorIds')
    if not isinstance(ids, list) or not ids or any(not isinstance(value, str) or not value for value in ids):
        raise ValueError('Invalid frozen X author ranking')
    return set(ids), set(snapshot.get('rankedAuthorHandles', []))


def ranked_expanded_cohorts(roster: list[dict[str, str]]) -> dict[str, set[str]]:
    """Use each new cohort's supplied ranking; never rerank the frozen legacy group."""
    groups: dict[str, dict[int, str]] = {'stock': {}, 'crypto': {}}
    seen_ids: set[str] = set()
    for row in roster:
        group = (row.get('selection_group') or '').strip().lower()
        if group not in groups:
            continue
        author_id = (row.get('user_id') or '').strip()
        try:
            rank = int(row.get('rank') or '')
        except ValueError as exc:
            raise ValueError(f'Invalid {group} cohort rank') from exc
        if not author_id or rank < 1 or rank in groups[group] or author_id in seen_ids:
            raise ValueError(f'Invalid {group} cohort roster')
        groups[group][rank] = author_id
        seen_ids.add(author_id)
    selected: dict[str, set[str]] = {}
    for group, ranks in groups.items():
        if ranks and set(ranks) != set(range(1, len(ranks) + 1)):
            raise ValueError(f'Incomplete {group} cohort ranking')
        count = (len(ranks) + 3) // 4
        selected[group] = {ranks[rank] for rank in range(1, count + 1)}
    return selected


def top_quartile_x_authors(database: str) -> tuple[set[str], set[str]]:
    connection = sqlite3.connect(f'file:{database}?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(f"""
            SELECT investor_id, handle
              FROM sv_investor_score
             WHERE source = 'x' AND ({QUALIFIED_FILTER})
             ORDER BY COALESCE(json_extract(platform_scores_json, '$.x'), sv, 100) DESC,
                      n_eff DESC, settled_calls DESC, investor_id ASC
        """).fetchall()
    finally:
        connection.close()
    if not rows:
        raise ValueError('No qualified X ranking is available')
    count = max(1, (len(rows) + 3) // 4)
    selected = rows[:count]
    return ({str(row['investor_id']) for row in selected},
            {str(row['handle']).casefold().lstrip('@') for row in selected if row['handle']})
