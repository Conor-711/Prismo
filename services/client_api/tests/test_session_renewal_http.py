import asyncio
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import httpx
from sqlalchemy import update

from services.client_api.accounts.repository import AccountBase, AccountRepository, SessionFamilyRecord
from services.client_api.config import ClientAPISettings, REPO_ROOT
from services.client_api.main import create_app
from services.client_api.tests.test_session_renewal import login


def test_http_rotation_auth_isolation_replay_and_logout(tmp_path, monkeypatch):
    monkeypatch.setenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "1")
    monkeypatch.setenv("BSMART_GOOGLE_SERVER_CLIENT_ID", "server.google")
    monkeypatch.setenv("BSMART_GOOGLE_IOS_CLIENT_ID", "ios.google")
    database = f"sqlite:///{tmp_path / 'renewal-http.db'}"
    accounts = AccountRepository(database)
    AccountBase.metadata.create_all(accounts.engine)
    app = create_app(ClientAPISettings(environment="test", database_url=database,
        read_model_mode="fixture", fixture_root=REPO_ROOT / "contracts/fixtures"))

    def allow_rotation():
        with accounts.sessions.begin() as db:
            db.execute(update(SessionFamilyRecord).values(rotated_at=datetime.now(UTC) - timedelta(minutes=2)))

    async def check():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="https://test") as client:
                installation = uuid4()
                async def register(identifier):
                    result = await client.post("/v1/installations", json={"installationId": str(identifier),
                        "platform": "ios", "appVersion": "1.0", "locale": "en_US", "timeZone": "UTC"})
                    assert result.status_code == 201
                    return {"Authorization": f"Bearer {result.json()['accessToken']}"}
                headers, foreign = await register(installation), await register(uuid4())
                _, original = login(accounts, installation)
                account_headers = {"Authorization": f"Bearer {original.accessToken}"}
                refresh_headers = {"Authorization": f"Bearer {original.refreshToken}"}
                body = {"refreshToken": original.refreshToken}
                for auth in [{}, account_headers, refresh_headers]:
                    for path in ["refresh", "revoke"]:
                        response = await client.post(f"/v1/auth/sessions/{path}", json=body, headers=auth)
                        assert response.status_code == 401
                        assert response.headers["cache-control"] == "no-store"
                assert (await client.get("/v1/auth/account", headers=refresh_headers)).status_code == 401
                for invalid in [{"refreshToken": "sensitive-short"}, {**body, "privateKey": "never-accept"},
                                {"refreshToken": original.refreshToken + "\n"}]:
                    rejected = await client.post("/v1/auth/sessions/refresh", json=invalid, headers=headers)
                    assert rejected.status_code == 422 and rejected.headers["cache-control"] == "no-store"
                    assert "sensitive-short" not in rejected.text and "never-accept" not in rejected.text
                    assert original.refreshToken not in rejected.text
                assert (await client.post("/v1/auth/sessions/refresh", json=body, headers=foreign)).status_code == 401
                assert (await client.post("/v1/auth/sessions/revoke", json=body, headers=foreign)).status_code == 204
                early = await client.post("/v1/auth/sessions/refresh", json=body, headers=headers)
                assert early.status_code == 429 and early.headers["retry-after"] == "60"
                assert (await client.get("/v1/auth/account", headers=account_headers)).status_code == 200
                allow_rotation()
                rotated = await client.post("/v1/auth/sessions/refresh", json=body, headers=headers)
                assert rotated.status_code == 200 and rotated.headers["cache-control"] == "no-store"
                pair = rotated.json()
                assert set(pair) == {"account", "accessToken", "expiresAt", "refreshToken", "refreshExpiresAt"}
                assert pair["account"] == original.account.model_dump(mode="json")
                assert pair["refreshToken"] != original.refreshToken and pair["accessToken"] != original.accessToken
                new_headers = {"Authorization": f"Bearer {pair['accessToken']}"}
                assert (await client.get("/v1/auth/account", headers=account_headers)).status_code == 401
                assert (await client.get("/v1/auth/account", headers=new_headers)).status_code == 200
                replay = await client.post("/v1/auth/sessions/refresh", json=body, headers=headers)
                assert replay.status_code == 401 and replay.headers["cache-control"] == "no-store"
                assert (await client.get("/v1/auth/account", headers=new_headers)).status_code == 401
                _, fresh = login(accounts, installation)
                fresh_headers = {"Authorization": f"Bearer {fresh.accessToken}"}
                # An old family cannot revoke a subsequent interactive login.
                assert (await client.post("/v1/auth/sessions/revoke", json=body, headers=headers)).status_code == 204
                assert (await client.get("/v1/auth/account", headers=fresh_headers)).status_code == 200
                for _ in range(2):
                    logout = await client.post("/v1/auth/sessions/revoke", json={"refreshToken": fresh.refreshToken}, headers=headers)
                    assert logout.status_code == 204 and not logout.content
                    assert logout.headers["cache-control"] == "no-store"
                assert (await client.get("/v1/auth/account", headers=fresh_headers)).status_code == 401
    try:
        asyncio.run(check())
    finally:
        accounts.engine.dispose()
