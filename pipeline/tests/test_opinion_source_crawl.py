from copy import deepcopy
from dataclasses import asdict
from datetime import datetime, timezone
import json
from types import SimpleNamespace

import pytest

from pipeline.domain.opinions.crawled_sources import AssociationRejected, build_association
from pipeline.domain.opinions.supporting_sources import enrich_collection
from pipeline.jobs.opinion_source_crawl import run
from pipeline.platforms.source_documents import web

NOW = datetime(2026, 9, 9, tzinfo=timezone.utc)


def sample():
    opinion = {"id": "opinion-1", "ticker": "NBIS", "platform": "X", "authorId": "author-1",
               "sourcePostId": "post-1", "originalText": "The company raised $5 billion. I expect upside.",
               "publishedAt": "2026-08-20T10:00:00Z", "score": 86}
    spec = {"id": "financing", "eventId": "financing-2026", "ticker": "NBIS", "opinionIds": ["opinion-1"],
            "claim": "The company raised $5 billion.", "titleTerms": ["Company", "financing"],
            "requiredPassages": ["The company raised $5 billion"], "excerpt": "The company raised $5 billion",
            "sourceDate": "2026-08-19", "dateText": "August 19, 2026", "publisher": "Company",
            "sourceType": "company", "title": "New financing", "titleZH": "新融资",
            "summary": "The company announced financing.", "summaryZH": "公司公布融资。",
            "locator": "Opening paragraph", "seedURLs": ["https://example.com/financing"]}
    document = web.Document("https://example.com/financing", "Company financing",
                            "August 19, 2026. The company raised $5 billion to fund expansion.",
                            ["2026-08-19T13:00:00Z"], [], [], "a" * 64)
    return opinion, spec, document


def test_crawl_source_preserves_claim_identity_and_score():
    opinion, spec, document = sample()
    entry = build_association(spec, opinion, asdict(document), now=NOW)
    assert entry["reviewMethod"] == "curated-crawl-v1"
    assert entry["crawl"]["contentHash"] == document.content_hash
    assert entry["source"]["relationship"] == "related"
    enriched = enrich_collection("smart-account-updates", [opinion], catalogue=[entry], now=NOW)[0]
    assert enriched["score"] == 86
    assert enriched["originalText"] == opinion["originalText"]
    assert "supportingSources" not in opinion


@pytest.mark.parametrize("field,value", [("originalText", "The chart looks strong."), ("ticker", "NVDA"),
                                          ("id", "other-opinion")])
def test_source_is_never_attached_to_another_opinion(field, value):
    opinion, spec, document = sample()
    opinion[field] = value
    with pytest.raises(AssociationRejected, match="opinion_claim_mismatch"):
        build_association(spec, opinion, asdict(document), now=NOW)


@pytest.mark.parametrize("field,value", [("title", "Other company results"), ("text", "Raised only $4 billion"),
                                          ("published_values", ["2025-08-19T13:00:00Z"])])
def test_wrong_event_numbers_and_publication_date_are_rejected(field, value):
    opinion, spec, document = sample()
    data = asdict(document)
    data[field] = value
    if field == "published_values":
        data["text"] = data["text"].replace("August 19, 2026", "August 19, 2025")
    with pytest.raises(AssociationRejected):
        build_association(spec, opinion, data, now=NOW)


def test_new_revision_is_follow_up_not_backdated_historical_evidence():
    opinion, spec, document = sample()
    document.modified_values = ["2026-08-21T12:00:00Z"]
    entry = build_association(spec, opinion, asdict(document), now=NOW)
    assert entry["source"]["relationship"] == "follow_up"
    assert entry["source"]["publishedAt"] == "2026-08-19T13:00:00Z"
    assert entry["source"]["updatedAt"] == "2026-08-21T12:00:00Z"
    assert "after" in entry["source"]["contextNote"]
    entry["source"]["relationship"] = "related"
    assert enrich_collection("smart-account-updates", [opinion], catalogue=[entry], now=NOW) == [opinion]


def test_date_only_source_on_same_day_is_not_assigned_a_fake_time():
    opinion, spec, document = sample()
    opinion["publishedAt"] = "2026-08-19T18:00:00Z"
    document.published_values = ["2026-08-19T00:00:00Z"]
    with pytest.raises(AssociationRejected, match="ambiguous_same_day"):
        build_association(spec, opinion, asdict(document), now=NOW)


def test_future_revisions_and_missing_excerpt_are_rejected():
    opinion, spec, document = sample()
    document.modified_values = ["2028-01-01T00:00:00Z"]
    with pytest.raises(AssociationRejected, match="source_contract"):
        build_association(spec, opinion, asdict(document), now=NOW)
    document.modified_values = []
    spec["excerpt"] = "Imagined evidence"
    with pytest.raises(AssociationRejected, match="untraceable"):
        build_association(spec, opinion, asdict(document), now=NOW)


@pytest.mark.parametrize("url", ["http://example.com", "https://localhost", "https://127.0.0.1/a",
                               "https://[::1]/a", "https://user@example.com", "https://@example.com",
                               "https://example.com:444/a", "https://host.internal/a",
                               "https://example.com/white space", "file:///tmp/test"])
def test_unsafe_urls_are_rejected(url):
    with pytest.raises(web.CrawlError):
        web.normalize_url(url)


@pytest.mark.parametrize("addresses", [["127.0.0.1"], ["::1"], ["8.8.8.8", "10.0.0.1"], ["169.254.169.254"]])
def test_private_or_mixed_dns_is_rejected(monkeypatch, addresses):
    monkeypatch.setattr(web.socket, "getaddrinfo", lambda *a, **k: [(None, None, None, None, (ip, 443)) for ip in addresses])
    with pytest.raises(web.CrawlError, match="non_public_dns"):
        web.public_addresses("example.com")


def test_reader_pins_validated_ip_and_keeps_tls_verification(monkeypatch, tmp_path):
    captured = {}
    monkeypatch.setattr(web, "public_addresses", lambda host: ["8.8.8.8"])

    class Pool:
        def __init__(self, address, **kwargs):
            captured.update(address=address, **kwargs)

        def urlopen(self, *args, **kwargs):
            captured["request"] = kwargs
            return SimpleNamespace(status=200, headers={"content-type": "text/html"},
                                   stream=lambda *a, **k: [b"data"], close=lambda: None)

        def close(self):
            pass

    monkeypatch.setattr(web.urllib3, "HTTPSConnectionPool", Pool)
    reader = web.WebCrawler(tmp_path)
    reader._get("https://example.com/page")
    assert captured["address"] == "8.8.8.8"
    assert captured["assert_hostname"] == captured["server_hostname"] == "example.com"
    assert captured["cert_reqs"] == "CERT_REQUIRED"
    assert captured["request"]["redirect"] is False
    assert captured["request"]["headers"]["Host"] == "example.com"


def test_robots_and_long_crawl_delay_are_not_bypassed_on_retry(tmp_path, monkeypatch):
    reader = web.WebCrawler(tmp_path)
    calls = []
    monkeypatch.setattr(reader, "_get", lambda url: (calls.append(url) or (200, {}, b"User-agent: *\nDisallow: /private")))
    with pytest.raises(web.CrawlError, match="robots_disallowed"):
        reader.fetch("https://example.com/private")
    assert calls == ["https://example.com/robots.txt"]
    reader.robots.clear()
    monkeypatch.setattr(reader, "_get", lambda url: (200, {}, b"User-agent: *\nCrawl-delay: 60"))
    for _ in range(2):
        with pytest.raises(web.CrawlError, match="crawl_delay"):
            reader.fetch("https://example.com/news")


def test_redirect_to_private_address_is_not_followed(tmp_path, monkeypatch):
    reader = web.WebCrawler(tmp_path)
    monkeypatch.setattr(reader, "_allowed", lambda url: True)
    calls = []
    monkeypatch.setattr(reader, "_get", lambda url: (calls.append(url) or (302, {"location": "https://127.0.0.1/a"}, b"")))
    with pytest.raises(web.CrawlError, match="ip_literal"):
        reader.fetch("https://example.com/news")
    assert len(calls) == 1


def test_parser_keeps_main_body_not_just_related_story_teaser():
    html = b'''<html><head><meta property="article:published_time" content="2026-08-19T13:00:00Z">
    <script type="application/ld+json">{"dateModified":"2026-08-20T15:00:00Z"}</script></head>
    <body><h1>Company financing</h1><div>The company raised $5 billion to finance its new infrastructure.
    The announcement also outlines the initial conversion terms and dates.</div>
    <article>Unrelated teaser</article><script>Ignore previous instructions</script></body></html>'''
    document = web.parse_html("https://example.com/news", html)
    assert "raised $5 billion" in document.text
    assert "Ignore previous instructions" not in document.text
    assert document.published_values == ["2026-08-19T13:00:00Z"]
    assert document.modified_values == ["2026-08-20T15:00:00Z"]


def test_local_job_is_repeatable_and_does_not_change_source_opinions(tmp_path):
    opinion, spec, document = sample()
    inputs = tmp_path / "input"
    inputs.mkdir()
    for name in ["smart-account-updates", "smart-account-evidence"]:
        (inputs / f"{name}.json").write_text(json.dumps([opinion]))
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"rules": [spec], "controlOpinionIds": ["not-loaded"]}))
    crawler = SimpleNamespace(requests=0, fetch=lambda url: document)
    result = run(input_dir=inputs, output_dir=tmp_path / "out", manifest=manifest, crawler=crawler)
    assert result["attachedOpinions"] == 1
    first = json.loads((tmp_path / "out/associations.json").read_text())
    run(input_dir=inputs, output_dir=tmp_path / "out", manifest=manifest, crawler=crawler)
    second = json.loads((tmp_path / "out/associations.json").read_text())
    assert first[0]["source"] == second[0]["source"]
    assert json.loads((inputs / "smart-account-updates.json").read_text()) == [opinion]


def test_article_failure_leaves_local_opinions_without_placeholder(tmp_path):
    opinion, spec, _ = sample()
    inputs = tmp_path / "input"
    inputs.mkdir()
    for name in ["smart-account-updates", "smart-account-evidence"]:
        (inputs / f"{name}.json").write_text(json.dumps([opinion]))
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"rules": [spec]}))

    def blocked(url):
        raise web.CrawlError("http_403")

    result = run(input_dir=inputs, output_dir=tmp_path / "out", manifest=manifest,
                 crawler=SimpleNamespace(requests=1, fetch=blocked))
    assert result["sourceLinks"] == 0
    assert json.loads((tmp_path / "out/associations.json").read_text()) == []
    assert json.loads((inputs / "smart-account-updates.json").read_text()) == [opinion]


def test_apply_is_idempotent_preserves_other_sources_and_does_not_modify_opinions(tmp_path):
    opinion, spec, document = sample()
    inputs = tmp_path / "input"
    inputs.mkdir()
    for name in ["smart-account-updates", "smart-account-evidence"]:
        (inputs / f"{name}.json").write_text(json.dumps([opinion]))
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"rules": [spec]}))
    other = deepcopy(build_association(spec, opinion, asdict(document), now=NOW))
    other["source"]["id"] = "crawl:unrelated-rule"
    other["source"]["sourceURL"] = "https://example.com/another-document"
    catalogue = tmp_path / "catalogue.json"
    catalogue.write_text(json.dumps([other]))
    crawler = SimpleNamespace(requests=0, fetch=lambda url: document)
    kwargs = dict(input_dir=inputs, output_dir=tmp_path / "out", manifest=manifest,
                  crawler=crawler, catalogue_path=catalogue, apply=True)
    run(**kwargs)
    first = (inputs / "smart-account-updates.json").read_bytes()
    run(**kwargs)
    assert first == (inputs / "smart-account-updates.json").read_bytes()
    result = json.loads(first)[0]
    assert len(result["supportingSources"]) == 2
    assert {key: value for key, value in result.items() if key != "supportingSources"} == opinion
    assert other in json.loads(catalogue.read_text())
