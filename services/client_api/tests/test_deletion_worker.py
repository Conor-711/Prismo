import asyncio
from dataclasses import replace

import httpx
import pytest
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.deletion_service import AccountDeletionService
from services.client_api.accounts.deletion_worker import deletion_worker_lifecycle, run_deletion_worker
from services.client_api.accounts.settings import AccountAuthSettings
from services.client_api.tests.deletion_test_support import accounts, login, accept


@pytest.mark.parametrize("environment,explicit,expected", [("production", "1", False), ("test", "", False),
                                                         ("test", "1", True), ("development", "1", True)])
def test_worker_is_never_enabled_implicitly_or_in_production(monkeypatch, environment, explicit, expected):
    monkeypatch.setenv("BSMART_ACCOUNT_AUTH_DEVELOPMENT", "1")
    monkeypatch.setenv("BSMART_ACCOUNT_DELETION_WORKER", explicit)
    monkeypatch.delenv("BSMART_APPLE_CLIENT_ID", raising=False)
    assert AccountAuthSettings.from_environment(environment).deletion_worker_enabled is expected


def test_periodic_worker_bounds_work_redacts_storage_errors_and_is_cancellable(caplog):
    calls = []
    class Service:
        async def process_due(self, limit):
            calls.append(limit)
            if len(calls) == 1:
                raise OperationalError("secret-sql", {"statusToken": "private-ticket"}, RuntimeError("private-grant"))
    async def sleep(seconds):
        assert seconds == 30
        if len(calls) >= 2:
            raise asyncio.CancelledError()
    async def check():
        with pytest.raises(asyncio.CancelledError):
            await run_deletion_worker(Service(), sleep=sleep)
    asyncio.run(check())
    assert calls == [10, 10]
    assert "pending work retained" in caplog.text
    assert all(value not in caplog.text for value in ["secret-sql", "private-ticket", "private-grant"])


def test_lifespan_resumes_accepted_request_without_client_poll_and_stops_its_task(accounts):
    installation, session = login(accounts)
    repository, request, _ = accept(accounts, session)
    settings = AccountAuthSettings(enabled=True, deletion_worker_enabled=True)
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: pytest.fail("Unexpected provider request"))) as client:
            async with deletion_worker_lifecycle(replace(settings, deletion_worker_enabled=False), accounts, client):
                assert not any(task.get_name() == "bsmart-account-deletion" for task in asyncio.all_tasks())
            async with deletion_worker_lifecycle(settings, accounts, client):
                for _ in range(500):
                    state = repository.status(request.id, installation, request.statusToken.get_secret_value())
                    if state.status == "completed":
                        break
                    await asyncio.sleep(0.002)
                assert state.status == "completed"
            assert not any(task.get_name() == "bsmart-account-deletion" for task in asyncio.all_tasks())
    asyncio.run(check())
