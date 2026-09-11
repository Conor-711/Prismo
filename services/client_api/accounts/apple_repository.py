"""Durable one-use Apple exchange claims and encrypted provider grants."""
import secrets
from dataclasses import dataclass, field
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, LargeBinary, String, delete
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Mapped, mapped_column

from .credential_cipher import CredentialCipher
from .oidc import VerifiedIdentity
from .repository import AccountBase, AccountRepository, ChallengeRecord, ChallengeRejected


class AppleExchangeRecord(AccountBase):
    __tablename__ = "trading_apple_exchange"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64))
    subject: Mapped[str] = mapped_column(String(255))
    client_id: Mapped[str] = mapped_column(String(255))
    installation_id: Mapped[str] = mapped_column(String(36))
    identity_issued_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class AppleGrantRecord(AccountBase):
    __tablename__ = "trading_apple_grant"
    account_id: Mapped[str] = mapped_column(String(36), ForeignKey("trading_account.id"), primary_key=True)
    client_id: Mapped[str] = mapped_column(String(255))
    key_id: Mapped[str] = mapped_column(String(32))
    ciphertext: Mapped[bytes] = mapped_column(LargeBinary)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    authenticated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


@dataclass(frozen=True)
class AppleExchangeClaim:
    id: UUID
    identity: VerifiedIdentity
    client_id: str
    installation_id: UUID
    token: str = field(repr=False)


class AppleGrantRepository:
    def __init__(self, accounts: AccountRepository):
        self.accounts = accounts

    def claim(self, identifier: UUID, installation: UUID, identity: VerifiedIdentity, client_id: str) -> AppleExchangeClaim:
        if identity.provider != "apple":
            raise ChallengeRejected()
        token = secrets.token_urlsafe(48)
        with self.accounts.sessions.begin() as db:
            expires = db.execute(delete(ChallengeRecord).where(
                *self.accounts.challenge_conditions(identifier, installation, "apple")
            ).returning(ChallengeRecord.expires_at)).scalar_one_or_none()
            if expires is None:
                raise ChallengeRejected()
            db.execute(delete(AppleExchangeRecord).where(AppleExchangeRecord.expires_at <= datetime.now(UTC)))
            db.add(AppleExchangeRecord(id=str(identifier), token_hash=self.accounts.digest(token),
                                      subject=identity.subject, client_id=client_id,
                                      installation_id=str(installation), identity_issued_at=identity.issued_at, expires_at=expires))
        return AppleExchangeClaim(identifier, identity, client_id, installation, token)

    def finish(self, claim: AppleExchangeClaim, refresh_token: str, cipher: CredentialCipher,
               expected_account_id: UUID | None = None):
        with self.accounts.sessions.begin() as db:
            if claim.identity.provider != "apple":
                raise ChallengeRejected()
            consumed = db.execute(delete(AppleExchangeRecord).where(
                AppleExchangeRecord.id == str(claim.id), AppleExchangeRecord.token_hash == self.accounts.digest(claim.token),
                AppleExchangeRecord.subject == claim.identity.subject, AppleExchangeRecord.client_id == claim.client_id,
                AppleExchangeRecord.installation_id == str(claim.installation_id),
                AppleExchangeRecord.identity_issued_at == claim.identity.issued_at,
                AppleExchangeRecord.expires_at > datetime.now(UTC))).rowcount
            if consumed != 1:
                raise ChallengeRejected()
            session = self.accounts.issue_in_transaction(db, claim.identity, claim.installation_id, expected_account_id)
            key_id, ciphertext = cipher.seal(refresh_token, str(session.account.id), claim.identity.subject, claim.client_id)
            now = datetime.now(UTC)
            insert = pg_insert if self.accounts.engine.dialect.name == "postgresql" else sqlite_insert
            values = dict(client_id=claim.client_id, key_id=key_id, ciphertext=ciphertext,
                          updated_at=now, authenticated_at=claim.identity.issued_at)
            db.execute(insert(AppleGrantRecord).values(account_id=str(session.account.id), **values)
                       .on_conflict_do_update(index_elements=["account_id"], set_=values))
        return session
