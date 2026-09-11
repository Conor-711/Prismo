#!/usr/bin/env python3
"""Project verified Reddit profile avatars without changing opinions or rankings."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from pipeline.platforms.author_assets.reddit_profile_avatars import records, username


def enrich(value, verified):
    changed = 0
    if isinstance(value, list):
        return sum(enrich(item, verified) for item in value)
    if not isinstance(value, dict):
        return 0
    if str(value.get("platform", "")).lower() == "reddit":
        identity = value.get("authorId") or value.get("id", "")
        field = "authorAvatarURL" if "authorId" in value else "avatarURL"
        url = verified.get(username(str(identity)))
        if url and not value.get(field):
            value[field] = url
            changed += 1
    return changed + sum(enrich(child, verified) for child in value.values() if isinstance(child, (dict, list)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT / "contracts/fixtures")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    verified = records()
    counts = {}
    for filename in ("smart-accounts.json", "smart-account-updates.json", "smart-account-evidence.json"):
        path = args.directory / filename
        if not path.exists():
            continue
        document = json.loads(path.read_text())
        counts[filename] = enrich(document, verified)
        if args.apply and counts[filename]:
            path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
    if args.apply:
        (args.directory / "reddit-author-avatars.json").write_text(json.dumps(verified, indent=2, sort_keys=True) + "\n")
    profiles = json.loads((args.directory / "smart-accounts.json").read_text())
    unresolved = [row["id"] for row in profiles if row["platform"].lower() == "reddit"
                  and not row.get("avatarURL") and username(row["id"]) not in verified]
    print(json.dumps({"applied": args.apply, "changed": counts, "unresolved": unresolved}, indent=2))


if __name__ == "__main__":
    main()
