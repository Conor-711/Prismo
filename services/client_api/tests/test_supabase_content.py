import hashlib
import json
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine, inspect, select
from sqlalchemy.orm import Session

from services.client_api.content_release.contract import SCHEMAS, PAGE_BYTES, encoded, pages, load_baseline
from services.client_api.content_release.models import Base, Active, Page, Release
from services.client_api.content_release.publisher import publish, rollback, read_collections, merge_x
from services.client_api.content_release.ranking_freeze import apply as apply_frozen_rankings, snapshot as ranking_snapshot
from services.client_api.content_release.prepare import prepare
from services.client_api.tests.test_daily_x_publisher import make_release


def baseline(tmp_path, *, profile_override=None):
    x = make_release(tmp_path / "x")
    collections = {name: [] for name in SCHEMAS}
    profile = json.loads((x / "smart-accounts.json").read_text())[0]
    profile.update(profile_override or {})
    collections["smart-accounts"] = [profile, {**profile, "id": "reddit:b", "platform": "Reddit"},
                                        {**profile, "id": "youtube:c", "platform": "YouTube"}]
    for name in ("smart-account-updates", "smart-account-evidence"):
        collections[name] = json.loads((x / f"{name}.json").read_text())
    stamp = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    metadata = {name: {"checkedAt": stamp, "latestContentAt": stamp} for name in SCHEMAS}
    source = tmp_path / "source"
    source.mkdir()
    for name, items in collections.items():
        (source / f"{name}.json").write_bytes(encoded(items))
    (source / "metadata.json").write_bytes(encoded(metadata))
    directory = tmp_path / "baseline"
    prepare(source, source / "metadata.json", directory)
    return directory


def rescore_release(directory, score, percentile):
    manifest_path = directory / "daily-x-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    for name in ("smart-accounts", "smart-account-updates", "smart-account-evidence"):
        path = directory / f"{name}.json"
        items = json.loads(path.read_text())
        for row in items:
            row["score"] = score
            row["platformPercentile"] = percentile
        raw = json.dumps(items).encode()
        path.write_bytes(raw)
        manifest["collections"][name]["sha256"] = hashlib.sha256(raw).hexdigest()
    manifest_path.write_text(json.dumps(manifest))


@pytest.fixture
def engine(tmp_path):
    value = create_engine(f"sqlite:///{tmp_path / 'isolated.db'}")
    # Tests alone create disposable schemas. The production publisher never does.
    Base.metadata.create_all(value)
    yield value
    value.dispose()


def test_dry_run_has_no_pointer_and_baseline_is_explicit(engine, tmp_path):
    directory = baseline(tmp_path)
    assert publish(engine, directory, baseline=True)["status"] == "validated"
    with Session(engine) as session:
        assert session.get(Active, "production") is None
        assert session.scalars(select(Release)).all() == []
    with pytest.raises(ValueError, match="baseline"):
        publish(engine, make_release(tmp_path / "daily"), apply=True)


def test_daily_atomic_merge_dedupe_and_rollback(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    initial = publish(engine, baseline(tmp_path), baseline=True, apply=True)
    with Session(engine) as session:
        old = session.get(Release, initial["revision"]).manifest
    incoming = make_release(tmp_path / "daily", name="Updated name")
    result = publish(engine, incoming, apply=True)
    assert result["status"] == "published" and not result["publicAPIVerified"]
    with Session(engine) as session:
        current = session.get(Active, "production").revision
        assert current == result["revision"] != initial["revision"]
        rows = read_collections(session, current)
        assert {p["id"] for p in rows["smart-accounts"]} == {"x:a", "reddit:b", "youtube:c"}
        assert next(p for p in rows["smart-accounts"] if p["id"] == "x:a")["name"] == "Updated name"
        assert len(rows["portfolio-signals"]) == 1
        assert session.get(Release, current).manifest["collections"]["smart-money"] == old["collections"]["smart-money"]
        assert read_collections(session, initial["revision"])["smart-accounts"][0]["name"] != "Updated name"
    assert publish(engine, incoming, apply=True)["status"] == "already-published"
    assert rollback(engine, initial["revision"])["status"] == "validated"
    rollback(engine, initial["revision"], apply=True)
    with Session(engine) as session:
        assert session.get(Active, "production").revision == initial["revision"]
    assert session.get(Release, initial["revision"]).manifest == old


def test_older_x_package_adds_history_without_replacing_newer_content(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    publish(engine, baseline(tmp_path), baseline=True, apply=True)
    current = make_release(tmp_path / "current", name="Current biography",
                           as_of=datetime.now(timezone.utc) - timedelta(minutes=2))
    first = publish(engine, current, apply=True)
    prior_through = json.loads((current / "daily-x-manifest.json").read_text())["sourceThrough"]

    older = make_release(tmp_path / "older", name="Outdated biography")
    manifest_path = older / "daily-x-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["sourceThrough"] = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
    for name, identity in (("smart-account-updates", "00000000-0000-0000-0000-000000000003"),
                           ("smart-account-evidence", "00000000-0000-0000-0000-000000000004")):
        path = older / f"{name}.json"
        rows = json.loads(path.read_text())
        rows[0]["id"] = identity
        rows[0]["publishedAt"] = (datetime.now(timezone.utc) - timedelta(hours=3)).isoformat()
        raw = json.dumps(rows).encode()
        path.write_bytes(raw)
        manifest["collections"][name]["sha256"] = hashlib.sha256(raw).hexdigest()
    manifest_path.write_text(json.dumps(manifest))

    monkeypatch.setattr("services.client_api.content_release.publisher.should_enqueue",
                        lambda *_args: pytest.fail("Historical backfill must not send push"))
    result = publish(engine, older, apply=True)
    with Session(engine) as session:
        release = session.get(Release, result["revision"])
        rows = read_collections(session, result["revision"])
        assert release.provenance["kind"] == "daily-x-backfill"
        assert release.provenance["xSourceThrough"] == prior_through
        assert len(release.provenance["xPackages"]) == 2
        assert next(row for row in rows["smart-accounts"] if row["id"] == "x:a")["name"] == "Current biography"
        assert {row["id"] for row in rows["smart-account-updates"] if row["platform"] == "X"} == {
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000003",
        }
        assert session.get(Active, "production").revision == result["revision"] != first["revision"]


def test_restore_rankings_keeps_new_content_and_freezes_future_publications(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    reviewed = baseline(tmp_path, profile_override={"score": 107, "rank": 24,
        "platformRank": 33, "platformPercentile": .141026})

    publish(engine, reviewed, baseline=True, apply=True)
    first = make_release(tmp_path / "first", name="Current biography")
    rescore_release(first, 101, .448276)
    publish(engine, first, apply=True)
    restored = publish(engine, reviewed, restore_rankings=True, apply=True)
    assert restored["status"] == "published"
    assert restored["restoredRankingProfiles"] == 3
    with Session(engine) as session:
        rows = read_collections(session, restored["revision"])
        author = next(row for row in rows["smart-accounts"] if row["id"] == "x:a")
        assert author["name"] == "Current biography"
        # The reviewed baseline's ranking is applied without replacing current content.
        assert author["score"] == 107
        assert author["platformPercentile"] == .141026
        assert rows["smart-account-updates"][0]["score"] == 107
        assert rows["smart-account-updates"][0]["platformPercentile"] == .141026
        assert session.get(Release, restored["revision"]).provenance["rankingsFrozen"]["snapshot"]["x:a"]["score"] == 107

    second = make_release(tmp_path / "second", name="Even newer biography")
    rescore_release(second, 99, .55)
    next_release = publish(engine, second, apply=True)
    with Session(engine) as session:
        rows = read_collections(session, next_release["revision"])
        assert next(row for row in rows["smart-accounts"] if row["id"] == "x:a")["name"] == "Even newer biography"
        assert next(row for row in rows["smart-accounts"] if row["id"] == "x:a")["score"] == 107
        assert rows["smart-account-updates"][0]["score"] == 107
        assert rows["smart-account-updates"][0]["platformPercentile"] == .141026
        assert rows["portfolio-signals"][0]["evidence"][0]["metric"] == "Top 14% on X"


def test_ranking_snapshot_restores_old_score_and_percentile_across_surfaces():
    current = [{"id": "x:a", "platform": "X", "name": "Fresh", "score": 101,
                "scoreChange": -6, "rank": 106, "platformRank": 104, "platformPercentile": .448276}]
    old = [{"id": "x:a", "platform": "X", "score": 107, "scoreChange": 0,
            "rank": 24, "platformRank": 33, "platformPercentile": .141026}]
    frozen, restored = ranking_snapshot(current, old)
    assert restored == 1
    collections = {"smart-accounts": current,
                   "smart-account-updates": [{"id": "view", "authorId": "x:a", "platform": "X", "score": 101,
                                              "platformPercentile": .448276}],
                   "smart-account-evidence": [],
                   "portfolio-signals": [{"kind": "account_leads", "priority": "important", "evidence": [
                       {"source": "smart_account", "referenceId": "view", "title": "Smart Account Score 101.0",
                        "metric": "Top 45% on X"}]}]}
    updated = apply_frozen_rankings(collections, frozen)
    assert updated["smart-accounts"][0]["name"] == "Fresh"
    assert updated["smart-accounts"][0]["score"] == 107
    assert updated["smart-accounts"][0]["platformRank"] == 33
    assert updated["smart-account-updates"][0]["platformPercentile"] == .141026
    assert updated["portfolio-signals"][0]["evidence"][0]["metric"] == "Top 14% on X"


def test_transaction_failure_does_not_activate_partial_release(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    initial = publish(engine, baseline(tmp_path), baseline=True, apply=True)
    def broken(*args):
        raise RuntimeError("disk/upload failed")
    monkeypatch.setattr("services.client_api.content_release.publisher.pages", broken)
    with pytest.raises(RuntimeError):
        publish(engine, make_release(tmp_path / "daily"), apply=True)
    with Session(engine) as session:
        assert session.get(Active, "production").revision == initial["revision"]
        assert len(session.scalars(select(Release)).all()) == 1


def test_stale_and_older_daily_releases_rejected(engine, tmp_path, monkeypatch):
    monkeypatch.setenv("X_INGEST_ENABLED", "false")
    publish(engine, baseline(tmp_path), baseline=True, apply=True)
    publish(engine, make_release(tmp_path / "new"), apply=True)
    with pytest.raises(ValueError, match="Newer"):
        publish(engine, make_release(tmp_path / "old", as_of=datetime.now(timezone.utc) - timedelta(hours=1)), apply=True)
    with pytest.raises(ValueError):
        publish(engine, make_release(tmp_path / "stale", as_of=datetime.now(timezone.utc) - timedelta(days=3)), apply=True)


def test_tamper_schema_duplicates_and_unknown_author_blocked(tmp_path):
    directory = baseline(tmp_path)
    (directory / "smart-accounts.json").write_text("[]")
    with pytest.raises(ValueError, match="Checksum"):
        load_baseline(directory)


def test_drop_guard_and_no_user_collections(tmp_path):
    collections, metadata = load_baseline(baseline(tmp_path))
    collections["smart-accounts"] = [{"id": f"x:{i}", "platform": "X"} for i in range(20)]
    source = {"asOf": datetime.now(timezone.utc).isoformat(), "sourceThrough": datetime.now(timezone.utc).isoformat()}
    with pytest.raises(ValueError, match="25%"):
        merge_x(collections, metadata, {"smart-accounts": []}, source)
    assert not {"portfolio", "wallets", "profiles", "balances", "user-state"} & SCHEMAS.keys()


def test_paging_is_bounded_and_evidence_owner_isolated():
    items = [{"id": str(i), "authorId": "x:a" if i % 2 else "youtube:b", "text": "测试" * 1200} for i in range(210)]
    result = list(pages("a" * 64, "smart-account-evidence", items))
    assert len(result) > 2
    for owner, page, payload in result:
        assert len(encoded(payload)) <= PAGE_BYTES
        assert payload["page"] == page and len(payload["items"]) <= 100
        assert all(item["authorId"] == owner for item in payload["items"])


def test_missing_schema_is_not_created(tmp_path):
    value = create_engine(f"sqlite:///{tmp_path / 'empty.db'}")
    with pytest.raises(Exception):
        publish(value, baseline(tmp_path), baseline=True, apply=True)
    assert inspect(value).get_table_names() == []
    value.dispose()


def test_live_writer_switch_required(engine, tmp_path, monkeypatch):
    publish(engine, baseline(tmp_path), baseline=True, apply=True)
    monkeypatch.delenv("X_INGEST_ENABLED", raising=False)
    with pytest.raises(ValueError, match="realtime"):
        publish(engine, make_release(tmp_path / "daily"), apply=True)


def test_retry_baseline_after_uncertain_response_is_idempotent(engine, tmp_path):
    directory = baseline(tmp_path)
    first = publish(engine, directory, baseline=True, apply=True)
    retry = publish(engine, directory, baseline=True, apply=True)
    assert retry["status"] == "already-published" and retry["revision"] == first["revision"]


def test_hash_survives_jsonb_and_javascript_number_spelling():
    from services.client_api.content_release.contract import digest
    assert digest({"a": [-0.0, 1.0, 2.5]}) == digest({"a": [0, 1, 2.5]})
    assert digest({"a": 1}) != digest({"a": 1.01})
    assert digest({"a": False}) != digest({"a": 0})
    with pytest.raises(ValueError):
        digest({"a": float("nan")})


def test_baseline_reencoding_is_explicit_and_preserves_old_release(engine, tmp_path):
    from copy import deepcopy
    directory = baseline(tmp_path)
    first = publish(engine, directory, baseline=True, apply=True)
    with Session(engine) as session, session.begin():
        release = session.get(Release, first["revision"])
        original = deepcopy(release.manifest)
        original["collections"]["smart-accounts"]["sha256"] = "0" * 64
        # Model a retained release made with the old encoding and its own identity.
        retained = Release(revision="f" * 64, manifest={**original, "revision": "f" * 64}, provenance=release.provenance)
        session.add(retained)
        session.flush()
        for p in session.scalars(select(Page).where(Page.revision == first["revision"])).all():
            session.add(Page(revision=retained.revision, collection=p.collection, owner=p.owner,
                             page=p.page, payload={**p.payload, "revision": retained.revision}))
        session.get(Active, "production").revision = retained.revision
    with pytest.raises(ValueError, match="reencode"):
        publish(engine, directory, baseline=True, apply=True)
    result = publish(engine, directory, baseline=True, reencode_baseline=True, apply=True)
    assert result["status"] == "published" and result["previousRevision"] == "f" * 64
    with Session(engine) as session:
        assert session.get(Release, "f" * 64).manifest["collections"]["smart-accounts"]["sha256"] == "0" * 64
        assert session.get(Active, "production").revision == result["revision"]
        assert session.get(Release, result["revision"]).manifest["collections"]["smart-accounts"]["sha256"] != "0" * 64


def test_reencoding_never_allows_a_different_baseline(engine, tmp_path):
    publish(engine, baseline(tmp_path), baseline=True, apply=True)
    other = tmp_path / "other"
    other.mkdir()
    with pytest.raises(ValueError, match="Baseline already"):
        publish(engine, baseline(other), baseline=True, reencode_baseline=True, apply=True)


def test_checked_time_never_invents_a_later_post_time(tmp_path):
    collections, metadata = load_baseline(baseline(tmp_path))
    source = {"asOf": datetime.now(timezone.utc).isoformat(), "sourceThrough": datetime.now(timezone.utc).isoformat()}
    _, stamps = merge_x(collections, metadata, {"smart-account-updates": []}, source)
    assert stamps["smart-account-updates"]["latestContentAt"] != source["sourceThrough"]


def test_schema_unknown_reference_and_duplicate_identity_rejected(tmp_path):
    from copy import deepcopy
    from services.client_api.content_release.contract import validate
    collections, metadata = load_baseline(baseline(tmp_path))
    broken = deepcopy(collections)
    broken["smart-account-updates"][0]["authorId"] = "x:missing"
    with pytest.raises(ValueError, match="author"):
        validate(broken, metadata)
    broken = deepcopy(collections)
    broken["smart-accounts"].append(broken["smart-accounts"][0])
    with pytest.raises(ValueError, match="Duplicate"):
        validate(broken, metadata)
    broken = deepcopy(collections)
    del broken["smart-accounts"][0]["score"]
    with pytest.raises(Exception):
        validate(broken, metadata)


def test_explicit_historical_test_preserves_dates_and_suppresses_notifications(engine, tmp_path, monkeypatch):
    monkeypatch.setenv('X_INGEST_ENABLED', 'false')
    initial = publish(engine, baseline(tmp_path), baseline=True, apply=True)
    # Simulate an older initial baseline without inventing new dates in the release.
    with Session(engine) as session, session.begin():
        session.get(Release, initial['revision']).provenance = {'kind':'baseline','xPackages':[]}
    old = datetime.now(timezone.utc) - timedelta(days=6)
    directory = make_release(tmp_path/'old-test',as_of=old)
    with pytest.raises(ValueError,match='stale'):
        publish(engine,directory,apply=True)
    def forbidden(*args):pytest.fail('Historical test must never enqueue push')
    monkeypatch.setattr('services.client_api.content_release.publisher.should_enqueue',forbidden)
    result=publish(engine,directory,apply=True,historical_test=True)
    with Session(engine) as session:
        release=session.get(Release,result['revision'])
        assert release.provenance['kind']=='historical-test'
        assert release.provenance['xAsOf']==old.isoformat()
    from services.client_api.content_release.verify_database import verify
    assert verify(engine,result['revision'])['databaseVerified'] is True


def test_database_verification_rejects_corrupted_page(engine,tmp_path):
    result=publish(engine,baseline(tmp_path),baseline=True,apply=True)
    with Session(engine) as session, session.begin():
        row=session.scalar(select(Page).where(Page.revision==result['revision'],Page.collection=='smart-accounts'))
        row.payload={**row.payload,'items':[]}
    from services.client_api.content_release.verify_database import verify
    with pytest.raises(ValueError,match='mismatch'):
        verify(engine,result['revision'])


def test_daily_window_keeps_prior_evidence_for_retained_authors():
    from services.client_api.content_release.publisher import merge_x
    now=datetime.now(timezone.utc).isoformat()
    collections={name:[] for name in SCHEMAS}
    collections['smart-accounts']=[{'id':'x:a','platform':'X'}]
    old=[{'id':str(i),'authorId':'x:a','platform':'X','publishedAt':now} for i in range(20)]
    collections['smart-account-evidence']=old
    metadata={name:{'checkedAt':now,'latestContentAt':None} for name in SCHEMAS}
    incoming={'smart-accounts':collections['smart-accounts'], 'smart-account-evidence':[{**old[0],'thesis':'corrected'}]}
    merged,_=merge_x(collections,metadata,incoming,{'asOf':now,'sourceThrough':now})
    assert len(merged['smart-account-evidence'])==20
    assert merged['smart-account-evidence'][0]['thesis']=='corrected'
    incoming['smart-accounts']=[{'id':'x:b','platform':'X'}]
    incoming['smart-account-evidence']=[]
    with pytest.raises(ValueError,match='drop'):
        merge_x(collections,metadata,incoming,{'asOf':now,'sourceThrough':now})


def test_cached_snapshot_requires_exact_server_hashes(tmp_path,monkeypatch):
    from services.client_api.content_release import cache
    monkeypatch.setattr(cache,'PATH',tmp_path/'current.json')
    items={name:[] for name in SCHEMAS}
    manifest={'collections':{name:{'count':0,'sha256':__import__('services.client_api.content_release.contract',fromlist=['digest']).digest([])} for name in SCHEMAS}}
    cache.save('a'*64,items)
    assert cache.load('a'*64,manifest)==items
    assert cache.load('b'*64,manifest) is None
    stored=json.loads(cache.PATH.read_text());stored['collections']['smart-accounts']=[{'id':'tampered'}]
    cache.PATH.write_text(json.dumps(stored))
    assert cache.load('a'*64,manifest) is None
