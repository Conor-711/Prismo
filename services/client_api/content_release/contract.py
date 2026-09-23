"""Validate exported research before it can become an app-visible revision."""
import hashlib
import json
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator, FormatChecker

SCHEMAS = {
    "smart-accounts": "SmartAccountProfile", "smart-account-updates": "SmartAccountUpdate",
    "smart-account-evidence": "SmartAccountUpdate", "portfolio-signals": "PortfolioSignal",
    "ticker-intelligence": "TickerIntelligence", "smart-money": "SmartMoneySignal",
    "smart-money-movements": "SmartMoneyMovement", "smart-money-evidence": "SmartMoneyRepresentativeEvidence",
}
EVIDENCE = {"smart-account-evidence": "authorId", "smart-money-evidence": "accountId"}
PAGE_BYTES = 256 * 1024


def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(value):
    # JSONB and JavaScript erase negative zero and integral-float spelling.
    def numbers(item):
        if isinstance(item, float) and item.is_integer():
            return int(item)
        if isinstance(item, list):
            return [numbers(v) for v in item]
        if isinstance(item, dict):
            return {k: numbers(v) for k, v in item.items()}
        return item
    return hashlib.sha256(encoded(numbers(value))).hexdigest()


def date(value):
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None or result > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise ValueError("Source timestamp requires timezone and cannot be in the future")
    return result


@lru_cache
def validators():
    path = Path(__file__).resolve().parents[3] / "contracts/openapi/bsmart-v1.yaml"
    contract = yaml.safe_load(path.read_text())
    return {name: Draft202012Validator({**contract["components"]["schemas"][schema],
        "components": contract["components"]}, format_checker=FormatChecker()) for name, schema in SCHEMAS.items()}


def validate(collections, metadata):
    if set(collections) != set(SCHEMAS) or set(metadata) != set(SCHEMAS):
        raise ValueError("All eight research collections are required")
    for name, items in collections.items():
        if not isinstance(items, list):
            raise ValueError(f"Not an array: {name}")
        ids = []
        for item in items:
            validators()[name].validate(item)
            identifier = item.get("id", item.get("ticker"))
            if not isinstance(identifier, str) or not identifier:
                raise ValueError(f"Missing identity: {name}")
            ids.append(identifier)
            if len(encoded(item)) > PAGE_BYTES - 1024:
                raise ValueError(f"Document exceeds page budget: {name}/{identifier}")
        if len(ids) != len(set(ids)):
            raise ValueError(f"Duplicate identity: {name}")
        date(metadata[name]["checkedAt"])
        if metadata[name].get("latestContentAt") is not None:
            date(metadata[name]["latestContentAt"])
    authors = {row["id"] for row in collections["smart-accounts"]}
    if not authors:
        raise ValueError("Cannot publish without authors")
    for name in ("smart-account-updates", "smart-account-evidence"):
        if any(row["authorId"] not in authors for row in collections[name]):
            raise ValueError("Unknown author reference")
    money = {row["id"] for row in collections["smart-money"]}
    for row in collections["smart-money"]:
        if row.get("source") not in {"hyperdash", "hyperdash_cached", "hyperliquid_fallback"} or not row.get("sourceUpdatedAt"):
            raise ValueError("Smart Money source provenance is missing")
        date(row["sourceUpdatedAt"])
        if not row.get("scoreSource") or row["scoreSource"] == "unverified" or (
            row["source"] == "hyperdash" and row["scoreSource"] != "hyperdash-copy-score"):
            raise ValueError("Smart Money score provenance is invalid")
    if any(row["accountId"] not in money for name in ("smart-money-evidence", "smart-money-movements") for row in collections[name]):
        raise ValueError("Unknown Smart Money reference")


def load_baseline(directory):
    manifest = json.loads((directory / "content-manifest.json").read_text())
    if manifest.get("schemaVersion") != 1 or manifest.get("status") != "ready":
        raise ValueError("Baseline must have a reviewed ready manifest")
    if set(manifest.get("collections", {})) != set(SCHEMAS):
        raise ValueError("Incomplete baseline manifest")
    collections, metadata = {}, {}
    for name, entry in manifest["collections"].items():
        raw = (directory / f"{name}.json").read_bytes()
        if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            raise ValueError(f"Checksum mismatch: {name}")
        items = json.loads(raw)
        if not isinstance(items, list) or len(items) != entry["count"]:
            raise ValueError(f"Count mismatch: {name}")
        collections[name] = items
        metadata[name] = {"checkedAt": entry["checkedAt"], "latestContentAt": entry.get("latestContentAt")}
    validate(collections, metadata)
    return collections, metadata


def pages(revision, name, items):
    groups = {}
    for item in items:
        owner = item[EVIDENCE[name]] if name in EVIDENCE else "_"
        if not isinstance(owner, str) or not 1 <= len(owner) <= 160 or any(ord(c) < 32 or ord(c) == 127 for c in owner):
            raise ValueError("Invalid page owner")
        groups.setdefault(owner, []).append(item)
    if name not in EVIDENCE:
        groups.setdefault("_", [])
    for owner, documents in groups.items():
        chunks, chunk, size = [], [], 512
        for item in documents:
            length = len(encoded(item)) + 1
            if chunk and (len(chunk) >= 100 or size + length > PAGE_BYTES - 512):
                chunks.append(chunk)
                chunk, size = [], 512
            chunk.append(item)
            size += length
        if chunk or not chunks:
            chunks.append(chunk)
        for page, chunk in enumerate(chunks):
            payload = {"revision": revision, "page": page, "pages": len(chunks), "total": len(documents), "items": chunk}
            if len(encoded(payload)) > PAGE_BYTES or len(chunks) > 10000:
                raise ValueError("Page budget exceeded")
            yield owner, page, payload
