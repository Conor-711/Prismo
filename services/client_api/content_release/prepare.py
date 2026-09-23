"""Create a baseline manifest from reviewed exports and explicit source timestamps."""
import argparse
import hashlib
import json
from pathlib import Path

from .contract import SCHEMAS, encoded, validate


def prepare(source: Path, metadata_path: Path, output: Path):
    if output.resolve() == source.resolve() or output.exists():
        raise ValueError("Use a new output directory; source files are never modified")
    metadata = json.loads(metadata_path.read_text())
    collections = {name: json.loads((source / f"{name}.json").read_text()) for name in SCHEMAS}
    validate(collections, metadata)
    output.mkdir(parents=True)
    entries = {}
    for name, items in collections.items():
        raw = encoded(items)
        (output / f"{name}.json").write_bytes(raw)
        entries[name] = {"count": len(items), "sha256": hashlib.sha256(raw).hexdigest(),
                         "checkedAt": metadata[name]["checkedAt"], "latestContentAt": metadata[name].get("latestContentAt")}
    manifest = {"schemaVersion": 1, "status": "ready", "collections": entries}
    (output / "content-manifest.json").write_bytes(encoded(manifest))
    return {"status": "ready", "counts": {name: len(items) for name, items in collections.items()}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--source-metadata", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.input_dir, args.source_metadata, args.output_dir), indent=2))


if __name__ == "__main__":
    main()
