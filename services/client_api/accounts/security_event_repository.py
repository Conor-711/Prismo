"""Security-only subject barriers and idempotent, transactional provider revocation."""
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from .apple_repository import AppleGrantRecord
from .repository import (AccountRecord, AccountRepository, ChallengeRejected, ProviderSubjectRecord,
                         SecurityEventRecord, SessionFamilyRecord, SessionRecord)
from .security_event_models import VerifiedSecurityEvent, subject_key
from .session_renewal import SessionRenewalRepository


class SecurityEventRepository:
    def __init__(self, accounts: AccountRepository):
        self.accounts = accounts

    def lock_subject(self, db, provider, subject):
        key = subject_key(provider, subject)
        insert = pg_insert if self.accounts.engine.dialect.name == "postgresql" else sqlite_insert
        db.execute(insert(ProviderSubjectRecord).values(id=key, provider=provider, state="active")
                   .on_conflict_do_nothing(index_elements=["id"]))
        # Lock even on SQLite; every interactive login and affecting event uses this first.
        db.execute(update(ProviderSubjectRecord).where(ProviderSubjectRecord.id == key)
                   .values(provider=ProviderSubjectRecord.provider))
        return db.get(ProviderSubjectRecord, key, populate_existing=True)

    def check_issuance(self, db, identity):
        state = self.lock_subject(db, identity.provider, identity.subject)
        if state.deletion_pending or state.state != "active" or (state.revoked_before is not None and (
                identity.issued_at is None or self.utc(identity.issued_at) <= self.utc(state.revoked_before))):
            raise ChallengeRejected()

    def apply(self, event: VerifiedSecurityEvent):
        now = datetime.now(UTC)
        insert = pg_insert if self.accounts.engine.dialect.name == "postgresql" else sqlite_insert
        with self.accounts.sessions.begin() as db:
            state = self.lock_subject(db, event.provider, event.subject) if event.action != "ignore" else None
            inserted = db.execute(insert(SecurityEventRecord).values(id=event.receipt_id,
                fingerprint=event.fingerprint, provider=event.provider, kind=event.kind,
                received_at=now, verification_hash=event.verification_hash)
                .on_conflict_do_nothing(index_elements=["id"])).rowcount
            if inserted != 1:
                if db.get(SecurityEventRecord, event.receipt_id).fingerprint != event.fingerprint:
                    raise ChallengeRejected()
                return
            if state is not None:
                self._apply_state(db, state, event, now)
            self._prune(db, now)

    def _apply_state(self, db, state, event, now):
        when = event.occurred_at
        state_time = self.utc(state.state_changed_at) if state.state_changed_at else datetime.min.replace(tzinfo=UTC)
        if event.action == "enable":
            if event.provider == "google" and state.state != "deleted" and when > state_time:
                state.state, state.state_changed_at = "active", when
            return
        blocks = event.action in {"disable", "delete"}
        if blocks and (when >= state_time or event.action == "delete"):
            state.state = "deleted" if event.action == "delete" else "disabled"
            state.state_changed_at = max(when, state_time)
        barrier = self.utc(state.revoked_before) if state.revoked_before else datetime.min.replace(tzinfo=UTC)
        if when > barrier:
            state.revoked_before = when
        account = db.scalar(select(AccountRecord).where(AccountRecord.provider == event.provider,
            AccountRecord.subject == event.subject).with_for_update())
        if account is None:
            return
        # Disabled identities cannot retain even a more recently authenticated family.
        all_sessions = state.state != "active"
        affected = [SessionFamilyRecord.account_id == account.id]
        if not all_sessions:
            affected.append(or_(SessionFamilyRecord.authenticated_at.is_(None),
                                SessionFamilyRecord.authenticated_at <= when))
        families = select(SessionFamilyRecord.id).where(*affected)
        db.execute(update(SessionFamilyRecord).where(*affected, SessionFamilyRecord.revoked_at.is_(None))
                   .values(revoked_at=now).execution_options(synchronize_session=False))
        db.execute(delete(SessionRecord).where(SessionRecord.account_id == account.id,
            or_(SessionRecord.family_id.is_(None), SessionRecord.family_id.in_(families))))
        if event.provider == "apple":
            grants = [AppleGrantRecord.account_id == account.id]
            if not all_sessions:
                grants.append(or_(AppleGrantRecord.authenticated_at.is_(None), AppleGrantRecord.authenticated_at <= when))
            db.execute(delete(AppleGrantRecord).where(*grants))

    def prune_receipts(self, now: datetime | None = None):
        with self.accounts.sessions.begin() as db:
            return self._prune(db, now or datetime.now(UTC))

    @staticmethod
    def _prune(db, now):
        expired = select(SecurityEventRecord.id).where(SecurityEventRecord.received_at < now - timedelta(days=30))
        expired = expired.order_by(SecurityEventRecord.received_at).limit(1000)
        return db.execute(delete(SecurityEventRecord).where(SecurityEventRecord.id.in_(expired))).rowcount

    utc = staticmethod(SessionRenewalRepository.utc)
