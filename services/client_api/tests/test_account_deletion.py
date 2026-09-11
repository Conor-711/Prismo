import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier
from uuid import uuid4
from pathlib import Path

import httpx
import pytest
from pydantic import ValidationError
from sqlalchemy import delete, event, func, inspect, select, update
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.apple_repository import AppleGrantRecord
from services.client_api.accounts.deletion_models import DeletionInput, DeletionRejected, DeletionReauthenticationRequired, DeletionStatus
from services.client_api.accounts.deletion_repository import DeletionRecord
from services.client_api.accounts.deletion_service import AccountDeletionService
from services.client_api.accounts.deletion_work import AccountDeletionWorkRepository
from services.client_api.accounts.repository import (AccountRecord, AccountRepository, ChallengeRejected, ProviderSubjectRecord,
    RefreshRecord, SessionFamilyRecord, SessionRecord)
from services.client_api.accounts.security_event_repository import SecurityEventRepository
from services.client_api.accounts.security_event_models import VerifiedSecurityEvent, subject_key
from services.client_api.accounts.session_renewal import SessionRenewalRepository
from services.client_api.accounts.wallet_repository import WalletRecord, WalletRepository
from services.client_api.opinion_trades.repository import OpinionFill, PublicTrader, OpinionTradeRepository
from services.client_api.tests.apple_test_support import REFRESH, apple_settings
from services.client_api.tests.deletion_test_support import accounts, login, payload, accept
from services.client_api.tests.test_wallet_binding import ADDRESS, sign
from services.client_api.tests.test_opinion_trades import fill


def test_acceptance_stops_all_devices_and_reauthentication_but_not_another_account(accounts):
    installation, first = login(accounts)
    _, second = login(accounts)
    _, unrelated = login(accounts, subject="someone-else")
    proof = WalletRepository(accounts).challenge(first.account.id, first.accessToken, ADDRESS)
    WalletRepository(accounts).bind(first.account.id, first.accessToken, proof.id, sign(proof))
    repository, request, accepted = accept(accounts, first)
    assert accepted.status == "pending" and accepted.completedAt is None
    assert accounts.authenticate(first.accessToken) is None and accounts.authenticate(second.accessToken) is None
    assert accounts.authenticate(unrelated.accessToken) == unrelated.account
    with pytest.raises(ChallengeRejected):
        login(accounts)
    with pytest.raises(ChallengeRejected):
        SessionRenewalRepository(accounts).rotate(second.refreshToken, installation)
    with accounts.sessions() as db:
        assert db.get(WalletRecord, str(first.account.id)).address == ADDRESS
        record = db.get(DeletionRecord, str(request.id))
        assert record.ticket_hash != request.statusToken.get_secret_value()
    assert repository.status(request.id, installation, request.statusToken.get_secret_value()).status == "pending"
    for other_installation, ticket in [(uuid4(), request.statusToken.get_secret_value()), (installation, "wrong-ticket")]:
        with pytest.raises(DeletionRejected):
            repository.status(request.id, other_installation, ticket)


@pytest.mark.parametrize("age", [301, 3600, -60])
def test_deletion_needs_fresh_interactive_identity_not_merely_a_live_access_token(accounts, age):
    _, session = login(accounts, issued_at=datetime.now(UTC) - timedelta(seconds=age))
    with pytest.raises(DeletionReauthenticationRequired):
        accept(accounts, session)
    assert accounts.authenticate(session.accessToken) == session.account
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(DeletionRecord)) == 0


@pytest.mark.parametrize("problem", ["missing", "wrong-client"])
def test_missing_matching_apple_grant_does_not_lock_or_delete_account(accounts, problem):
    settings = apple_settings()
    _, session = login(accounts, provider="apple", settings=settings)
    with accounts.sessions.begin() as db:
        if problem == "missing":
            db.execute(delete(AppleGrantRecord))
        else:
            db.execute(update(AppleGrantRecord).values(client_id="different.app"))
    with pytest.raises(DeletionReauthenticationRequired):
        accept(accounts, session, settings=settings)
    assert accounts.authenticate(session.accessToken) == session.account


def test_completion_purges_only_deleted_account_and_leaves_minimal_receipt(accounts):
    installation, session = login(accounts)
    _, other = login(accounts, subject="unrelated")
    proof = WalletRepository(accounts).challenge(session.account.id, session.accessToken, ADDRESS)
    WalletRepository(accounts).bind(session.account.id, session.accessToken, proof.id, sign(proof))
    with accounts.sessions.begin() as db:
        for value in [session, other]:
            db.add(PublicTrader(account_id=str(value.account.id), public_id=str(uuid4()), nickname="private", visible=True))
            db.add(OpinionFill(venue="hyperliquid", fill_id=str(uuid4()), opinion_id=str(uuid4()),
                account_id=str(value.account.id), order_id="test-order", ticker="NVDA", side="long", traded_at=datetime.now(UTC)))
    repository, request, _ = accept(accounts, session)
    work = repository.claim(request.id)
    assert work and work.provider == "google"
    repository.complete(work)
    with accounts.sessions() as db:
        for model in (AccountRecord, WalletRecord, AppleGrantRecord, PublicTrader):
            assert db.get(model, str(session.account.id)) is None
        for model in (SessionFamilyRecord, SessionRecord, OpinionFill):
            assert db.scalar(select(func.count()).select_from(model).where(model.account_id == str(session.account.id))) == 0
        assert db.get(PublicTrader, str(other.account.id)).nickname == "private"
        receipt = db.get(DeletionRecord, str(request.id))
        assert receipt.account_id is None and receipt.grant_ciphertext is None and receipt.lease_id is None
    status = repository.status(request.id, installation, request.statusToken.get_secret_value())
    assert status.status == "completed" and status.retryAfterSeconds == 0 and status.completedAt is not None
    assert repository.claim(request.id) is None
    _, recreated = login(accounts)
    assert recreated.account.id != session.account.id
    assert WalletRepository(accounts).registration(recreated.account.id).address is None
    assert accounts.authenticate(other.accessToken) == other.account


def test_provider_error_retains_encrypted_grant_and_backoff_then_retries_safely(accounts):
    settings = apple_settings()
    installation, session = login(accounts, provider="apple", settings=settings)
    now = datetime.now(UTC)
    repository, request, _ = accept(accounts, session, settings=settings, clock=lambda: now)
    calls = []
    def handle(_):
        calls.append(1)
        return httpx.Response(500 if len(calls) == 1 else 200)
    async def check():
        nonlocal now
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = AccountDeletionService(repository, settings, client)
            await service.process(request.id)
            assert repository.due() == []
            await service.process(request.id)
            assert len(calls) == 1
            with accounts.sessions() as db:
                record = db.get(DeletionRecord, str(request.id))
                assert record.status == "pending" and record.grant_ciphertext and record.lease_id is None
                assert REFRESH.encode() not in record.grant_ciphertext
            # A real security notification can remove the original grant while deletion is pending.
            with accounts.sessions.begin() as db:
                db.execute(delete(AppleGrantRecord).where(AppleGrantRecord.account_id == str(session.account.id)))
            now += timedelta(seconds=31)
            assert repository.due() == [request.id]
            await service.process(request.id)
            assert repository.status(request.id, installation, request.statusToken.get_secret_value()).status == "completed"
    asyncio.run(check())
    assert len(calls) == 2


def test_stale_worker_cannot_finalize_new_lease(accounts):
    settings = apple_settings()
    _, session = login(accounts, provider="apple", settings=settings)
    now = datetime.now(UTC)
    repository, request, _ = accept(accounts, session, settings=settings, clock=lambda: now)
    first = repository.claim(request.id)
    assert first and repository.claim(request.id) is None
    now += timedelta(seconds=61)
    second = repository.claim(request.id)
    with pytest.raises(DeletionRejected):
        repository.complete(first)
    repository.retry(first)
    with accounts.sessions() as db:
        assert db.get(DeletionRecord, str(request.id)).lease_id == second.lease_id
    repository.complete(second)


def test_cancelled_provider_request_can_resume_after_durable_lease_expires(accounts):
    settings = apple_settings()
    installation, session = login(accounts, provider="apple", settings=settings)
    now = datetime.now(UTC)
    repository, request, _ = accept(accounts, session, settings=settings, clock=lambda: now)
    calls = []
    def handle(_):
        calls.append(1)
        if len(calls) == 1:
            raise asyncio.CancelledError()
        return httpx.Response(200)
    async def check():
        nonlocal now
        async with httpx.AsyncClient(transport=httpx.MockTransport(handle)) as client:
            service = AccountDeletionService(repository, settings, client)
            with pytest.raises(asyncio.CancelledError):
                await service.process(request.id)
            assert repository.status(request.id, installation, request.statusToken.get_secret_value()).status == "pending"
            await service.process(request.id)
            assert len(calls) == 1
            now += timedelta(seconds=61)
            await service.process_due()
            assert repository.status(request.id, installation, request.statusToken.get_secret_value()).status == "completed"
    asyncio.run(check())


@pytest.mark.parametrize("bad_grant", ["ciphertext", "key", "client", "configuration"])
def test_unreadable_grant_never_contacts_provider_or_completes_deletion(accounts, bad_grant):
    settings = apple_settings()
    installation, session = login(accounts, provider="apple", settings=settings)
    repository, request, _ = accept(accounts, session, settings=settings)
    with accounts.sessions.begin() as db:
        record = db.get(DeletionRecord, str(request.id))
        if bad_grant == "ciphertext": record.grant_ciphertext = b"bad-ciphertext"
        elif bad_grant == "key": record.grant_key_id = "unknown-key"
        elif bad_grant == "client": record.grant_client_id = "other.app"
    async def check():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: pytest.fail("Invalid grant sent"))) as client:
            await AccountDeletionService(repository, None if bad_grant == "configuration" else settings, client).process(request.id)
    asyncio.run(check())
    assert repository.status(request.id, installation, request.statusToken.get_secret_value()).status == "pending"
    with accounts.sessions() as db:
        assert db.get(AccountRecord, str(session.account.id)) is not None


def test_provider_enable_event_cannot_reopen_an_account_being_deleted(accounts):
    _, session = login(accounts)
    accept(accounts, session)
    SecurityEventRepository(accounts).apply(VerifiedSecurityEvent("google", str(uuid4()), "account-enabled",
        "disposable-owner", datetime.now(UTC), "enable"))
    with pytest.raises(ChallengeRejected):
        login(accounts)
    with accounts.sessions() as db:
        assert db.get(ProviderSubjectRecord, subject_key("google", "disposable-owner")).deletion_pending


def test_concurrent_fresh_login_cannot_leave_a_session_after_deletion_acceptance(accounts):
    _, session = login(accounts)
    start = Barrier(2)
    def run(operation):
        start.wait()
        if operation == "delete":
            return accept(accounts, session)
        try:
            return login(accounts)[1]
        except ChallengeRejected:
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(run, ["delete", "login"]))
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(SessionRecord).where(SessionRecord.account_id == str(session.account.id))) == 0


@pytest.mark.parametrize("phase", ["accept", "complete"])
def test_transaction_failure_never_leaves_half_deleted_data_or_false_completion(accounts, phase):
    installation, session = login(accounts)
    request = payload()
    repository = AccountDeletionWorkRepository(accounts)
    if phase == "complete":
        repository.begin(session.account.id, session.accessToken, request, None)
        work = repository.claim(request.id)
    def fail(_, __, statement, parameters, ___, ____):
        if (phase == "accept" and statement.startswith("INSERT INTO trading_account_deletion")) or (
                phase == "complete" and statement.startswith("DELETE FROM trading_account ")):
            raise OperationalError(statement, parameters, RuntimeError("test failure"))
    event.listen(accounts.engine, "before_cursor_execute", fail)
    try:
        with pytest.raises(OperationalError):
            if phase == "accept":
                repository.begin(session.account.id, session.accessToken, request, None)
            else:
                repository.complete(work)
    finally:
        event.remove(accounts.engine, "before_cursor_execute", fail)
    with accounts.sessions() as db:
        assert db.get(AccountRecord, str(session.account.id)) is not None
        record = db.get(DeletionRecord, str(request.id))
        assert record is None if phase == "accept" else record.status == "pending"
    if phase == "accept":
        assert accounts.authenticate(session.accessToken) == session.account
    else:
        repository.complete(work)
        assert repository.status(request.id, installation, request.statusToken.get_secret_value()).status == "completed"


def test_two_workers_cannot_claim_same_deletion_and_old_receipts_expire(accounts):
    installation, session = login(accounts)
    now = datetime.now(UTC)
    repository, request, _ = accept(accounts, session, clock=lambda: now)
    start = Barrier(2)
    def claim(_):
        start.wait()
        return repository.claim(request.id)
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [job for job in pool.map(claim, range(2)) if job is not None]
    assert len(jobs) == 1
    repository.complete(jobs[0])
    now += timedelta(days=30, seconds=1)
    with pytest.raises(DeletionRejected):
        repository.status(request.id, installation, request.statusToken.get_secret_value())
    assert repository.prune_receipts() == 1
    with accounts.sessions() as db:
        assert db.get(ProviderSubjectRecord, subject_key("google", "disposable-owner")) is not None


def test_late_profile_or_fill_cannot_recreate_pending_or_erased_account_data(accounts):
    _, session = login(accounts)
    personal = OpinionTradeRepository(str(accounts.engine.url))
    try:
        item = fill(account_id=session.account.id)
        assert personal.record_confirmed(item)
        repository, request, _ = accept(accounts, session)
        for completed in [False, True]:
            if completed:
                repository.complete(repository.claim(request.id))
            with pytest.raises(ValueError):
                personal.update_public_profile(session.account.id, nickname="late", avatar_url=None, visible=True)
            with pytest.raises(ValueError):
                personal.record_confirmed(item)
        with accounts.sessions() as db:
            assert db.get(PublicTrader, str(session.account.id)) is None
            assert db.scalar(select(func.count()).select_from(OpinionFill)) == 0
    finally:
        personal.engine.dispose()


@pytest.mark.parametrize("changes", [{"confirmDeletion": False}, {"confirmDeletion": 1},
    {"walletRecoveryConfirmed": False}, {"walletRecoveryConfirmed": "true"}, {"statusToken": "short"},
    {"statusToken": "token with spaces" * 3}, {"privateKey": "forbidden"}])
def test_closed_confirmation_contract_rejects_unsafe_input(changes):
    with pytest.raises(ValidationError):
        DeletionInput.model_validate({**payload().model_dump(), **changes})


def test_status_fixture_contains_only_public_progress_fields():
    path = Path(__file__).resolve().parents[3] / "contracts/fixtures/account-deletion-status.json"
    value = json.loads(path.read_text())
    result = DeletionStatus.model_validate(value)
    assert result.status == "pending" and result.completedAt is None
    assert set(value) == {"id", "status", "requestedAt", "completedAt", "retryAfterSeconds"}


def test_deletion_repository_does_not_create_or_migrate_schema():
    accounts = AccountRepository("sqlite:///:memory:")
    try:
        with pytest.raises(OperationalError):
            AccountDeletionWorkRepository(accounts).due()
        assert inspect(accounts.engine).get_table_names() == []
    finally:
        accounts.engine.dispose()
