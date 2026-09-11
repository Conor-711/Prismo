"""Enrich exported opinion JSON using reviewed factual-source associations."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from ..domain.opinions.supporting_sources import COLLECTIONS, enrich_collection, load_catalogue


def export_sources(input_dir: Path, output_dir: Path, catalogue_path: Path | None = None,
                   *, catalogue: list[dict] | None = None) -> dict[str, int]:
    if catalogue is None:
        catalogue = load_catalogue(catalogue_path) if catalogue_path else load_catalogue()
    prepared = {}
    for name in sorted(COLLECTIONS):
        path = input_dir / f"{name}.json"
        with path.open(encoding="utf-8") as handle:
            opinions = json.load(handle)
        if not isinstance(opinions, list) or any(not isinstance(item, dict) for item in opinions):
            raise ValueError(f"{name} must contain an object array")
        prepared[name] = enrich_collection(name, opinions, catalogue=catalogue)
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, opinions in prepared.items():
        target = output_dir / f"{name}.json"
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(opinions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(target)
    return {name: sum(bool(item.get("supportingSources")) for item in items)
            for name, items in prepared.items()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--catalogue", type=Path)
    args = parser.parse_args()
    print(json.dumps(export_sources(args.input_dir, args.output_dir, args.catalogue), ensure_ascii=False))
