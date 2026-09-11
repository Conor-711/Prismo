import json
from tempfile import TemporaryDirectory

import pytest
import yaml

from services.client_api.config import REPO_ROOT
from services.client_api.tests.test_api import make_client, register


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_profile_intro_and_author_endpoint_reference_the_same_early_call():
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            _, token = await register(client)
            headers = {"Authorization": f"Bearer {token}"}
            response = await client.get("/v1/smart-accounts", headers=headers)
            assert response.status_code == 200
            accounts = response.json()
            pool = [a for a in accounts if a.get("platformPercentile") is not None
                    and 0 <= a["platformPercentile"] <= .25 and (a.get("platformRank") or 0) > 0]
            assert pool and all(a.get("representativeWork", {}).get("firstOpinion", {}).get("price") for a in pool)
            wey = next(a for a in accounts if a["handle"] == "@wey_how12640")
            intro = wey["representativeWork"]
            evidence = (await client.get(f"/v1/smart-accounts/{wey['id']}/evidence", headers=headers)).json()
            work = next(w for w in evidence if w["id"] == intro["evidenceId"])
            assert work["ticker"] == intro["ticker"] == "MU"
            assert work["settlement"]["tickerReturnPercent"] == intro["stockReturnPercent"]
            assert intro["publishedAt"] == intro["firstOpinion"]["publishedAt"] == "2025-12-06T02:21:09Z"
            assert intro["entryPrice"] == work["settlement"]["entryPrice"]


def test_optional_contract_and_every_intro_evidence_reference():
    schemas = yaml.safe_load((REPO_ROOT / "contracts/openapi/bsmart-v1.yaml").read_text())["components"]["schemas"]
    assert "representativeWork" not in schemas["SmartAccountProfile"]["required"]
    assert "firstOpinion" not in schemas["SmartAccountUpdate"]["required"]
    root = REPO_ROOT / "contracts/fixtures"
    profiles = json.loads((root / "smart-accounts.json").read_text())
    evidence = {w["id"]: w for w in json.loads((root / "smart-account-evidence.json").read_text())}
    for profile in profiles:
        if intro := profile.get("representativeWork"):
            assert set(schemas["SmartAccountRepresentativeIntro"]["required"]).issubset(intro)
            work = evidence[intro["evidenceId"]]
            assert work["authorId"] == profile["id"]
            assert work["direction"] == intro["direction"]
            assert work["settlement"]["tickerReturnPercent"] == intro["stockReturnPercent"]
