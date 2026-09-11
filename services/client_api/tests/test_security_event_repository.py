from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import event as sql_event, select, update
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.apple_repository import AppleGrantRecord, AppleGrantRepository
from services.client_api.accounts.oidc import VerifiedIdentity
from services.client_api.accounts.repository import (AccountBase, AccountRecord, AccountRepository,
    ChallengeRejected, ProviderSubjectRecord, SecurityEventRecord, SessionRecord)
from services.client_api.accounts.security_event_models import VerifiedSecurityEvent, subject_key
from services.client_api.accounts.security_event_repository import SecurityEventRepository
from services.client_api.accounts.session_renewal import SessionRenewalRepository
from services.client_api.accounts.wallet_repository import WalletRepository
from services.client_api.tests.apple_test_support import REFRESH, apple_settings
from services.client_api.tests.test_wallet_binding import ADDRESS, sign


@pytest.fixture
def accounts(tmp_path):
    result = AccountRepository(f"sqlite:///{tmp_path / 'security-only.db'}")
    AccountBase.metadata.create_all(result.engine)
    yield result
    result.engine.dispose()


def login(accounts, when, provider="google", subject="owner"):
    installation = uuid4()
    challenge = accounts.challenge(installation, provider)
    return installation, accounts.issue(challenge.id, installation, VerifiedIdentity(provider, subject, when))


def event(when, action="revoke", provider="google", subject="owner"):
    return VerifiedSecurityEvent(provider, str(uuid4()), "test-" + action, subject, when, action)


def test_revocation_removes_old_and_rotated_sessions_but_preserves_wallet_and_other_provider(accounts):
    now = datetime.now(UTC)
    installation, original = login(accounts, now - timedelta(minutes=5))
    wallets = WalletRepository(accounts)
    proof = wallets.challenge(original.account.id, original.accessToken, ADDRESS)
    binding = wallets.bind(original.account.id, original.accessToken, proof.id, sign(proof))
    _, other_device = login(accounts, now - timedelta(minutes=5))
    _, other_provider = login(accounts, now - timedelta(minutes=5), provider="apple")
    renewed = SessionRenewalRepository(accounts, clock=lambda: now + timedelta(minutes=2)).rotate(original.refreshToken, installation)
    SecurityEventRepository(accounts).apply(event(now))
    for value in [original, other_device, renewed]: assert accounts.authenticate(value.accessToken) is None
    assert accounts.authenticate(other_provider.accessToken) == other_provider.account
    assert wallets.registration(original.account.id) == binding
    with pytest.raises(ChallengeRejected):
        SessionRenewalRepository(accounts, clock=lambda: now + timedelta(minutes=5)).rotate(renewed.refreshToken, installation)


def test_late_notification_and_replay_do_not_revoke_a_newer_interactive_login(accounts):
    now = datetime.now(UTC)
    _, old = login(accounts, now - timedelta(minutes=3))
    _, fresh = login(accounts, now - timedelta(seconds=30))
    repo = SecurityEventRepository(accounts)
    notification = event(now - timedelta(minutes=1))
    repo.apply(notification)
    repo.apply(notification)
    repo.apply(replace(notification, jti=str(uuid4())))
    assert accounts.authenticate(old.accessToken) is None
    assert accounts.authenticate(fresh.accessToken) == fresh.account
    with pytest.raises(ChallengeRejected): login(accounts, now - timedelta(minutes=2))
    _, later = login(accounts, now)
    assert accounts.authenticate(later.accessToken) == later.account


def test_notification_before_account_creation_blocks_stale_identity_and_keeps_subject_private(accounts):
    now = datetime.now(UTC)
    repo = SecurityEventRepository(accounts)
    repo.apply(event(now))
    with pytest.raises(ChallengeRejected): login(accounts, now - timedelta(seconds=1))
    with pytest.raises(ChallengeRejected): login(accounts, None)
    with accounts.sessions() as db:
        assert db.scalar(select(AccountRecord)) is None
        state = db.get(ProviderSubjectRecord, subject_key("google", "owner"))
        assert state is not None and state.id != "owner"
    _, current = login(accounts, now + timedelta(seconds=1))
    assert accounts.authenticate(current.accessToken) == current.account


def test_disabled_google_identity_needs_strictly_newer_enable_and_fresh_login(accounts):
    now = datetime.now(UTC)
    _, session = login(accounts, now + timedelta(seconds=1))
    repo = SecurityEventRepository(accounts)
    repo.apply(event(now, "disable"))
    assert accounts.authenticate(session.accessToken) is None
    for when in [now - timedelta(seconds=1), now]:
        repo.apply(event(when, "enable"))
        with pytest.raises(ChallengeRejected): login(accounts, now + timedelta(seconds=5))
    repo.apply(event(now + timedelta(seconds=2), "enable"))
    assert accounts.authenticate(session.accessToken) is None
    _, restored = login(accounts, now + timedelta(seconds=3))
    assert accounts.authenticate(restored.accessToken) == restored.account
    repo.apply(event(now - timedelta(seconds=1), "disable"))
    assert accounts.authenticate(restored.accessToken) == restored.account


def test_equal_time_conflicting_events_favor_block_regardless_of_order(accounts):
    now = datetime.now(UTC)
    repo = SecurityEventRepository(accounts)
    repo.apply(event(now, "enable"))
    repo.apply(event(now, "disable"))
    with pytest.raises(ChallengeRejected): login(accounts, now + timedelta(seconds=1))


def test_deleted_apple_identity_cannot_be_reenabled_or_have_wallet_mapping_removed(accounts):
    now = datetime.now(UTC)
    _, session = login(accounts, now - timedelta(minutes=1), provider="apple")
    wallets = WalletRepository(accounts)
    proof = wallets.challenge(session.account.id, session.accessToken, ADDRESS)
    binding = wallets.bind(session.account.id, session.accessToken, proof.id, sign(proof))
    repo = SecurityEventRepository(accounts)
    repo.apply(event(now, "delete", "apple"))
    repo.apply(event(now + timedelta(seconds=1), "enable", "apple"))
    with pytest.raises(ChallengeRejected): login(accounts, now + timedelta(seconds=2), provider="apple")
    assert wallets.registration(session.account.id) == binding


@pytest.mark.parametrize("fresh", [False, True])
def test_apple_grant_revocation_respects_provider_authentication_time(accounts, fresh):
    now = datetime.now(UTC)
    settings = apple_settings()
    installation = uuid4()
    challenge = accounts.challenge(installation, "apple")
    identity = VerifiedIdentity("apple", "owner", now + timedelta(seconds=1) if fresh else now - timedelta(minutes=1))
    grants = AppleGrantRepository(accounts)
    session = grants.finish(grants.claim(challenge.id, installation, identity, settings.client_id), REFRESH, settings.cipher)
    SecurityEventRepository(accounts).apply(event(now, "revoke", "apple"))
    with accounts.sessions() as db:
        assert (db.get(AppleGrantRecord, str(session.account.id)) is not None) is fresh


def test_pending_apple_exchange_cannot_finish_after_revocation_or_forge_issue_time(accounts):
    now = datetime.now(UTC)
    installation = uuid4()
    challenge = accounts.challenge(installation, "apple")
    identity = VerifiedIdentity("apple", "owner", now - timedelta(minutes=1))
    settings = apple_settings()
    grants = AppleGrantRepository(accounts)
    claim = grants.claim(challenge.id, installation, identity, settings.client_id)
    SecurityEventRepository(accounts).apply(event(now, "revoke", "apple"))
    for value in [claim, replace(claim, identity=replace(identity, issued_at=now + timedelta(seconds=1)))]:
        with pytest.raises(ChallengeRejected): grants.finish(value, REFRESH, settings.cipher)


def test_failed_transaction_never_acknowledges_or_partially_revokes(accounts):
    now = datetime.now(UTC)
    _, session = login(accounts, now - timedelta(minutes=1))
    notification = event(now)
    repo = SecurityEventRepository(accounts)
    def fail(conn, cursor, statement, parameters, context, many):
        if "DELETE FROM trading_account_session" in statement:
            raise OperationalError("Injected test failure", None, Exception("test-only"))
    sql_event.listen(accounts.engine, "before_cursor_execute", fail)
    try:
        with pytest.raises(OperationalError): repo.apply(notification)
    finally:
        sql_event.remove(accounts.engine, "before_cursor_execute", fail)
    assert accounts.authenticate(session.accessToken) == session.account
    with accounts.sessions() as db:
        assert db.get(SecurityEventRecord, notification.receipt_id) is None
        assert db.get(ProviderSubjectRecord, subject_key("google", "owner")).revoked_before is None
    repo.apply(notification)
    assert accounts.authenticate(session.accessToken) is None


def test_concurrent_notification_and_old_identity_login_cannot_leave_a_valid_session(accounts):
    now = datetime.now(UTC)
    repo = SecurityEventRepository(accounts)
    ready = Barrier(2)
    def operation(kind):
        ready.wait(timeout=5)
        if kind == "event": return repo.apply(event(now))
        try: return login(accounts, now - timedelta(seconds=1))[1]
        except ChallengeRejected: return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        _, signed_in = list(pool.map(operation, ["event", "login"]))
    if signed_in is not None: assert accounts.authenticate(signed_in.accessToken) is None


def test_concurrent_notification_and_rotation_cannot_leave_a_live_descendant(accounts):
    now = datetime.now(UTC)
    installation, original = login(accounts, now - timedelta(minutes=5))
    renewals = SessionRenewalRepository(accounts, clock=lambda: now + timedelta(minutes=2))
    ready = Barrier(2)
    def operation(kind):
        ready.wait(timeout=5)
        if kind == "event": return SecurityEventRepository(accounts).apply(event(now))
        try: return renewals.rotate(original.refreshToken, installation)
        except ChallengeRejected: return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        _, descendant = list(pool.map(operation, ["event", "rotation"]))
    assert accounts.authenticate(original.accessToken) is None
    if descendant is not None:
        assert accounts.authenticate(descendant.accessToken) is None
        with pytest.raises(ChallengeRejected): renewals.rotate(descendant.refreshToken, installation)


def test_receipt_retention_preserves_barrier_and_conflicting_jti_cannot_mutate_state(accounts):
    now = datetime.now(UTC)
    repo = SecurityEventRepository(accounts)
    notification = event(now)
    repo.apply(notification)
    _, fresh = login(accounts, now + timedelta(seconds=1))
    with pytest.raises(ChallengeRejected): repo.apply(replace(notification, action="disable", kind="test-disable"))
    assert accounts.authenticate(fresh.accessToken) == fresh.account
    with accounts.sessions.begin() as db:
        db.execute(update(SecurityEventRecord).values(received_at=now - timedelta(days=31)))
    assert repo.prune_receipts(now) == 1
    repo.apply(notification)
    assert accounts.authenticate(fresh.accessToken) == fresh.account
    with pytest.raises(ChallengeRejected): login(accounts, now)
