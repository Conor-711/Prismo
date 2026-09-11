from copy import deepcopy

import pytest
import yaml

from services.client_api.config import REPO_ROOT
from services.client_api.tests.test_api import make_client, register
from services.client_api.read_models import (
    DatabaseReadModelRepository, ReadModelPublisher, RealtimeReadModelPublisher,
    load_read_model_directory,
)


@pytest.mark.parametrize("mode", ["release", "realtime", "partitioned"])
def test_sources_survive_publication_and_withdrawal_changes_etag(tmp_path, mode):
    collections = load_read_model_directory(REPO_ROOT / "contracts" / "fixtures")
    record = next(item for item in collections["smart-account-evidence"] if item.get("supportingSources"))
    database_url = f"sqlite:///{tmp_path / 'sources.db'}"
    repository = DatabaseReadModelRepository(database_url)
    publisher = ReadModelPublisher(database_url) if mode == "release" else RealtimeReadModelPublisher(database_url)

    def publish(version):
        if mode == "release":
            publisher.publish(collections, source_version=version)
        elif mode == "realtime":
            publisher.publish({"smart-account-evidence": [record]}, source_version=version)
        else:
            publisher.publish_partitioned({"smart-account-evidence": [record]}, producer="test",
                                          source_version=version)
    try:
        original = deepcopy(record)
        publish("with-context")
        loaded = next(item for item in repository.smart_account_evidence(record["authorId"])
                      if item["id"] == record["id"])
        assert loaded["supportingSources"]
        assert loaded["score"] == original["score"]
        first_etag = repository.etag("smart-account-evidence")
        assert record == original
        # Source review and withdrawal happen upstream; the API only stores the new projection.
        record.pop("supportingSources")
        publish("withdrawn-context")
        loaded = next(item for item in repository.smart_account_evidence(record["authorId"])
                      if item["id"] == record["id"])
        assert "supportingSources" not in loaded
        assert repository.etag("smart-account-evidence") != first_etag
        assert loaded["score"] == original["score"]
        assert loaded["originalText"] == original["originalText"]
    finally:
        repository.dispose()
        publisher.dispose()


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_evidence_endpoint_preserves_sources_and_stable_etag(tmp_path):
    async with make_client(str(tmp_path)) as client:
        path = "/v1/smart-accounts/1018427617/evidence"
        assert (await client.get(path)).status_code == 401
        _, token = await register(client)
        headers = {"Authorization": f"Bearer {token}"}
        response = await client.get(path, headers=headers)
        assert response.status_code == 200
        record = next(item for item in response.json()
                      if item["id"] == "dc0b0c28-2e07-55e5-91be-e4db8c7a47fa")
        assert record["supportingSources"][0]["publisher"] == "Nebius Group · SEC EDGAR"
        assert record["supportingSources"][0]["claim"] in record["originalText"]
        repeated = await client.get(path, headers=headers)
        assert repeated.status_code == 200
        assert repeated.headers["etag"] == response.headers["etag"]
        assert repeated.json() == response.json()


def test_published_sources_match_optional_openapi_contract():
    schemas = yaml.safe_load((REPO_ROOT / "contracts/openapi/bsmart-v1.yaml").read_text())["components"]["schemas"]
    assert "supportingSources" not in schemas["SmartAccountUpdate"]["required"]
    source_schema = schemas["OpinionSupportingSource"]
    collections = load_read_model_directory(REPO_ROOT / "contracts/fixtures")
    sources = [source for collection in ("smart-account-updates", "smart-account-evidence")
               for opinion in collections[collection] for source in opinion.get("supportingSources", [])]
    assert len(sources) >= 2
    for source in sources:
        assert set(source_schema["required"]).issubset(source)
        for name in source_schema["required"]:
            assert isinstance(source[name], str) and source[name].strip()
        for field in ("sourceType", "relationship", "status"):
            assert source[field] in source_schema["properties"][field]["enum"]
