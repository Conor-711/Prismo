import httpx
import pytest

from services.client_api.content_release.contract import SCHEMAS, EVIDENCE, digest, load_baseline, pages
from services.client_api.content_release.verify import verify
from services.client_api.tests.test_supabase_content import baseline


def server(tmp_path, monkeypatch, *, fail=None):
    collections, metadata = load_baseline(baseline(tmp_path))
    collections = {name: sorted(items, key=lambda row: row.get("id", row.get("ticker", ""))) for name, items in collections.items()}
    revision = "a" * 64
    manifest = {"revision": revision, "schemaVersion": 1, "collections": {
        name: {"count": len(items), "sha256": digest(items), **metadata[name]} for name, items in collections.items()}}
    responses = {(name, owner, index): payload for name, items in collections.items()
                 for owner, index, payload in pages(revision, name, items)}
    def request(req):
        assert req.headers["authorization"] == "Bearer a.b.c"
        assert req.headers["apikey"] == "sb_publishable_test"
        if fail == "auth":
            return httpx.Response(401)
        if req.url.path.endswith("manifest"):
            if fail == "revision":
                return httpx.Response(200, json={**manifest, "revision": "b" * 64})
            return httpx.Response(200, json=manifest)
        q = req.url.params
        assert q["revision"] == revision
        payload = responses.get((q["collection"], q["owner"], int(q["page"])))
        if fail == "hash" and q["collection"] == "smart-accounts":
            payload = {**payload, "items": [{**item, "name": "tampered"} for item in payload["items"]]}
        return httpx.Response(200, json=payload)
    factory = httpx.Client
    monkeypatch.setattr("services.client_api.content_release.verify.httpx.Client",
                        lambda **kwargs: factory(**kwargs, transport=httpx.MockTransport(request)))
    return revision


def test_verifier_checks_readable_hashes_and_evidence_not_device(tmp_path, monkeypatch):
    revision = server(tmp_path, monkeypatch)
    result = verify("https://project.supabase.co", "sb_publishable_test", "a.b.c", revision, evidence_owner="x:a")
    assert result["publicAPIVerified"] and not result["iOSDeviceVerified"]
    assert set(result["verifiedCounts"]) == set(SCHEMAS) - {"smart-money-evidence"}
    assert result["verifiedCounts"]["smart-account-evidence"] == 1
    assert "a.b.c" not in str(result)


@pytest.mark.parametrize("failure", ["revision", "hash", "auth"])
def test_verifier_never_accepts_wrong_release_corruption_or_unauthorized(tmp_path, monkeypatch, failure):
    revision = server(tmp_path, monkeypatch, fail=failure)
    with pytest.raises(ValueError):
        verify("https://project.supabase.co", "sb_publishable_test", "a.b.c", revision)


def test_verifier_rejects_untrusted_target_before_sending_tokens():
    for url in ["https://evil.invalid", "http://project.supabase.co", "https://user:pass@project.supabase.co",
                "https://project.supabase.co?redirect=elsewhere"]:
        with pytest.raises(ValueError):
            verify(url, "sb_publishable_test", "a.b.c", "a" * 64)
