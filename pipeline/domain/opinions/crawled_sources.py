"""Claim/date checks for a small, explicitly curated local crawl experiment."""
from __future__ import annotations

from datetime import datetime, time, timezone
from hashlib import sha256

from .supporting_sources import _date, _source


class AssociationRejected(ValueError):
    pass


def normalized(value: str) -> str:
    return " ".join(value.split())


def source_timestamp(spec: dict, document: dict, opinion: dict) -> datetime:
    expected = datetime.strptime(spec["sourceDate"], "%Y-%m-%d").date()
    timestamps = [parsed for value in document["published_values"] if (parsed := _date(value))]
    dated = [value for value in timestamps if value.date() == expected]
    # CMS midnight timestamps often encode just a date, not a verified publication time.
    precise = [value for value in dated if value.time() != time(0, 0)]
    if precise:
        published = min(precise)
    elif dated or normalized(spec["dateText"]) in document["text"]:
        published = datetime.combine(expected, time(23, 59, 59), tzinfo=timezone.utc)
        if expected == _date(opinion["publishedAt"]).date():
            raise AssociationRejected("ambiguous_same_day_publication")
    else:
        raise AssociationRejected("publication_date_not_found")
    return published


def build_association(spec: dict, opinion: dict, document: dict, *, now: datetime) -> dict:
    if (opinion["ticker"] != spec["ticker"] or opinion["id"].lower() not in spec["opinionIds"]
            or spec["claim"] not in (opinion.get("originalText") or "")):
        raise AssociationRejected("opinion_claim_mismatch")
    text = normalized(document["text"])
    if not all(term.casefold() in document["title"].casefold() for term in spec["titleTerms"]):
        raise AssociationRejected("different_article")
    if not all(normalized(passage) in text for passage in spec["requiredPassages"]):
        raise AssociationRejected("factual_passage_not_found")
    if normalized(spec["excerpt"]) not in text or len(spec["excerpt"].split()) > 25:
        raise AssociationRejected("untraceable_or_oversized_excerpt")
    published = source_timestamp(spec, {**document, "text": text}, opinion)
    updates = [parsed for value in document["modified_values"] if (parsed := _date(value)) and parsed > published]
    available = max([published, *updates])
    relationship = "follow_up" if available > _date(opinion["publishedAt"]) else "related"
    source = {field: spec[field] for field in (
        "ticker", "publisher", "sourceType", "title", "titleZH", "summary", "summaryZH",
        "claim", "excerpt", "locator", "contextNote", "contextNoteZH",
    ) if field in spec}
    source.update(id="crawl:" + spec["id"], eventId=spec["eventId"],
                  sourceURL=document["url"], status="ready", relationship=relationship,
                  publishedAt=published.isoformat().replace("+00:00", "Z"))
    if available > published:
        source["updatedAt"] = available.isoformat().replace("+00:00", "Z")
    if published <= _date(opinion["publishedAt"]) < available:
        source["contextNote"] = source.get("contextNote", "") + " This version was updated after the opinion was posted."
        source["contextNoteZH"] = source.get("contextNoteZH", "") + " 当前版本在观点发布后有更新，不作为发帖时已知的资料。"
    entry = {field: opinion[field] for field in ("platform", "authorId", "sourcePostId", "ticker")}
    entry.update(reviewed=True, reviewedOn=now.date().isoformat(), reviewMethod="curated-crawl-v1",
                 source=source, crawl={"retrievedAt": now.isoformat(), "contentHash": document["content_hash"],
                                      "ruleId": spec["id"],
                                      "claimHash": sha256(spec["claim"].encode()).hexdigest()})
    if not _source(entry, opinion, now):
        raise AssociationRejected("source_contract_rejected")
    return entry
