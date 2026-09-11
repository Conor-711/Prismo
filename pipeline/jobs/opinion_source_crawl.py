"""Crawl and associate only the opinion IDs specified by a local sample manifest."""
from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import json
from pathlib import Path

from ..domain.opinions.crawled_sources import AssociationRejected, build_association
from ..domain.opinions.supporting_sources import COLLECTIONS, load_catalogue
from ..platforms.source_documents.web import CrawlError, WebCrawler
from .opinion_sources import export_sources

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "pipeline/domain/opinions/data/local_crawl_samples.json"
CATALOGUE = ROOT / "pipeline/domain/opinions/data/crawled_sources.json"


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def run(*, input_dir: Path, output_dir: Path, manifest: Path = MANIFEST,
        apply: bool = False, refresh: bool = False, request_limit: int = 30,
        crawler=None, catalogue_path: Path = CATALOGUE) -> dict:
    plan = json.loads(manifest.read_text(encoding="utf-8"))
    rules = plan["rules"]
    if not 1 <= len(rules) <= 12:
        raise ValueError("Local experiment requires 1-12 explicitly scoped rules")
    opinions = {}
    for name in sorted(COLLECTIONS):
        for opinion in json.loads((input_dir / f"{name}.json").read_text(encoding="utf-8")):
            opinions[opinion["id"].lower()] = opinion
    crawler = crawler or WebCrawler(output_dir / "cache", request_limit=request_limit, refresh=refresh)
    now = datetime.now(timezone.utc)
    approved, results = [], []
    for spec in rules:
        targets = [opinions[key] for key in spec["opinionIds"] if key in opinions]
        if not targets:
            results.append({"rule": spec["id"], "status": "opinion_not_found"})
            continue
        candidates, errors = [], []
        for index in spec.get("indexes", []):
            try:
                candidates.extend(crawler.discover(index, spec["discoveryTerms"], limit=2))
            except (CrawlError, OSError, ValueError) as error:
                errors.append({"url": index, "error": str(error)})
        # Direct seeds cover archive pages whose older articles are no longer linked.
        candidates = list(dict.fromkeys([*candidates, *spec.get("seedURLs", [])]))[:4]
        accepted = set()
        for url in candidates:
            if len(accepted) == len(targets):
                break
            try:
                document = crawler.fetch(url)
            except (CrawlError, OSError, ValueError) as error:
                errors.append({"url": url, "error": str(error)})
                continue
            for opinion in targets:
                if opinion["id"] in accepted:
                    continue
                try:
                    entry = build_association(spec, opinion, asdict(document), now=now)
                except (AssociationRejected, KeyError, TypeError) as error:
                    errors.append({"url": url, "opinionId": opinion["id"], "error": str(error)})
                    continue
                approved.append(entry)
                accepted.add(opinion["id"])
        results.append({"rule": spec["id"], "status": "attached" if accepted else "no_verified_material",
                        "opinionIds": sorted(accepted), "discoveredURLs": candidates, "errors": errors})
        print(f"{spec['id']}: {len(accepted)}/{len(targets)}", flush=True)

    report = {"checkedAt": now.isoformat(), "requests": crawler.requests, "results": results,
              "attachedOpinions": len({(x["platform"], x["sourcePostId"], x["ticker"]) for x in approved}),
              "sourceLinks": len(approved), "applied": apply}
    report["controls"] = [{"opinionId": key, "present": key in opinions,
                           "hasSupportingSources": bool(opinions.get(key, {}).get("supportingSources"))}
                          for key in plan.get("controlOpinionIds", [])]
    write_json(output_dir / "associations.json", approved)
    write_json(output_dir / "report.json", report)
    if apply:
        existing = json.loads(catalogue_path.read_text(encoding="utf-8")) if catalogue_path.exists() else []
        owned_ids = {"crawl:" + rule["id"] for rule in rules}
        retained = [entry for entry in existing if entry["source"]["id"] not in owned_ids]
        write_json(catalogue_path, retained + approved)
        catalogue = load_catalogue(include_crawled=False) + retained + approved
        report["collections"] = export_sources(input_dir, input_dir, catalogue=catalogue)
        write_json(output_dir / "report.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=ROOT / "contracts/fixtures")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "data/runtime/opinion-source-crawl")
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--apply", action="store_true", help="Update the crawl catalogue and local fixture sources")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--request-limit", type=int, default=30)
    args = parser.parse_args()
    if not 1 <= args.request_limit <= 60:
        parser.error("request-limit must be between 1 and 60")
    report = run(input_dir=args.input_dir, output_dir=args.output_dir, manifest=args.manifest,
                 apply=args.apply, refresh=args.refresh, request_limit=args.request_limit)
    print(json.dumps({key: value for key, value in report.items() if key != "results"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
