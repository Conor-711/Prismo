from copy import deepcopy
from datetime import datetime, timezone
import json
from types import SimpleNamespace

import pytest

from pipeline.domain.opinions.supporting_sources import enrich_collection, public_source_url
from pipeline.domain.opinions import supporting_sources
from pipeline.jobs.opinion_sources import export_sources
from pipeline.jobs.smart_voice.x_realtime import XRealtimeJobs

NOW = datetime(2026, 9, 9, tzinfo=timezone.utc)


def sample():
    opinion = dict(id="call-1", ticker="NVDA", authorId="author-1", platform="X",
                   sourcePostId="post-1", originalText="The company disclosed new capacity. My target is higher.",
                   publishedAt="2026-03-30T12:00:00Z", score=88)
    source = dict(id="source-1", eventId="event-1", ticker="NVDA", publisher="Publisher",
                  sourceType="news", relationship="related", status="ready",
                  title="Capacity report", summary="A report about capacity.",
                  publishedAt="2026-03-16T12:00:00Z", sourceURL="https://example.com/report",
                  claim="The company disclosed new capacity.", excerpt="New capacity", locator="Opening paragraph")
    entry = {key: opinion[key] for key in ("ticker", "authorId", "platform", "sourcePostId")}
    entry.update(reviewed=True, source=source)
    return opinion, entry


def attach(opinion, entries):
    return enrich_collection("smart-account-updates", [opinion], catalogue=entries, now=NOW)[0]


@pytest.mark.parametrize("kind", ["company", "regulatory", "news", "research", "data", "other"])
def test_accepts_all_reviewed_factual_source_types_without_changing_opinion(kind):
    opinion, entry = sample()
    entry["source"]["sourceType"] = kind
    result = attach(opinion, [entry])
    assert result["supportingSources"][0]["sourceType"] == kind
    assert {k: v for k, v in result.items() if k != "supportingSources"} == opinion
    assert "supportingSources" not in opinion


@pytest.mark.parametrize("key,value", [("ticker", "MSFT"), ("authorId", "another"),
                                      ("platform", "YouTube"), ("sourcePostId", "another")])
def test_never_matches_by_ticker_or_author_alone(key, value):
    opinion, entry = sample()
    opinion[key] = value
    assert "supportingSources" not in attach(opinion, [entry])


@pytest.mark.parametrize("key,value", [("status", "withdrawn"), ("claim", "Something absent"),
                                      ("excerpt", ""), ("ticker", "MSFT"), ("sourceType", "unknown"),
                                      ("sourceType", []), ("relationship", {}),
                                      ("publishedAt", "2028-01-01T00:00:00Z"),
                                      ("publishedAt", "2026-03-16"), ("sourceURL", "javascript:alert(1)")])
def test_invalid_source_is_hidden_not_a_negative_opinion_state(key, value):
    opinion, entry = sample()
    entry["source"][key] = value
    assert attach(opinion, [entry]) == opinion


def test_later_sources_cannot_be_historical_evidence():
    opinion, entry = sample()
    entry["source"]["publishedAt"] = "2026-04-01T00:00:00Z"
    assert attach(opinion, [entry]) == opinion
    entry["source"]["relationship"] = "follow_up"
    assert attach(opinion, [entry])["supportingSources"][0]["relationship"] == "follow_up"


def test_citation_requires_review_and_duplicate_urls_collapse():
    opinion, entry = sample()
    entry["source"]["relationship"] = "cited"
    assert attach(opinion, [entry]) == opinion
    entry["citationVerified"] = True
    duplicate = deepcopy(entry)
    duplicate["source"]["id"] = "another-id"
    duplicate["source"]["sourceURL"] += "#paragraph"
    result = attach(opinion, [entry, entry, duplicate])
    assert len(result["supportingSources"]) == 1
    assert attach(result, []) == opinion
    entry["reviewed"] = False
    assert attach(result, [entry]) == opinion


@pytest.mark.parametrize("url", ["http://example.com/x", "https://127.0.0.1/x", "https://[::1]/x",
                                     "https://user:password@example.com/x", "https://server.local/x",
                                     "https://example.com:8080/x", "https://localhost/x", "file:///tmp/x"])
def test_source_urls_cannot_link_to_private_or_executable_locations(url):
    assert public_source_url(url) is None


def test_other_collections_and_pure_subjective_views_are_unchanged():
    opinion, entry = sample()
    opinion["originalText"] = "Price may bounce from the moving average."
    assert attach(opinion, [entry]) == opinion
    assert enrich_collection("smart-money", [opinion], catalogue=[entry]) == [opinion]


def test_realtime_job_attaches_before_publication_and_removes_withdrawn_sources(monkeypatch):
    opinion, entry = sample()
    repository = SimpleNamespace(ready_updates=lambda **kwargs: [opinion])
    jobs = XRealtimeJobs(repository, None, None)
    publications = []
    monkeypatch.setattr(supporting_sources, "load_catalogue", lambda: [entry])
    publish = lambda collections, version: publications.append(collections)
    assert jobs.publish(publish) == 1
    assert publications[0]["smart-account-updates"][0]["supportingSources"]
    assert "supportingSources" not in opinion
    monkeypatch.setattr(supporting_sources, "load_catalogue", lambda: [])
    jobs.publish(publish)
    assert publications[1]["smart-account-updates"] == [opinion]


def test_export_refreshes_recent_and_historical_sources_idempotently(tmp_path):
    opinion, entry = sample()
    inputs, outputs = tmp_path / "input", tmp_path / "output"
    inputs.mkdir()
    for name in supporting_sources.COLLECTIONS:
        (inputs / f"{name}.json").write_text(json.dumps([opinion]), encoding="utf-8")
    catalogue = tmp_path / "catalogue.json"
    catalogue.write_text(json.dumps([entry]), encoding="utf-8")
    counts = export_sources(inputs, outputs, catalogue)
    assert set(counts.values()) == {1}
    assert export_sources(outputs, outputs, catalogue) == counts
    catalogue.write_text("[]", encoding="utf-8")
    assert set(export_sources(outputs, outputs, catalogue).values()) == {0}
    for name in counts:
        assert json.loads((outputs / f"{name}.json").read_text()) == [opinion]


def test_missing_or_malformed_catalogue_does_not_block_original_opinions(tmp_path):
    path = tmp_path / "missing.json"
    assert supporting_sources.load_catalogue(path) == []
    path.write_text("not JSON", encoding="utf-8")
    assert supporting_sources.load_catalogue(path) == []
