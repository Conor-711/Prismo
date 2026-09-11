from tempfile import TemporaryDirectory

import pytest

from .test_api import make_client, register


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_unchanged_daily_collections_return_304_only_after_authentication():
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            _, token = await register(client)
            headers = {"Authorization": f"Bearer {token}"}
            profiles = await client.get("/v1/smart-accounts", headers=headers)
            identity = profiles.json()[0]["id"]
            for path in ("/v1/smart-accounts", "/v1/smart-account-updates", "/v1/feed",
                         f"/v1/smart-accounts/{identity}/evidence"):
                first = await client.get(path, headers=headers)
                conditional = {**headers, "If-None-Match": first.headers["etag"]}
                second = await client.get(path, headers=conditional)
                assert second.status_code == 304
                assert not second.content
                assert second.headers["etag"] == first.headers["etag"]
                assert (await client.get(path, headers={"If-None-Match": first.headers["etag"]})).status_code == 401
                assert (await client.get(path, headers={**headers, "If-None-Match": '"older"'})).status_code == 200


@pytest.mark.anyio
async def test_mid_read_publication_does_not_cache_a_mismatched_body(monkeypatch):
    with TemporaryDirectory() as directory:
        async with make_client(directory) as client:
            _, token = await register(client)
            repository = client._transport.app.state.read_models
            original = repository.smart_accounts
            def read_and_publish():
                items = original()
                monkeypatch.setattr(repository, "etag", lambda _: "new-version")
                return items
            monkeypatch.setattr(repository, "smart_accounts", read_and_publish)
            response = await client.get("/v1/smart-accounts", headers={"Authorization": f"Bearer {token}"})
            assert response.status_code == 503
