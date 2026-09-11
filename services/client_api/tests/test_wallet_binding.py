from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from eth_account import Account
from eth_account.messages import encode_defunct
from sqlalchemy import select, update

from services.client_api.accounts.oidc import VerifiedIdentity
from services.client_api.accounts.repository import AccountBase, AccountRepository, ChallengeRejected, ChallengeThrottled
from services.client_api.accounts.wallet_models import WalletChallenge
from services.client_api.accounts.wallet_proof import SECP256K1_ORDER, binding_message, verifies_binding
from services.client_api.accounts.wallet_repository import WalletChallengeRecord, WalletConflict, WalletRecord, WalletRepository

# Public deterministic test keys only, never used on a network or with funds.
KEY = bytes.fromhex("11" * 32)
OTHER_KEY = bytes.fromhex("22" * 32)
ADDRESS = Account.from_key(KEY).address.lower()
OTHER_ADDRESS = Account.from_key(OTHER_KEY).address.lower()


def sign(challenge, key=KEY):
    return "0x" + Account.sign_message(encode_defunct(text=binding_message(challenge)), private_key=key).signature.hex()


@pytest.fixture
def repo(tmp_path):
    accounts = AccountRepository(f"sqlite:///{tmp_path / 'wallet-test.sqlite'}")
    AccountBase.metadata.create_all(accounts.engine)  # Disposable test database only.
    yield accounts, WalletRepository(accounts)
    accounts.engine.dispose()


def session(accounts, subject="a"):
    install = uuid4()
    challenge = accounts.challenge(install, "apple")
    return accounts.issue(challenge.id, install, VerifiedIdentity("apple", subject))


def test_binding_is_per_account_proof_of_control_not_provider_identity(repo):
    accounts, wallets = repo
    active = session(accounts)
    assert wallets.registration(active.account.id).address is None
    challenge = wallets.challenge(active.account.id, active.accessToken, ADDRESS)
    with pytest.raises(ChallengeRejected):
        wallets.bind(active.account.id, active.accessToken, challenge.id, sign(challenge, OTHER_KEY))
    result = wallets.bind(active.account.id, active.accessToken, challenge.id, sign(challenge))
    assert result.address == ADDRESS
    assert wallets.registration(active.account.id) == result
    with pytest.raises(ChallengeRejected):
        wallets.bind(active.account.id, active.accessToken, challenge.id, sign(challenge))


def test_same_account_session_cannot_replay_another_session_challenge(repo):
    accounts, wallets = repo
    a, b = session(accounts), session(accounts)
    challenge = wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    with pytest.raises(ChallengeRejected):
        wallets.bind(b.account.id, b.accessToken, challenge.id, sign(challenge))
    assert wallets.bind(a.account.id, a.accessToken, challenge.id, sign(challenge)).address == ADDRESS


def test_registered_address_and_account_are_immutable_and_unique(repo):
    accounts, wallets = repo
    a, b = session(accounts, "a"), session(accounts, "b")
    c = wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    wallets.bind(a.account.id, a.accessToken, c.id, sign(c))
    with pytest.raises(WalletConflict):
        wallets.challenge(a.account.id, a.accessToken, OTHER_ADDRESS)
    with pytest.raises(WalletConflict):
        wallets.challenge(b.account.id, b.accessToken, ADDRESS)
    # Reverification with a fresh proof of the same address is allowed.
    c = wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    assert wallets.bind(a.account.id, a.accessToken, c.id, sign(c)).address == ADDRESS


@pytest.mark.parametrize("invalidate", ["logout", "expire"])
def test_revoked_or_expired_session_cannot_bind(repo, invalidate):
    accounts, wallets = repo
    a = session(accounts)
    c = wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    if invalidate == "logout":
        accounts.revoke(a.accessToken)
    else:
        with accounts.sessions.begin() as db:
            db.execute(update(WalletChallengeRecord).values(expires_at=datetime.now(UTC) - timedelta(seconds=1)))
    with pytest.raises(ChallengeRejected):
        wallets.bind(a.account.id, a.accessToken, c.id, sign(c))
    assert wallets.registration(a.account.id).address is None


def test_replay_race_consumes_exactly_once(repo):
    accounts, wallets = repo
    a = session(accounts)
    c = wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    signature = sign(c)

    def attempt():
        try:
            wallets.bind(a.account.id, a.accessToken, c.id, signature)
            return True
        except ChallengeRejected:
            return False

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert sorted(pool.map(lambda _: attempt(), range(2))) == [False, True]
    with accounts.sessions() as db:
        assert len(db.scalars(select(WalletRecord)).all()) == 1


def test_different_device_pending_wallet_cannot_overwrite_winner(repo):
    accounts, wallets = repo
    a, b = session(accounts), session(accounts)
    first = wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    second = wallets.challenge(b.account.id, b.accessToken, OTHER_ADDRESS)
    wallets.bind(a.account.id, a.accessToken, first.id, sign(first))
    with pytest.raises(WalletConflict):
        wallets.bind(b.account.id, b.accessToken, second.id, sign(second, OTHER_KEY))
    assert wallets.registration(a.account.id).address == ADDRESS


def test_challenges_are_bounded_and_zero_address_rejected(repo):
    accounts, wallets = repo
    a = session(accounts)
    with pytest.raises(WalletConflict):
        wallets.challenge(a.account.id, a.accessToken, "0x" + "0" * 40)
    for _ in range(5):
        wallets.challenge(a.account.id, a.accessToken, ADDRESS)
    with pytest.raises(ChallengeThrottled):
        wallets.challenge(a.account.id, a.accessToken, ADDRESS)


def test_signature_domain_fields_and_low_s_are_enforced():
    now = datetime.now(UTC).replace(microsecond=0)
    original = WalletChallenge(id=uuid4(), accountId=uuid4(), address=ADDRESS, nonce="a" * 64,
                               issuedAt=now, expiresAt=now + timedelta(minutes=5))
    signature = sign(original)
    assert verifies_binding(original, signature)
    for field, value in [("accountId", uuid4()), ("id", uuid4()), ("address", OTHER_ADDRESS),
                         ("nonce", "b" * 64), ("expiresAt", now + timedelta(minutes=4))]:
        assert not verifies_binding(original.model_copy(update={field: value}), signature)
    raw = bytes.fromhex(signature[2:])
    high_s = SECP256K1_ORDER - int.from_bytes(raw[32:64], "big")
    malleated = raw[:32] + high_s.to_bytes(32, "big") + bytes([55 - raw[64]])
    assert not verifies_binding(original, "0x" + malleated.hex())
    for invalid in ["0x", "invalid", "0x" + "00" * 65, "0x" + raw[:64].hex() + "00"]:
        assert not verifies_binding(original, invalid)
    # In-range scalars can still fail elliptic-curve recovery; they must return false, not HTTP 500.
    for r in range(1, 40):
        malformed = r.to_bytes(32, "big") + (1).to_bytes(32, "big") + bytes([27])
        assert not verifies_binding(original, "0x" + malformed.hex())


def test_no_runtime_wallet_schema_creation(tmp_path):
    file = tmp_path / "not-created.sqlite"
    accounts = AccountRepository(f"sqlite:///{file}")
    WalletRepository(accounts)
    assert not file.exists()
    accounts.engine.dispose()
