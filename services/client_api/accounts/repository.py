import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, String, UniqueConstraint, create_engine, delete, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from .models import AccountSession, AuthChallenge, TradingAccount
from .oidc import VerifiedIdentity


class AccountBase(DeclarativeBase):
    pass


class AccountRecord(AccountBase):
    __tablename__ = "trading_account"
    __table_args__ = (UniqueConstraint("provider", "subject"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    provider: Mapped[str] = mapped_column(String(16))
    subject: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class ChallengeRecord(AccountBase):
    __tablename__ = "trading_auth_challenge"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    installation_id: Mapped[str] = mapped_column(String(36), index=True)
    provider: Mapped[str] = mapped_column(String(16))
    nonce_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class SessionRecord(AccountBase):
    __tablename__ = "trading_account_session"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    account_id: Mapped[str] = mapped_column(String(36), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    family_id: Mapped[str | None] = mapped_column(ForeignKey("trading_session_family.id"), nullable=True, index=True)


class SessionFamilyRecord(AccountBase):
    __tablename__ = "trading_session_family"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("trading_account.id"), index=True)
    installation_id: Mapped[str] = mapped_column(String(36), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    rotated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    authenticated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class RefreshRecord(AccountBase):
    __tablename__ = "trading_session_refresh"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    family_id: Mapped[str] = mapped_column(ForeignKey("trading_session_family.id"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ProviderSubjectRecord(AccountBase):
    __tablename__ = "trading_provider_subject"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    provider: Mapped[str] = mapped_column(String(16))
    state: Mapped[str] = mapped_column(String(16))
    state_changed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_before: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deletion_pending: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")


class SecurityEventRecord(AccountBase):
    __tablename__ = "trading_security_event"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    fingerprint: Mapped[str] = mapped_column(String(64))
    provider: Mapped[str] = mapped_column(String(16))
    kind: Mapped[str] = mapped_column(String(200))
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    verification_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)


class ChallengeRejected(Exception):
    pass


class ChallengeThrottled(Exception):
    pass


class AccountRepository:
    def __init__(self, database_url: str):
        self.engine = create_engine(database_url, pool_pre_ping=True)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)
        # Deliberately no create_all/migration at runtime.

    def challenge(self, installation_id: UUID, provider: str) -> AuthChallenge:
        now = datetime.now(UTC)
        nonce, identifier, expires = secrets.token_urlsafe(32), uuid4(), now + timedelta(minutes=5)
        with self.sessions.begin() as db:
            db.execute(delete(ChallengeRecord).where(ChallengeRecord.expires_at <= now))
            count = db.scalar(select(func.count()).select_from(ChallengeRecord).where(
                ChallengeRecord.installation_id == str(installation_id)))
            if count >= 5:
                raise ChallengeThrottled()
            db.add(ChallengeRecord(id=str(identifier), installation_id=str(installation_id),
                                   provider=provider, nonce_hash=self.digest(nonce), expires_at=expires))
        return AuthChallenge(id=identifier, nonce=nonce, expiresAt=expires)

    def nonce_hash(self, identifier: UUID, installation_id: UUID, provider: str) -> str:
        with self.sessions() as db:
            value = db.scalar(select(ChallengeRecord.nonce_hash).where(
                *self.challenge_conditions(identifier, installation_id, provider)))
            if value is None:
                raise ChallengeRejected()
            return value

    def issue(self, identifier: UUID, installation_id: UUID, identity: VerifiedIdentity,
              expected_account_id: UUID | None = None) -> AccountSession:
        with self.sessions.begin() as db:
            consumed = db.execute(delete(ChallengeRecord).where(
                *self.challenge_conditions(identifier, installation_id, identity.provider)
            )).rowcount
            if consumed != 1:
                raise ChallengeRejected()
            return self.issue_in_transaction(db, identity, installation_id, expected_account_id)

    def issue_in_transaction(self, db, identity: VerifiedIdentity, installation_id: UUID,
                             expected_account_id: UUID | None = None) -> AccountSession:
        from .session_renewal import SessionRenewalRepository
        from .security_event_repository import SecurityEventRepository
        SecurityEventRepository(self).check_issuance(db, identity)
        now, account_id = datetime.now(UTC), str(uuid4())
        insert = pg_insert if self.engine.dialect.name == "postgresql" else sqlite_insert
        if expected_account_id is None:
            db.execute(insert(AccountRecord).values(
                id=account_id, provider=identity.provider, subject=identity.subject, created_at=now
            ).on_conflict_do_nothing(index_elements=["provider", "subject"]))
        record = db.scalar(select(AccountRecord).where(
            AccountRecord.provider == identity.provider, AccountRecord.subject == identity.subject).with_for_update())
        if record is None or (expected_account_id is not None and record.id != str(expected_account_id)):
            raise ChallengeRejected()
        db.execute(delete(SessionRecord).where(SessionRecord.expires_at <= now))
        return SessionRenewalRepository(self).start(db, record, installation_id, now, identity.issued_at)

    def authenticate(self, token: str) -> TradingAccount | None:
        if not 32 <= len(token) <= 256:
            return None
        with self.sessions() as db:
            record = db.scalar(select(AccountRecord).join(
                SessionRecord, SessionRecord.account_id == AccountRecord.id
            ).where(SessionRecord.token_hash == self.digest(token),
                    SessionRecord.expires_at > datetime.now(UTC)))
            return TradingAccount(id=record.id, provider=record.provider) if record else None

    def revoke(self, token: str) -> None:
        from .session_renewal import SessionRenewalRepository
        SessionRenewalRepository(self).revoke_access(token)

    @staticmethod
    def require_personal_data_write(db, account_id: UUID):
        from .security_event_models import subject_key
        # Order writers against deletion; a late profile/fill must not recreate erased data.
        found = db.execute(update(AccountRecord).where(AccountRecord.id == str(account_id))
            .values(created_at=AccountRecord.created_at)).rowcount
        if found != 1:
            raise ValueError("Account data is unavailable")
        account = db.get(AccountRecord, str(account_id), populate_existing=True)
        state = db.get(ProviderSubjectRecord, subject_key(account.provider, account.subject), populate_existing=True)
        if state is None or state.deletion_pending:
            raise ValueError("Account data is unavailable")

    @staticmethod
    def digest(token: str) -> str:
        return hashlib.sha256(token.encode()).hexdigest()

    @staticmethod
    def challenge_conditions(identifier: UUID, installation_id: UUID, provider: str):
        return (ChallengeRecord.id == str(identifier),
                ChallengeRecord.installation_id == str(installation_id),
                ChallengeRecord.provider == provider,
                ChallengeRecord.expires_at > datetime.now(UTC))
