from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import event, func, select, update
from sqlalchemy.exc import OperationalError

from services.client_api.accounts.oidc import VerifiedIdentity
from services.client_api.accounts.repository import (AccountBase, AccountRepository, ChallengeRejected,
    ChallengeThrottled, RefreshRecord, SessionFamilyRecord, SessionRecord)
from services.client_api.accounts.session_renewal import SessionRenewalRepository
from services.client_api.accounts.wallet_repository import WalletRepository
from services.client_api.tests.test_wallet_binding import ADDRESS, sign


@pytest.fixture
def accounts(tmp_path):
    result = AccountRepository(f"sqlite:///{tmp_path / 'session-only.db'}")
    AccountBase.metadata.create_all(result.engine)
    yield result
    result.engine.dispose()


def login(accounts, installation=None, subject="owner"):
    installation = installation or uuid4()
    challenge = accounts.challenge(installation, "google")
    return installation, accounts.issue(challenge.id, installation, VerifiedIdentity("google", subject))


def renewal(accounts, minutes=2):
    now = datetime.now(UTC) + timedelta(minutes=minutes)
    return SessionRenewalRepository(accounts, clock=lambda: now)


def test_rotation_replaces_only_device_credentials_and_preserves_wallet(accounts):
    installation, original = login(accounts)
    wallets = WalletRepository(accounts)
    proof = wallets.challenge(original.account.id, original.accessToken, ADDRESS)
    binding = wallets.bind(original.account.id, original.accessToken, proof.id, sign(proof))
    _, other_device = login(accounts)
    rotated = renewal(accounts).rotate(original.refreshToken, installation)
    assert rotated.account == original.account
    assert rotated.accessToken != original.accessToken and rotated.refreshToken != original.refreshToken
    assert accounts.authenticate(original.accessToken) is None
    assert accounts.authenticate(rotated.accessToken) == original.account
    assert accounts.authenticate(other_device.accessToken) == original.account
    assert accounts.authenticate(rotated.refreshToken) is None
    assert wallets.registration(original.account.id) == binding
    assert rotated.accessToken not in repr(rotated) and rotated.refreshToken not in repr(rotated)
    with accounts.sessions() as db:
        old = db.get(RefreshRecord, accounts.digest(original.refreshToken))
        assert old.consumed_at is not None
        assert db.get(RefreshRecord, original.refreshToken) is None
        assert db.get(SessionRecord, rotated.accessToken) is None


def test_replay_revocation_commits_before_unauthorized_and_does_not_cross_devices(accounts):
    installation, original = login(accounts)
    _, other_device = login(accounts)
    rotated = renewal(accounts).rotate(original.refreshToken, installation)
    with pytest.raises(ChallengeRejected):
        renewal(accounts).rotate(original.refreshToken, installation)
    assert accounts.authenticate(rotated.accessToken) is None
    assert accounts.authenticate(other_device.accessToken) == original.account
    with pytest.raises(ChallengeRejected):
        renewal(accounts, 5).rotate(rotated.refreshToken, installation)
    with accounts.sessions() as db:
        credential = db.get(RefreshRecord, accounts.digest(rotated.refreshToken))
        assert db.get(SessionFamilyRecord, credential.family_id).revoked_at is not None


def test_foreign_installation_cannot_rotate_or_revoke_a_valid_family(accounts):
    installation, original = login(accounts)
    repo = renewal(accounts)
    with pytest.raises(ChallengeRejected):
        repo.rotate(original.refreshToken, uuid4())
    repo.revoke_refresh(original.refreshToken, uuid4())
    assert accounts.authenticate(original.accessToken) == original.account
    assert repo.rotate(original.refreshToken, installation).account == original.account


def test_early_rotation_does_not_consume_an_unused_token(accounts):
    installation, original = login(accounts)
    with pytest.raises(ChallengeThrottled):
        SessionRenewalRepository(accounts).rotate(original.refreshToken, installation)
    assert accounts.authenticate(original.accessToken) == original.account
    assert renewal(accounts).rotate(original.refreshToken, installation).account == original.account


@pytest.mark.parametrize("expired", ["idle", "absolute"])
def test_expired_renewal_never_issues_another_session(accounts, expired):
    installation, original = login(accounts)
    clock = datetime.now(UTC) + (timedelta(days=1, seconds=1) if expired == "idle" else timedelta(days=8))
    with pytest.raises(ChallengeRejected):
        SessionRenewalRepository(accounts, clock=lambda: clock).rotate(original.refreshToken, installation)
    with accounts.sessions() as db:
        assert db.scalar(select(func.count()).select_from(SessionRecord)) == 1


def test_last_rotation_cannot_extend_absolute_lifetime(accounts):
    installation, original = login(accounts)
    limit = datetime.now(UTC) + timedelta(minutes=3)
    with accounts.sessions.begin() as db:
        db.execute(update(SessionFamilyRecord).values(expires_at=limit))
    renewed = renewal(accounts).rotate(original.refreshToken, installation)
    assert renewed.expiresAt == limit and renewed.refreshExpiresAt == limit


@pytest.mark.parametrize("revoke", ["refresh", "access"])
def test_logout_revokes_the_family_but_not_other_devices(accounts, revoke):
    installation, original = login(accounts)
    _, other = login(accounts)
    repo = renewal(accounts)
    if revoke == "access":
        accounts.revoke(original.accessToken)
    else:
        repo.revoke_refresh(original.refreshToken, installation)
        repo.revoke_refresh(original.refreshToken, installation)
    with pytest.raises(ChallengeRejected):
        repo.rotate(original.refreshToken, installation)
    assert accounts.authenticate(original.accessToken) is None
    assert accounts.authenticate(other.accessToken) == other.account


def test_old_refresh_can_revoke_an_uncertain_rotation_after_access_expiry(accounts):
    installation, original = login(accounts)
    repo = renewal(accounts)
    rotated = repo.rotate(original.refreshToken, installation)
    repo.revoke_refresh(original.refreshToken, installation)
    assert accounts.authenticate(rotated.accessToken) is None


def test_concurrent_replay_invalidates_both_the_ancestor_and_returned_descendant(accounts):
    installation, original = login(accounts)
    repo = renewal(accounts)
    ready = Barrier(2)
    def rotate(_):
        ready.wait(timeout=5)
        try: return repo.rotate(original.refreshToken, installation)
        except ChallengeRejected: return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        result = [session for session in pool.map(rotate, range(2)) if session is not None]
    assert len(result) == 1
    assert accounts.authenticate(result[0].accessToken) is None


def test_concurrent_logout_cannot_leave_a_rotated_session_active(accounts):
    installation, original = login(accounts)
    repo = renewal(accounts)
    ready = Barrier(2)
    def operation(kind):
        ready.wait(timeout=5)
        try:
            if kind == "rotate": return repo.rotate(original.refreshToken, installation)
            repo.revoke_refresh(original.refreshToken, installation)
        except ChallengeRejected: pass
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(operation, ["rotate", "logout"]))
    for session in results:
        if session is not None: assert accounts.authenticate(session.accessToken) is None
    assert accounts.authenticate(original.accessToken) is None


def test_failed_rotation_rolls_back_consumption_and_retains_original_session(accounts):
    installation, original = login(accounts)
    def fail(conn, cursor, statement, parameters, context, many):
        if "INSERT INTO trading_session_refresh" in statement:
            raise OperationalError("injected failure", None, Exception("test-only"))
    event.listen(accounts.engine, "before_cursor_execute", fail)
    try:
        with pytest.raises(OperationalError): renewal(accounts).rotate(original.refreshToken, installation)
    finally:
        event.remove(accounts.engine, "before_cursor_execute", fail)
    assert accounts.authenticate(original.accessToken) == original.account
    assert renewal(accounts).rotate(original.refreshToken, installation).account == original.account


def test_fresh_interactive_login_replaces_only_the_same_installation_family(accounts):
    installation, original = login(accounts)
    _, other = login(accounts)
    _, replacement = login(accounts, installation)
    assert replacement.account == original.account
    assert accounts.authenticate(original.accessToken) is None
    assert accounts.authenticate(other.accessToken) == other.account
    with pytest.raises(ChallengeRejected): renewal(accounts).rotate(original.refreshToken, installation)
    assert accounts.authenticate(replacement.accessToken) == replacement.account


def test_concurrent_interactive_login_does_not_leave_old_rotation_active(accounts):
    installation, original = login(accounts)
    repo = renewal(accounts)
    ready = Barrier(2)
    def operation(kind):
        ready.wait(timeout=5)
        if kind == "login": return login(accounts, installation)[1]
        try: return repo.rotate(original.refreshToken, installation)
        except ChallengeRejected: return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        signed_in, rotated = list(pool.map(operation, ["login", "rotate"]))
    assert accounts.authenticate(signed_in.accessToken) == signed_in.account
    assert accounts.authenticate(original.accessToken) is None
    if rotated is not None: assert accounts.authenticate(rotated.accessToken) is None


def test_expired_access_does_not_prevent_refresh_family_logout(accounts):
    installation, original = login(accounts)
    with accounts.sessions.begin() as db:
        db.execute(update(SessionRecord).values(expires_at=datetime.now(UTC) - timedelta(seconds=1)))
    assert accounts.authenticate(original.accessToken) is None
    renewal(accounts).revoke_refresh(original.refreshToken, installation)
    with pytest.raises(ChallengeRejected): renewal(accounts).rotate(original.refreshToken, installation)
