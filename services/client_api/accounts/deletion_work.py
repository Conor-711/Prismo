"""Leased deletion work; locks are never held while contacting a provider."""
from dataclasses import dataclass, field
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import delete, select, update

from .apple_repository import AppleExchangeRecord, AppleGrantRecord
from .deletion_models import DeletionRejected
from .deletion_repository import AccountDeletionRepository, DeletionRecord
from .repository import AccountRecord, RefreshRecord, SessionFamilyRecord, SessionRecord
from .security_event_repository import SecurityEventRepository
from .wallet_repository import WalletChallengeRecord, WalletRecord
from ..opinion_trades.repository import OpinionTradeRepository


@dataclass(frozen=True, repr=False)
class DeletionWork:
    id: UUID
    lease_id: str
    account_id: str
    provider: str
    subject: str = field(repr=False)
    client_id: str | None
    key_id: str | None
    ciphertext: bytes | None = field(repr=False)


class AccountDeletionWorkRepository(AccountDeletionRepository):
    def _locked(self, db, identifier):
        # This lookup obtains no row lock. All mutation paths lock subject first.
        account = db.scalar(select(AccountRecord).join(DeletionRecord,
            DeletionRecord.account_id == AccountRecord.id).where(DeletionRecord.id == str(identifier)))
        if account is None:
            return None, None, None
        state = SecurityEventRepository(self.accounts).lock_subject(db, account.provider, account.subject)
        db.scalar(select(AccountRecord).where(AccountRecord.id == account.id).with_for_update())
        db.execute(update(DeletionRecord).where(DeletionRecord.id == str(identifier))
            .values(attempts=DeletionRecord.attempts))
        record = db.get(DeletionRecord, str(identifier), populate_existing=True)
        return record, account, state

    def claim(self, identifier: UUID) -> DeletionWork | None:
        now = self.clock()
        with self.accounts.sessions.begin() as db:
            record, account, state = self._locked(db, identifier)
            if record is None or record.status != "pending":
                return None
            if (not state.deletion_pending or self.utc(record.next_attempt_at) > now
                    or (record.lease_until and self.utc(record.lease_until) > now)):
                return None
            record.lease_id, record.lease_until = str(uuid4()), now + timedelta(seconds=60)
            record.attempts += 1
            return DeletionWork(UUID(record.id), record.lease_id, account.id, account.provider, account.subject,
                                record.grant_client_id, record.grant_key_id, record.grant_ciphertext)

    def retry(self, work: DeletionWork):
        with self.accounts.sessions.begin() as db:
            record, _, _ = self._locked(db, work.id)
            if record is not None and record.status == "pending" and record.lease_id == work.lease_id:
                delay = min(3600, 30 * 2 ** min(record.attempts - 1, 7))
                record.next_attempt_at = self.clock() + timedelta(seconds=delay)
                record.lease_id = record.lease_until = None

    def complete(self, work: DeletionWork):
        now = self.clock()
        with self.accounts.sessions.begin() as db:
            record, account, state = self._locked(db, work.id)
            if (record is None or record.status != "pending" or record.lease_id != work.lease_id
                    or record.lease_until is None or self.utc(record.lease_until) <= now
                    or account.id != work.account_id or not state.deletion_pending):
                raise DeletionRejected()
            families = select(SessionFamilyRecord.id).where(SessionFamilyRecord.account_id == account.id)
            db.execute(delete(SessionRecord).where(SessionRecord.account_id == account.id))
            db.execute(delete(RefreshRecord).where(RefreshRecord.family_id.in_(families)))
            db.execute(delete(SessionFamilyRecord).where(SessionFamilyRecord.account_id == account.id))
            db.execute(delete(WalletChallengeRecord).where(WalletChallengeRecord.account_id == account.id))
            db.execute(delete(WalletRecord).where(WalletRecord.account_id == account.id))
            db.execute(delete(AppleGrantRecord).where(AppleGrantRecord.account_id == account.id))
            if account.provider == "apple":
                db.execute(delete(AppleExchangeRecord).where(AppleExchangeRecord.subject == account.subject))
            OpinionTradeRepository.delete_account_data(db, UUID(account.id))
            db.delete(account)
            state.deletion_pending = False
            state.revoked_before = max(now, self.utc(state.revoked_before)) if state.revoked_before else now
            record.status, record.completed_at = "completed", now
            record.account_id = record.lease_id = record.lease_until = None
            record.grant_client_id = record.grant_key_id = record.grant_ciphertext = None

    def due(self, limit: int = 100) -> list[UUID]:
        if not 1 <= limit <= 100:
            raise ValueError("Invalid deletion work limit")
        now = self.clock()
        with self.accounts.sessions() as db:
            rows = db.scalars(select(DeletionRecord.id).where(DeletionRecord.status == "pending",
                DeletionRecord.next_attempt_at <= now,
                (DeletionRecord.lease_until.is_(None) | (DeletionRecord.lease_until <= now)))
                .order_by(DeletionRecord.next_attempt_at).limit(limit))
            return [UUID(value) for value in rows]
