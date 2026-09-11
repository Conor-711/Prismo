import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, String, delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, mapped_column

from .repository import AccountBase, AccountRecord, AccountRepository, ChallengeRejected, ChallengeThrottled, SessionRecord
from .wallet_models import WalletChallenge, WalletRegistration
from .wallet_proof import verifies_binding


class WalletRecord(AccountBase):
    __tablename__ = "trading_wallet"
    account_id: Mapped[str] = mapped_column(ForeignKey("trading_account.id"), primary_key=True)
    address: Mapped[str] = mapped_column(String(42), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class WalletChallengeRecord(AccountBase):
    __tablename__ = "trading_wallet_challenge"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("trading_account.id"), index=True)
    session_hash: Mapped[str] = mapped_column(String(64), index=True)
    address: Mapped[str] = mapped_column(String(42))
    nonce: Mapped[str] = mapped_column(String(64))
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class WalletConflict(Exception):
    pass


class WalletRepository:
    def __init__(self, accounts: AccountRepository):
        self.accounts = accounts

    def registration(self, account_id: UUID) -> WalletRegistration:
        with self.accounts.sessions() as db:
            value = db.get(WalletRecord, str(account_id))
            return WalletRegistration(accountId=account_id, address=value.address if value else None)

    def challenge(self, account_id: UUID, token: str, address: str) -> WalletChallenge:
        now = datetime.now(UTC).replace(microsecond=0)
        if int(address[2:], 16) == 0:
            raise WalletConflict()
        result = WalletChallenge(id=uuid4(), accountId=account_id, address=address,
                                 nonce=secrets.token_hex(32), issuedAt=now, expiresAt=now + timedelta(minutes=5))
        with self.accounts.sessions.begin() as db:
            # Serializes account-local challenge limits on PostgreSQL.
            db.scalar(select(AccountRecord).where(AccountRecord.id == str(account_id)).with_for_update())
            self.require_session(db, account_id, token)
            self.check_conflict(db, account_id, address)
            db.execute(delete(WalletChallengeRecord).where(WalletChallengeRecord.expires_at <= now))
            count = db.scalar(select(func.count()).select_from(WalletChallengeRecord).where(
                WalletChallengeRecord.account_id == str(account_id)))
            if count >= 5:
                raise ChallengeThrottled()
            db.add(WalletChallengeRecord(id=str(result.id), account_id=str(account_id),
                                         session_hash=self.accounts.digest(token), address=address,
                                         nonce=result.nonce, issued_at=now, expires_at=result.expiresAt))
        return result

    def bind(self, account_id: UUID, token: str, challenge_id: UUID, signature: str) -> WalletRegistration:
        conditions = (WalletChallengeRecord.id == str(challenge_id),
                      WalletChallengeRecord.account_id == str(account_id),
                      WalletChallengeRecord.session_hash == self.accounts.digest(token),
                      WalletChallengeRecord.expires_at > datetime.now(UTC))
        try:
            with self.accounts.sessions.begin() as db:
                self.require_session(db, account_id, token)
                record = db.scalar(select(WalletChallengeRecord).where(*conditions))
                if record is None:
                    raise ChallengeRejected()
                challenge = WalletChallenge(id=record.id, accountId=record.account_id, address=record.address,
                                             nonce=record.nonce, issuedAt=self.utc(record.issued_at),
                                             expiresAt=self.utc(record.expires_at))
                if not verifies_binding(challenge, signature):
                    raise ChallengeRejected()
                # Recheck expiry after signature verification, then consume atomically.
                consumed = db.execute(delete(WalletChallengeRecord).where(
                    *conditions, WalletChallengeRecord.expires_at > datetime.now(UTC)
                ).execution_options(synchronize_session=False)).rowcount
                if consumed != 1:
                    raise ChallengeRejected()
                self.check_conflict(db, account_id, challenge.address)
                if db.get(WalletRecord, str(account_id)) is None:
                    db.add(WalletRecord(account_id=str(account_id), address=challenge.address,
                                        created_at=datetime.now(UTC)))
            return WalletRegistration(accountId=account_id, address=challenge.address)
        except IntegrityError:
            raise WalletConflict() from None

    def require_session(self, db, account_id: UUID, token: str):
        active = db.scalar(select(SessionRecord.token_hash).where(
            SessionRecord.token_hash == self.accounts.digest(token),
            SessionRecord.account_id == str(account_id), SessionRecord.expires_at > datetime.now(UTC)).with_for_update())
        if active is None:
            raise ChallengeRejected()

    @staticmethod
    def check_conflict(db, account_id: UUID, address: str):
        own = db.get(WalletRecord, str(account_id))
        other = db.scalar(select(WalletRecord).where(WalletRecord.address == address))
        if (own and own.address != address) or (other and other.account_id != str(account_id)):
            raise WalletConflict()

    @staticmethod
    def utc(value: datetime) -> datetime:
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
