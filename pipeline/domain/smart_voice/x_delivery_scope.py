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
