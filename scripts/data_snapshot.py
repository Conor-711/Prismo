#!/usr/bin/env python3
"""Manage bSmart's local SQLite truth source without tracking the raw database."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import lzma
import os
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = ROOT / "data" / "dev.db"
DEFAULT_BACKUP_DIR = Path(
    os.environ.get("BSMART_BACKUP_DIR", ROOT.parent / f"{ROOT.name}-backups")
).expanduser()
SNAPSHOT = ROOT / "data" / "dev.db.xz"
MANIFEST = ROOT / "data" / "dev.db.xz.parts"
METADATA = ROOT / "data" / "dev.db.snapshot.json"
PART_GLOB = "dev.db.xz.part-*"


def _human_size(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.1f}{unit}"
        value /= 1024
    return f"{value:.1f}TB"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _check_database(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(path)
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=60)
    try:
        result = con.execute("PRAGMA quick_check").fetchone()
    finally:
        con.close()
    if not result or result[0] != "ok":
        raise RuntimeError(f"SQLite quick_check failed for {path}: {result}")


def _remove_paths(paths: list[Path]) -> None:
    for path in paths:
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink(missing_ok=True)


def backup_database(db_path: Path, backup_dir: Path, keep: int) -> Path:
    """Create a transactionally consistent external backup and rotate old copies."""
    if keep <= 0:
        raise ValueError("keep must be positive")
    _check_database(db_path)
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    destination = backup_dir / f"dev.db.bak-{stamp}"
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.unlink(missing_ok=True)

    source = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=60)
    target = sqlite3.connect(temporary)
    try:
        source.backup(target, pages=4096)
        target.execute("PRAGMA journal_mode=DELETE")
        target.commit()
    finally:
        target.close()
        source.close()
    _check_database(temporary)
    os.replace(temporary, destination)

    backups = sorted(backup_dir.glob("dev.db.bak-*"), key=lambda path: path.stat().st_mtime)
    _remove_paths(backups[:-keep])
    print(f"[data-backup] {destination} ({_human_size(destination.stat().st_size)})")
    return destination


def _compact_database(source: Path, destination: Path) -> None:
    destination.unlink(missing_ok=True)
    con = sqlite3.connect(source, timeout=120)
    try:
        con.execute("VACUUM INTO ?", (str(destination),))
    finally:
        con.close()
    _check_database(destination)


def _compress(source: Path, destination: Path, preset: int) -> None:
    xz = shutil.which("xz")
    if xz:
        with destination.open("wb") as output_file:
            subprocess.run(
                [xz, "--threads=0", f"-{preset}", "--stdout", str(source)],
                stdout=output_file,
                check=True,
            )
        return
    with source.open("rb") as input_file, lzma.open(
        destination, "wb", format=lzma.FORMAT_XZ, preset=preset
    ) as output_file:
        shutil.copyfileobj(input_file, output_file, length=8 * 1024 * 1024)


def _verify_compressed(path: Path, expected_hash: str) -> None:
    digest = hashlib.sha256()
    with lzma.open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_hash:
        raise RuntimeError("compressed snapshot verification failed")


def _write_parts(compressed: Path, chunk_bytes: int) -> list[Path]:
    data_dir = ROOT / "data"
    staging = data_dir / ".snapshot-parts"
    _remove_paths([staging])
    staging.mkdir(parents=True)
    parts: list[Path] = []
    with compressed.open("rb") as source:
        index = 0
        while True:
            chunk = source.read(chunk_bytes)
            if not chunk:
                break
            path = staging / f"dev.db.xz.part-{index:03d}"
            path.write_bytes(chunk)
            parts.append(path)
            index += 1
    if not parts:
        raise RuntimeError("snapshot split produced no parts")

    _remove_paths(list(data_dir.glob(PART_GLOB)))
    final_parts = []
    for part in parts:
        final = data_dir / part.name
        os.replace(part, final)
        final_parts.append(final)
    _remove_paths([staging])
    return final_parts


def create_snapshot(
    db_path: Path,
    *,
    single_limit_mb: int,
    chunk_mb: int,
    preset: int,
) -> dict:
    """Create one deployment snapshot without retaining duplicate compressed copies."""
    if single_limit_mb <= 0 or chunk_mb <= 0:
        raise ValueError("snapshot size limits must be positive")
    _check_database(db_path)
    data_dir = ROOT / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="bsmart-snapshot-", dir=data_dir) as temp_dir:
        compact = Path(temp_dir) / "dev.compact.db"
        compressed = Path(temp_dir) / "dev.db.xz"
        print("[data-snapshot] compacting SQLite database...", flush=True)
        _compact_database(db_path, compact)
        compact_hash = _sha256(compact)
        print("[data-snapshot] compressing compact database...", flush=True)
        _compress(compact, compressed, preset)
        _verify_compressed(compressed, compact_hash)

        compressed_size = compressed.stat().st_size
        single_limit = single_limit_mb * 1024 * 1024
        if compressed_size <= single_limit:
            _remove_paths(list(data_dir.glob(PART_GLOB)) + [MANIFEST])
            os.replace(compressed, SNAPSHOT)
            files = [SNAPSHOT]
            mode = "single"
        else:
            files = _write_parts(compressed, chunk_mb * 1024 * 1024)
            _remove_paths([SNAPSHOT])
            MANIFEST.write_text(
                "".join(f"data/{path.name}\n" for path in files), encoding="utf-8"
            )
            mode = "split"

        metadata = {
            "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "source": "data/dev.db",
            "sourceBytes": db_path.stat().st_size,
            "compactBytes": compact.stat().st_size,
            "compressedBytes": compressed_size,
            "decompressedSha256": compact_hash,
            "mode": mode,
            "files": [f"data/{path.name}" for path in files],
            "partBytes": chunk_mb * 1024 * 1024 if mode == "split" else None,
        }
        temporary_metadata = METADATA.with_suffix(".json.tmp")
        temporary_metadata.write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        os.replace(temporary_metadata, METADATA)

    print(
        f"[data-snapshot] mode={mode} files={len(files)} "
        f"source={_human_size(metadata['sourceBytes'])} "
        f"compact={_human_size(metadata['compactBytes'])} "
        f"compressed={_human_size(metadata['compressedBytes'])}"
    )
    return metadata


def restore_snapshot(destination: Path, force: bool) -> None:
    """Restore the deployment snapshot to a local SQLite database."""
    if destination.exists() and not force:
        raise RuntimeError(f"{destination} exists; pass --force to replace it")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bsmart-restore-", dir=destination.parent) as temp_dir:
        compressed = Path(temp_dir) / "dev.db.xz"
        restored = Path(temp_dir) / "dev.db"
        if MANIFEST.exists():
            part_names = [line.strip() for line in MANIFEST.read_text().splitlines() if line.strip()]
            if not part_names:
                raise RuntimeError("snapshot manifest is empty")
            with compressed.open("wb") as output:
                for name in part_names:
                    part = ROOT / name
                    if not part.exists():
                        raise FileNotFoundError(part)
                    with part.open("rb") as input_file:
                        shutil.copyfileobj(input_file, output, length=8 * 1024 * 1024)
        elif SNAPSHOT.exists():
            shutil.copy2(SNAPSHOT, compressed)
        else:
            raise RuntimeError("no deployment snapshot found")

        with lzma.open(compressed, "rb") as input_file, restored.open("wb") as output_file:
            shutil.copyfileobj(input_file, output_file, length=8 * 1024 * 1024)
        _check_database(restored)
        os.replace(restored, destination)
    print(f"[data-restore] {destination} ({_human_size(destination.stat().st_size)})")


def cleanup_runtime(db_path: Path) -> None:
    """Remove reproducible runtime leftovers while preserving the truth source."""
    data_dir = ROOT / "data"
    _remove_paths(list(data_dir.glob("*.db.bak-*")))
    _remove_paths([data_dir / "_ytframes_tmp"])
    if db_path.exists():
        try:
            con = sqlite3.connect(db_path, timeout=10)
            try:
                result = con.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
                print(f"[data-clean] wal_checkpoint={result}")
            finally:
                con.close()
        except sqlite3.Error as exc:
            print(f"[data-clean] WAL checkpoint skipped: {exc}")
    print("[data-clean] removed in-project DB backups and frame cache")


def show_status(db_path: Path, backup_dir: Path) -> None:
    paths = [db_path, SNAPSHOT, MANIFEST, METADATA]
    paths.extend(sorted((ROOT / "data").glob(PART_GLOB)))
    paths.extend(sorted(backup_dir.glob("dev.db.bak-*")) if backup_dir.exists() else [])
    for path in paths:
        if path.exists():
            size = path.stat().st_size if path.is_file() else 0
            print(f"{_human_size(size):>10}  {path}")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    subparsers = parser.add_subparsers(dest="command", required=True)

    backup = subparsers.add_parser("backup")
    backup.add_argument("--backup-dir", type=Path, default=DEFAULT_BACKUP_DIR)
    backup.add_argument("--keep", type=int, default=1)

    snapshot = subparsers.add_parser("snapshot")
    snapshot.add_argument("--single-limit-mb", type=int, default=90)
    snapshot.add_argument("--chunk-mb", type=int, default=24)
    snapshot.add_argument(
        "--preset",
        type=int,
        choices=range(0, 10),
        default=3,
        help="xz compression preset; 3 keeps daily snapshots reasonably fast",
    )

    restore = subparsers.add_parser("restore")
    restore.add_argument("--force", action="store_true")

    subparsers.add_parser("cleanup")

    status = subparsers.add_parser("status")
    status.add_argument("--backup-dir", type=Path, default=DEFAULT_BACKUP_DIR)
    return parser


def main() -> None:
    args = _parser().parse_args()
    db_path = args.db.expanduser().resolve()
    if args.command == "backup":
        backup_database(db_path, args.backup_dir.expanduser().resolve(), args.keep)
    elif args.command == "snapshot":
        create_snapshot(
            db_path,
            single_limit_mb=args.single_limit_mb,
            chunk_mb=args.chunk_mb,
            preset=args.preset,
        )
    elif args.command == "restore":
        restore_snapshot(db_path, args.force)
    elif args.command == "cleanup":
        cleanup_runtime(db_path)
    elif args.command == "status":
        show_status(db_path, args.backup_dir.expanduser().resolve())


if __name__ == "__main__":
    main()
