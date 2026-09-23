from datetime import datetime, timedelta, timezone
import json
from types import SimpleNamespace

import pytest

from pipeline.domain.opinions.official_channels import IssuerChannel, candidates_for_rule
from pipeline.jobs.official_source_refresh import run
from pipeline.jobs.opinion_source_crawl import run as run_opinion_crawl
from pipeline.platforms.source_documents.official import index_links, rss_items, sec_filings
from pipeline.platforms.source_documents.web import CrawlError, Document, WebCrawler


ISSUER = IssuerChannel("NVDA", 1045810, "NVIDIA", feed_url="https://nvidianews.nvidia.com/cats/press_release.xml",
                       article_hosts=("nvidianews.nvidia.com",), article_paths=("/news/",))
NOW = datetime(2026, 9, 22, tzinfo=timezone.utc)


def filing_payload():
    return {"cik": 1045810, "tickers": ["NVDA"], "filings": {"recent": {
        "form": ["8-K", "S-1", "10-Q"],
        "accessionNumber": ["0001045810-26-000123", "0001045810-26-000122", "0001045810-26-000121"],
        "primaryDocument": ["form8k.htm", "s1.htm", "../bad.htm"],
        "filingDate": ["2026-09-22", "2026-09-21", "2026-09-20"],
        "acceptanceDateTime": ["2026-09-22T10:00:00.000Z", "", ""]}}}


def feed():
    return b'''<rss><channel>
      <item><title>NVIDIA reports results</title><link>https://nvidianews.nvidia.com/news/results</link>
      <pubDate>Tue, 22 Sep 2026 10:00:00 GMT</pubDate></item>
      <item><title>Unrelated</title><link>https://example.com/news/claim</link></item>
      <item><title>Wrong path</title><link>https://nvidianews.nvidia.com/account/private</link></item>
    </channel></rss>'''


def article():
    return Document("https://nvidianews.nvidia.com/news/results", "NVIDIA reports results",
                    "Company reported quarterly results and disclosed revenue in its release.",
                    ["2026-09-22T10:00:00Z"], [], [], "a" * 64)


def test_sec_rejects_wrong_identity_schema_and_unsafe_document():
    items = sec_filings(filing_payload(), ticker="NVDA", cik=1045810)
    assert len(items) == 1
    assert items[0]["url"] == "https://www.sec.gov/Archives/edgar/data/1045810/000104581026000123/form8k.htm"
    with pytest.raises(CrawlError, match="issuer_mismatch"):
        sec_filings(filing_payload(), ticker="MU", cik=1045810)
    payload = filing_payload()
    payload["filings"]["recent"]["form"].pop()
    with pytest.raises(CrawlError, match="misaligned"):
        sec_filings(payload, ticker="NVDA", cik=1045810)


def test_rss_accepts_only_first_party_articles_and_rejects_doctype():
    items = rss_items(feed(), hosts=ISSUER.article_hosts, paths=ISSUER.article_paths)
    assert len(items) == 1
    assert items[0]["publishedAt"] == "2026-09-22T10:00:00Z"
    with pytest.raises(CrawlError, match="xml_external_entity"):
        rss_items(b'<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]><rss/>',
                  hosts=ISSUER.article_hosts, paths=ISSUER.article_paths)


def test_index_discards_third_party_and_unapproved_paths():
    doc = article()
    doc.links = [{"url": "https://nvidianews.nvidia.com/news/a", "title": "Release"},
                 {"url": "https://example.com/news/a", "title": "Unrelated"},
                 {"url": "https://nvidianews.nvidia.com/account", "title": "Account"}]
    assert index_links(doc, hosts=ISSUER.article_hosts, paths=ISSUER.article_paths) == [
        {"url": "https://nvidianews.nvidia.com/news/a"}]


def test_payload_fetch_rejects_offsite_private_redirect(tmp_path, monkeypatch):
    crawler = WebCrawler(tmp_path)
    monkeypatch.setattr(crawler, "_allowed", lambda url: True)
    monkeypatch.setattr(crawler, "_get", lambda url: (302, {"location": "https://127.0.0.1/private"}, b""))
    with pytest.raises(CrawlError, match="ip_literal"):
        crawler.fetch_payload("https://example.com/feed.xml", content_types=("text/xml",))


class FakeCrawler:
    requests = 3
    fail = False

    def fetch_payload(self, url, *, content_types):
        if self.fail:
            raise CrawlError("http_503")
        if "data.sec.gov" in url:
            return url, json.dumps(filing_payload()).encode()
        return url, feed()

    def fetch(self, url):
        return article()


def test_refresh_keeps_last_good_on_source_failure_and_never_attaches_to_opinions(tmp_path):
    crawler = FakeCrawler()
    report = run(output_dir=tmp_path, contact="ops@example.com", issuers=(ISSUER,), crawler=crawler, now=NOW)
    assert report["degraded"] is False
    assert report["candidateCount"] == 2
    index = json.loads((tmp_path / "index.json").read_text())
    assert index["channels"]["NVDA:sec"]["items"][0]["reviewStatus"] == "candidate"
    assert "opinionId" not in str(index)
    crawler.fail = True
    report = run(output_dir=tmp_path, contact="ops@example.com", issuers=(ISSUER,), crawler=crawler,
                 now=NOW + timedelta(hours=1))
    assert report["degraded"] is True
    assert report["candidateCount"] == 2
    assert all(item["status"] == "error" for item in report["channels"])
    index = json.loads((tmp_path / "index.json").read_text())
    assert index["channels"]["NVDA:sec"]["lastSuccessAt"] == NOW.isoformat()


def test_sec_not_configured_does_not_block_issuer_feed(tmp_path):
    report = run(output_dir=tmp_path, issuers=(ISSUER,), crawler=FakeCrawler(), now=NOW)
    assert report["channels"][0]["status"] == "not_configured"
    assert report["channels"][1]["status"] == "ok"
    assert report["candidateCount"] == 1


def test_sec_only_issuer_has_no_phantom_newsroom_channel(tmp_path):
    issuer = IssuerChannel("NVDA", 1045810, "NVIDIA")
    report = run(output_dir=tmp_path, contact="ops@example.com", issuers=(issuer,),
                 crawler=FakeCrawler(), now=NOW)
    assert [item["channel"] for item in report["channels"]] == ["NVDA:sec"]
    assert report["coveredTickers"] == ["NVDA"]


def test_review_rule_requires_exact_publisher_date_and_title():
    index = {"channels": {"NVDA:issuer": {"items": [
        {"url": "https://nvidianews.nvidia.com/news/results", "publisher": "NVIDIA",
         "publishedAt": "2026-09-22T10:00:00Z", "title": "NVIDIA reports results"},
        {"url": "https://nvidianews.nvidia.com/news/other", "publisher": "NVIDIA",
         "publishedAt": "2026-09-21T10:00:00Z", "title": "NVIDIA reports results"}]}}}
    rule = {"ticker": "NVDA", "sourceType": "company", "publisher": "NVIDIA",
            "sourceDate": "2026-09-22", "titleTerms": ["NVIDIA", "results"]}
    assert candidates_for_rule(index, rule) == ["https://nvidianews.nvidia.com/news/results"]
    assert candidates_for_rule(index, {**rule, "publisher": "Associated Press"}) == []
    assert candidates_for_rule(index, {**rule, "sourceType": "news"}) == []


def test_curated_opinion_crawl_can_use_index_without_auto_publishing(tmp_path):
    opinion = {"id": "op-1", "ticker": "NBIS", "platform": "X", "authorId": "author-1",
               "sourcePostId": "post-1", "originalText": "Nebius raised $5 billion.",
               "publishedAt": "2026-08-20T10:00:00Z"}
    spec = {"id": "financing", "eventId": "financing-2026", "ticker": "NBIS", "opinionIds": ["op-1"],
            "claim": "Nebius raised $5 billion.", "titleTerms": ["Nebius", "financing"],
            "requiredPassages": ["Nebius raised $5 billion"], "excerpt": "Nebius raised $5 billion",
            "sourceDate": "2026-08-19", "dateText": "August 19, 2026", "publisher": "Nebius Group",
            "sourceType": "company", "title": "Nebius financing", "summary": "Nebius raised $5 billion.",
            "locator": "Announcement", "useOfficialIndex": True, "indexes": [], "seedURLs": []}
    url = "https://nebius.com/newsroom/financing"
    index = {"channels": {"NBIS:issuer": {"items": [
        {"url": url, "publisher": "Nebius Group", "publishedAt": "2026-08-19T13:00:00Z",
         "title": "Nebius financing"}]}}}
    inputs = tmp_path / "inputs"
    inputs.mkdir()
    for name in ("smart-account-updates", "smart-account-evidence"):
        (inputs / f"{name}.json").write_text(json.dumps([opinion]))
    manifest = tmp_path / "manifest.json"
    manifest.write_text(json.dumps({"rules": [spec]}))
    official = tmp_path / "official.json"
    official.write_text(json.dumps(index))
    document = Document(url, "Nebius financing", "Nebius raised $5 billion on August 19, 2026.",
                        ["2026-08-19T13:00:00Z"], [], [], "a" * 64)
    crawler = SimpleNamespace(requests=0, fetch=lambda target: document)
    result = run_opinion_crawl(input_dir=inputs, output_dir=tmp_path / "out", manifest=manifest,
                               crawler=crawler, official_index_path=official)
    assert result["sourceLinks"] == 1
    assert not (tmp_path / "pipeline/domain/opinions/data/crawled_sources.json").exists()
    assert json.loads((tmp_path / "out/report.json").read_text())["applied"] is False
