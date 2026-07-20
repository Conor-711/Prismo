from __future__ import annotations

import sqlite3

from scripts import data_snapshot


def _seed_database(path) -> None:
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, value TEXT)")
    con.executemany("INSERT INTO sample(value) VALUES (?)", [("alpha",), ("beta",)])
    con.commit()
    con.close()


def test_snapshot_round_trip_and_external_backup(tmp_path, monkeypatch):
    root = tmp_path / "repo"
    data_dir = root / "data"
    data_dir.mkdir(parents=True)
    source = data_dir / "dev.db"
    restored = data_dir / "restored.db"
    backup_dir = tmp_path / "backups"
    _seed_database(source)

    monkeypatch.setattr(data_snapshot, "ROOT", root)
    monkeypatch.setattr(data_snapshot, "SNAPSHOT", data_dir / "dev.db.xz")
    monkeypatch.setattr(data_snapshot, "MANIFEST", data_dir / "dev.db.xz.parts")
    monkeypatch.setattr(data_snapshot, "METADATA", data_dir / "dev.db.snapshot.json")

    backup = data_snapshot.backup_database(source, backup_dir, keep=1)
    assert backup.parent == backup_dir
    assert sqlite3.connect(backup).execute("SELECT COUNT(*) FROM sample").fetchone()[0] == 2

    metadata = data_snapshot.create_snapshot(
        source,
        single_limit_mb=90,
        chunk_mb=24,
        preset=0,
    )
    assert metadata["mode"] == "single"
    assert data_snapshot.SNAPSHOT.exists()
    assert not data_snapshot.MANIFEST.exists()

    data_snapshot.restore_snapshot(restored, force=False)
    con = sqlite3.connect(restored)
    try:
        assert con.execute("PRAGMA quick_check").fetchone()[0] == "ok"
        assert con.execute("SELECT value FROM sample ORDER BY id").fetchall() == [
            ("alpha",),
            ("beta",),
        ]
    finally:
        con.close()
