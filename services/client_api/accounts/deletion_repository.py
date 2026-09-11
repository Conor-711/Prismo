"""Durable account-deletion acceptance and status, independent of revoked sessions."""
import math
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import DateTime, Integer, LargeBinary, String, delete, select, update
from sqlalchemy.orm import Mapped, mapped_column

from .apple_repository import AppleExchangeRecord, AppleGrantRecord
from .deletion_models import DeletionInput, DeletionRejected, DeletionReauthenticationRequired, DeletionStatus
from .repository import AccountBase, AccountRecord, AccountRepository, SessionFamilyRecord, SessionRecord
from .security_event_repository import SecurityEventRepository
from .session_renewal import SessionRenewalRepository
from .wallet_repository import WalletChallengeRecord


class DeletionRecord(AccountBase):
    __tablename__ = "trading_account_deletion"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str | None] = mapped_column(String(36), unique=True, nullable=True)
    installation_id: Mapped[str] = mapped_column(String(36))
    ticket_hash: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(16))
    requested_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    lease_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    grant_client_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    grant_key_id: Mapped[str | None] = mapped_column(String(32), nullable=True)
    grant_ciphertext: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)


class AccountDeletionRepository:
    def __init__(self, accounts: AccountRepository, clock=lambda: datetime.now(UTC)):
        self.accounts, self.clock = accounts, clock

    def begin(self, account_id: UUID, access: str, payload: DeletionInput, apple_client_id: str | None):
        now = self.clock()
        with self.accounts.sessions.begin() as db:
            account = db.get(AccountRecord, str(account_id))
            if account is None:
                raise DeletionRejected()
            state = SecurityEventRepository(self.accounts).lock_subject(db, account.provider, account.subject)
            db.scalar(select(AccountRecord).where(AccountRecord.id == account.id).with_for_update())
            family = db.scalar(select(SessionFamilyRecord).join(SessionRecord,
                SessionRecord.family_id == SessionFamilyRecord.id).where(
                SessionRecord.token_hash == self.accounts.digest(access), SessionRecord.account_id == account.id,
                SessionRecord.expires_at > now, SessionFamilyRecord.revoked_at.is_(None),
                SessionFamilyRecord.expires_at > now).with_for_update())
            if family is None or state.deletion_pending or state.state != "active":
                raise DeletionRejected()
            if family.authenticated_at is None or not now - timedelta(minutes=5) <= self.utc(family.authenticated_at) <= now:
                raise DeletionReauthenticationRequired()
            if db.get(DeletionRecord, str(payload.id)) is not None:
                raise DeletionRejected()
            grant = db.get(AppleGrantRecord, account.id) if account.provider == "apple" else None
            if account.provider == "apple" and (grant is None or grant.client_id != apple_client_id):
                raise DeletionReauthenticationRequired()
            record = DeletionRecord(id=str(payload.id), account_id=account.id,
                installation_id=family.installation_id, ticket_hash=self.accounts.digest(payload.statusToken.get_secret_value()),
                status="pending", requested_at=now, next_attempt_at=now, attempts=0,
                grant_client_id=grant.client_id if grant else None, grant_key_id=grant.key_id if grant else None,
                grant_ciphertext=grant.ciphertext if grant else None)
            db.add(record)
            state.deletion_pending = True
            state.revoked_before = max(now, self.utc(state.revoked_before)) if state.revoked_before else now
            db.execute(update(SessionFamilyRecord).where(SessionFamilyRecord.account_id == account.id,
                SessionFamilyRecord.revoked_at.is_(None)).values(revoked_at=now))
            db.execute(delete(SessionRecord).where(SessionRecord.account_id == account.id))
            db.execute(delete(WalletChallengeRecord).where(WalletChallengeRecord.account_id == account.id))
            if account.provider == "apple":
                db.execute(delete(AppleExchangeRecord).where(AppleExchangeRecord.subject == account.subject))
            result = self.present(record, now)
        return result

    def status(self, identifier: UUID, installation: UUID, ticket: str) -> DeletionStatus:
        now = self.clock()
        with self.accounts.sessions() as db:
            record = db.scalar(select(DeletionRecord).where(DeletionRecord.id == str(identifier),
                DeletionRecord.installation_id == str(installation), DeletionRecord.ticket_hash == self.accounts.digest(ticket)))
            if record is None or (record.completed_at is not None and self.utc(record.completed_at) <= now - timedelta(days=30)):
                raise DeletionRejected()
            return self.present(record, now)

    def prune_receipts(self):
        with self.accounts.sessions.begin() as db:
            expired = select(DeletionRecord.id).where(DeletionRecord.status == "completed",
                DeletionRecord.completed_at <= self.clock() - timedelta(days=30)).order_by(DeletionRecord.completed_at).limit(1000)
            return db.execute(delete(DeletionRecord).where(DeletionRecord.id.in_(expired))).rowcount

    @classmethod
    def present(cls, record, now):
        retry = max(30, min(3600, math.ceil((cls.utc(record.next_attempt_at) - now).total_seconds())))
        if record.lease_until:
            retry = max(retry, min(3600, math.ceil((cls.utc(record.lease_until) - now).total_seconds())))
        return DeletionStatus(id=record.id, status=record.status, requestedAt=cls.utc(record.requested_at),
            completedAt=cls.utc(record.completed_at) if record.completed_at else None,
            retryAfterSeconds=0 if record.status == "completed" else retry)

    utc = staticmethod(SessionRenewalRepository.utc)
