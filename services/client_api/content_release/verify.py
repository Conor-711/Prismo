"""Read the published API with a real user's short-lived token, never an admin key."""
import argparse
import json
import os
import re
from pathlib import Path
from urllib.parse import urlparse

import httpx

from .contract import SCHEMAS, EVIDENCE, digest, validators


def verify(url, key, token, revision, *, evidence_owner=None):
    parsed = urlparse(url)
    if parsed.scheme != "https" or not re.fullmatch(r"[a-z0-9-]+\.supabase\.co", parsed.hostname or "") or parsed.path not in {"", "/"} or any(
        [parsed.username, parsed.password, parsed.port, parsed.query, parsed.fragment]):
        raise ValueError("Expected the HTTPS Supabase project URL")
    if not key.startswith("sb_publishable_") or not re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", token):
        raise ValueError("Use a publishable key and a real user access token")
    if not re.fullmatch(r"[a-f0-9]{64}", revision):
        raise ValueError("Invalid expected revision")
    with httpx.Client(base_url=url.rstrip("/") + "/functions/v1/bsmart-content/", timeout=30, follow_redirects=False,
                      headers={"apikey": key, "Authorization": f"Bearer {token}"}) as client:
        def get(path, **query):
            response = client.get(path, params=query)
            if response.status_code != 200:
                raise ValueError(f"Content API returned HTTP {response.status_code}")
            return response.json()
        manifest = get("manifest")
        if manifest.get("revision") != revision or manifest.get("schemaVersion") != 1 or set(manifest.get("collections", {})) != set(SCHEMAS):
            raise ValueError("Public manifest differs from the expected publication")
        counts = {}
        for name in SCHEMAS:
            if name in EVIDENCE and not (name == "smart-account-evidence" and evidence_owner):
                continue
            owner = evidence_owner if name in EVIDENCE else "_"
            items, index, count, page_count = [], 0, None, None
            while True:
                page = get("page", revision=revision, collection=name, owner=owner, page=index)
                if page.get("revision") != revision or page.get("page") != index or not 1 <= page.get("pages", 0) <= 10000:
                    raise ValueError("Unexpected page revision or sequence")
                if count is None:
                    count, page_count = page["total"], page["pages"]
                if count != page["total"] or page_count != page["pages"] or len(page["items"]) > 100:
                    raise ValueError("Unstable page metadata")
                for item in page["items"]:
                    validators()[name].validate(item)
                items.extend(page["items"])
                index += 1
                if index == page_count:
                    break
            if len(items) != count:
                raise ValueError("Incomplete collection")
            if name not in EVIDENCE:
                entry = manifest["collections"][name]
                normalized = sorted(items, key=lambda row: row.get("id", row.get("ticker", "")))
                if len(items) != entry["count"] or digest(normalized) != entry["sha256"]:
                    raise ValueError("Published collection checksum mismatch")
            elif any(item.get("authorId") != evidence_owner for item in items):
                raise ValueError("Evidence owner mismatch")
            counts[name] = len(items)
        if get("manifest").get("revision") != revision:
            raise ValueError("Active publication changed during verification; retry with its new revision")
        return {"status": "verified", "revision": revision, "publicAPIVerified": True,
                "verifiedCounts": counts, "evidenceOwner": evidence_owner, "iOSDeviceVerified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--evidence-owner")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(os.environ.get("BSMART_CONTENT_SUPABASE_URL", ""),
                        os.environ.get("BSMART_CONTENT_PUBLISHABLE_KEY", ""),
                        os.environ.get("BSMART_CONTENT_ACCESS_TOKEN", ""), args.revision,
                        evidence_owner=args.evidence_owner)
        temporary = args.output.with_suffix(".tmp")
        temporary.write_text(json.dumps(result, indent=2) + "\n")
        temporary.replace(args.output)
        print(json.dumps(result, indent=2))
    except Exception as error:
        print(json.dumps({"status": "failed", "errorType": type(error).__name__,
                          "message": str(error) if isinstance(error, ValueError) else "API verification failed"}))
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
