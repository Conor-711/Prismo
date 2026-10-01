"""Read the optional, source-provided cohort roster in an X delivery package."""
from __future__ import annotations

import csv
import io
import zipfile
from pathlib import Path

MAX_ROSTER_BYTES = 5 * 1024 * 1024


def read_expanded_roster(package: Path) -> list[dict[str, str]]:
    if package.suffix.lower() != '.zip':
        return []
    with zipfile.ZipFile(package) as archive:
        members = [item for item in archive.infolist() if item.filename == 'roster.csv']
        if not members:
            return []
        if len(members) != 1 or members[0].file_size > MAX_ROSTER_BYTES:
            raise ValueError('Invalid X cohort roster')
        with archive.open(members[0]) as stream:
            reader = csv.DictReader(io.TextIOWrapper(stream, encoding='utf-8-sig', newline=''))
            fields = set(reader.fieldnames or [])
            if not {'selection_group', 'rank'} & fields:
                return []
            if not {'user_id', 'selection_group', 'rank'}.issubset(fields):
                raise ValueError('Incomplete X cohort roster columns')
            return list(reader)
