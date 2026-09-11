"""Installation-bound rotating product sessions, independent of provider tokens."""
import re
import secrets
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import delete, select, update

from .models import AccountSession, TradingAccount
from .repository import (AccountRecord, AccountRepository, ChallengeRejected, ChallengeThrottled,
                         RefreshRecord, SessionFamilyRecord, SessionRecord)

ACCESS_LIFETIME = timedelta(minutes=30)
IDLE_LIFETIME = timedelta(hours=24)
FAMILY_LIFETIME = timedelta(days=7)
MIN_ROTATION_INTERVAL = timedelta(minutes=1)


class SessionRenewalRepository:
    def __init__(self, accounts: AccountRepository, clock=lambda: datetime.now(UTC)):
        self.accounts, self.clock = accounts, clock

    def start(self, db, account: AccountRecord, installation: UUID, now: datetime,
              authenticated_at: datetime | None = None) -> AccountSession:
        previous = select(SessionFamilyRecord.id).where(
            SessionFamilyRecord.account_id == account.id, SessionFamilyRecord.installation_id == str(installation))
        # Lock/revoke before deleting access rows: a concurrent rotation may have
        # minted a descendant while this transaction waited for the family lock.
        db.execute(update(SessionFamilyRecord).where(
            SessionFamilyRecord.account_id == account.id, SessionFamilyRecord.installation_id == str(installation),
            SessionFamilyRecord.revoked_at.is_(None)).values(revoked_at=now))
        db.execute(delete(SessionRecord).where(SessionRecord.family_id.in_(previous)))
        family = SessionFamilyRecord(id=str(uuid4()), account_id=account.id, installation_id=str(installation),
            expires_at=now + FAMILY_LIFETIME, rotated_at=now, revoked_at=None, authenticated_at=authenticated_at)
        db.add(family)
        db.flush()
        return self._pair(db, family, account, now)

    def rotate(self, token: str, installation: UUID) -> AccountSession:
        if not self.valid_token(token):
            raise ChallengeRejected()
        result = None
        with self.accounts.sessions.begin() as db:
            family = self._family_for_refresh(db, token, installation)
            now = self.clock()
            if family is not None and family.revoked_at is None and self.utc(family.expires_at) > now:
                credential = db.get(RefreshRecord, self.accounts.digest(token))
                if credential.consumed_at is not None:
                    # Do not raise inside this transaction: replay revocation must commit.
                    self._revoke(db, family.id, now)
                elif self.utc(credential.expires_at) > now:
                    if now - self.utc(family.rotated_at) < MIN_ROTATION_INTERVAL:
                        raise ChallengeThrottled()
                    consumed = db.execute(update(RefreshRecord).where(
                        RefreshRecord.token_hash == credential.token_hash,
                        RefreshRecord.consumed_at.is_(None), RefreshRecord.expires_at > now
                    ).values(consumed_at=now).execution_options(synchronize_session=False)).rowcount
                    if consumed != 1:
                        self._revoke(db, family.id, now)
                    else:
                        db.execute(delete(SessionRecord).where(SessionRecord.family_id == family.id))
                        family.rotated_at = now
                        account = db.get(AccountRecord, family.account_id)
                        if account is None:
                            raise ChallengeRejected()
                        result = self._pair(db, family, account, now)
        if result is None:
            raise ChallengeRejected()
        return result

    def revoke_refresh(self, token: str, installation: UUID) -> None:
        if not self.valid_token(token):
            return
        with self.accounts.sessions.begin() as db:
            family = self._family_for_refresh(db, token, installation)
            if family is not None:
                self._revoke(db, family.id, self.clock())

    def revoke_access(self, token: str) -> None:
        with self.accounts.sessions.begin() as db:
            record = db.get(SessionRecord, self.accounts.digest(token))
            if record is None:
                return
            if record.family_id is None:
                db.delete(record)
            else:
                self._lock(db, record.family_id)
                self._revoke(db, record.family_id, self.clock())

    def _family_for_refresh(self, db, token: str, installation: UUID):
        identifier = db.scalar(select(SessionFamilyRecord.id).join(RefreshRecord).where(
            RefreshRecord.token_hash == self.accounts.digest(token),
            SessionFamilyRecord.installation_id == str(installation)))
        if identifier is None:
            return None
        self._lock(db, identifier)
        return db.get(SessionFamilyRecord, identifier, populate_existing=True)

    @staticmethod
    def _lock(db, identifier: str):
        # A no-op write also serializes SQLite; SELECT FOR UPDATE alone does not.
        db.execute(update(SessionFamilyRecord).where(SessionFamilyRecord.id == identifier)
            .values(rotated_at=SessionFamilyRecord.rotated_at))

    @staticmethod
    def _revoke(db, identifier: str, now: datetime):
        db.execute(update(SessionFamilyRecord).where(
            SessionFamilyRecord.id == identifier, SessionFamilyRecord.revoked_at.is_(None)
        ).values(revoked_at=now))
        db.execute(delete(SessionRecord).where(SessionRecord.family_id == identifier))

    def _pair(self, db, family, account, now: datetime) -> AccountSession:
        access, refresh = "bsa_" + secrets.token_urlsafe(48), "bsr_" + secrets.token_urlsafe(48)
        access_expiry = min(now + ACCESS_LIFETIME, self.utc(family.expires_at))
        refresh_expiry = min(now + IDLE_LIFETIME, self.utc(family.expires_at))
        db.add(SessionRecord(token_hash=self.accounts.digest(access), account_id=account.id,
                             family_id=family.id, expires_at=access_expiry))
        db.add(RefreshRecord(token_hash=self.accounts.digest(refresh), family_id=family.id,
                             expires_at=refresh_expiry, consumed_at=None))
        return AccountSession(account=TradingAccount(id=account.id, provider=account.provider),
            accessToken=access, expiresAt=access_expiry, refreshToken=refresh, refreshExpiresAt=refresh_expiry)

    @staticmethod
    def valid_token(token: str) -> bool:
        return isinstance(token, str) and bool(re.fullmatch(r"[A-Za-z0-9_-]{32,256}", token))

    @staticmethod
    def utc(value: datetime) -> datetime:
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
