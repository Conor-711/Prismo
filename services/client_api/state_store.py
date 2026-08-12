from __future__ import annotations

import hashlib
import json
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

from sqlalchemy import Boolean, DateTime, Float, Integer, String, Text, create_engine, delete, func, or_, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from services.client_api.schemas import (
    DeviceRegistrationInput,
    InstallationRegistration,
    ClientTelemetryBatch,
    NotificationPreferences,
    PortfolioEntryInput,
    SignalUserStateInput,
)


class Base(DeclarativeBase):
    pass


class InstallationRecord(Base):
    __tablename__ = "client_installation"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    platform: Mapped[str] = mapped_column(String(16))
    app_version: Mapped[str] = mapped_column(String(32))
    locale: Mapped[str] = mapped_column(String(64))
    time_zone: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class PortfolioRecord(Base):
    __tablename__ = "client_portfolio_entry"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    entry_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    company_name: Mapped[str] = mapped_column(String(160))
    entry_kind: Mapped[str] = mapped_column(String(16))
    shares: Mapped[float | None] = mapped_column(Float, nullable=True)
    average_cost: Mapped[float | None] = mapped_column(Float, nullable=True)
    portfolio_weight: Mapped[float | None] = mapped_column(Float, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SignalStateRecord(Base):
    __tablename__ = "client_signal_state"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    signal_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    is_read: Mapped[bool] = mapped_column(Boolean)
    is_saved: Mapped[bool] = mapped_column(Boolean)
    is_ignored: Mapped[bool] = mapped_column(Boolean)
    feedback: Mapped[str | None] = mapped_column(String(32), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class NotificationPreferencesRecord(Base):
    __tablename__ = "client_notification_preferences"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    instant_alerts_enabled: Mapped[bool] = mapped_column(Boolean)
    daily_digest_enabled: Mapped[bool] = mapped_column(Boolean)
    daily_digest_minutes: Mapped[int]
    quiet_hours_enabled: Mapped[bool] = mapped_column(Boolean)
    quiet_hours_start_minutes: Mapped[int]
    quiet_hours_end_minutes: Mapped[int]
    muted_tickers_json: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class DeviceRecord(Base):
    __tablename__ = "client_device"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    apns_token: Mapped[str] = mapped_column(String(256), unique=True, index=True)
    environment: Mapped[str] = mapped_column(String(16))
    app_version: Mapped[str] = mapped_column(String(32))
    locale: Mapped[str] = mapped_column(String(64))
    time_zone: Mapped[str] = mapped_column(String(128))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class NotificationDeliveryRecord(Base):
    __tablename__ = "client_notification_delivery"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    signal_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    title: Mapped[str] = mapped_column(String(240))
    body: Mapped[str] = mapped_column(Text)
    deep_link: Mapped[str] = mapped_column(String(320))
    status: Mapped[str] = mapped_column(String(24), index=True)
    reason: Mapped[str | None] = mapped_column(String(64), nullable=True)
    scheduled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class DailyDigestRecord(Base):
    __tablename__ = "client_daily_digest"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    digest_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    local_date: Mapped[str] = mapped_column(String(10), index=True)
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    period_start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    period_end: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    data_as_of: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    title: Mapped[str] = mapped_column(String(240))
    summary: Mapped[str] = mapped_column(Text)
    signals_json: Mapped[str] = mapped_column(Text)


class NotificationAttemptRecord(Base):
    __tablename__ = "client_notification_attempt"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    installation_id: Mapped[str] = mapped_column(String(36), index=True)
    signal_id: Mapped[str] = mapped_column(String(36), index=True)
    outcome: Mapped[str] = mapped_column(String(24))
    status_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reason: Mapped[str | None] = mapped_column(String(96), nullable=True)
    attempted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class ClientTelemetryRecord(Base):
    __tablename__ = "client_telemetry_event"

    installation_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    event_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(40), index=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    signal_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    ticker: Mapped[str | None] = mapped_column(String(16), nullable=True, index=True)
    evidence_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    source: Mapped[str | None] = mapped_column(String(24), nullable=True)
    context: Mapped[str] = mapped_column(String(24))


@dataclass(frozen=True)
class AuthenticatedInstallation:
    installation_id: UUID


@dataclass(frozen=True)
class NotificationTarget:
    installation_id: UUID
    apns_token: str
    environment: str
    locale: str
    time_zone: str
    preferences: NotificationPreferences


@dataclass(frozen=True)
class NotificationDelivery:
    installation_id: UUID
    signal_id: UUID
    ticker: str
    status: str
    reason: str | None
    scheduled_at: datetime
    title: str = ""
    body: str = ""
    deep_link: str = ""


@dataclass(frozen=True)
class ClaimedNotification:
    installation_id: UUID
    signal_id: UUID
    ticker: str
    title: str
    body: str
    deep_link: str
    apns_token: str
    environment: str


@dataclass(frozen=True)
class DailyDigestTarget:
    installation_id: UUID
    apns_token: str
    environment: str
    locale: str
    time_zone: str
    preferences: NotificationPreferences
    tickers: frozenset[str]


@dataclass(frozen=True)
class DailyDigestSnapshotRecord:
    installation_id: UUID
    digest_id: UUID
    local_date: str
    generated_at: datetime
    period_start: datetime
    period_end: datetime
    data_as_of: datetime
    title: str
    summary: str
    signals: list[dict]


@dataclass(frozen=True)
class NotificationAttempt:
    installation_id: UUID
    signal_id: UUID
    outcome: str
    status_code: int | None
    reason: str | None


@dataclass(frozen=True)
class ClientTelemetry:
    installation_id: UUID
    event_id: UUID
    name: str
    signal_id: UUID | None
    ticker: str | None
    evidence_id: UUID | None
    source: str | None
    context: str


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


class ClientStateStore:
    def __init__(
        self,
        database_url: str,
        session_lifetime_days: int = 90,
        telemetry_retention_days: int = 90,
    ):
        if database_url.startswith("sqlite:///"):
            database_path = Path(database_url.removeprefix("sqlite:///"))
            database_path.parent.mkdir(parents=True, exist_ok=True)
        connect_args = {"check_same_thread": False} if database_url.startswith("sqlite") else {}
        self.engine = create_engine(
            database_url,
            pool_pre_ping=True,
            connect_args=connect_args,
        )
        self.session_factory = sessionmaker(self.engine, expire_on_commit=False)
        self.session_lifetime = timedelta(days=session_lifetime_days)
        self.telemetry_retention = timedelta(days=telemetry_retention_days)
        Base.metadata.create_all(self.engine)

    def register_installation(
        self,
        registration: InstallationRegistration,
    ) -> tuple[str, datetime]:
        now = _utc_now()
        expires_at = now + self.session_lifetime
        token = secrets.token_urlsafe(32)
        installation_id = str(registration.installation_id)
        with self.session_factory.begin() as session:
            record = session.get(InstallationRecord, installation_id)
            if record is None:
                record = InstallationRecord(
                    installation_id=installation_id,
                    created_at=now,
                    token_hash="",
                    platform=registration.platform,
                    app_version=registration.app_version,
                    locale=registration.locale,
                    time_zone=registration.time_zone,
                    last_seen_at=now,
                    expires_at=expires_at,
                )
                session.add(record)
            record.token_hash = _token_hash(token)
            record.platform = registration.platform
            record.app_version = registration.app_version
            record.locale = registration.locale
            record.time_zone = registration.time_zone
            record.last_seen_at = now
            record.expires_at = expires_at
        return token, expires_at

    def authenticate(self, token: str) -> AuthenticatedInstallation | None:
        if not token:
            return None
        now = _utc_now()
        with self.session_factory.begin() as session:
            record = session.scalar(
                select(InstallationRecord).where(InstallationRecord.token_hash == _token_hash(token))
            )
            if record is None or _as_utc(record.expires_at) <= now:
                return None
            record.last_seen_at = now
            return AuthenticatedInstallation(UUID(record.installation_id))

    def list_portfolio(self, installation_id: UUID) -> list[PortfolioRecord]:
        with self.session_factory() as session:
            return list(
                session.scalars(
                    select(PortfolioRecord)
                    .where(PortfolioRecord.installation_id == str(installation_id))
                    .order_by(PortfolioRecord.ticker)
                )
            )

    def upsert_portfolio(
        self,
        installation_id: UUID,
        entry_id: UUID,
        payload: PortfolioEntryInput,
    ) -> PortfolioRecord:
        now = _utc_now()
        key = {"installation_id": str(installation_id), "entry_id": str(entry_id)}
        with self.session_factory.begin() as session:
            record = session.get(PortfolioRecord, (key["installation_id"], key["entry_id"]))
            if record is None:
                record = PortfolioRecord(**key, ticker=payload.ticker, company_name="", entry_kind="watchlist", updated_at=now)
                session.add(record)
            record.ticker = payload.ticker
            record.company_name = payload.company_name or payload.ticker
            record.entry_kind = payload.entry_kind
            record.shares = payload.shares if payload.entry_kind == "position" else None
            record.average_cost = payload.average_cost if payload.entry_kind == "position" else None
            record.portfolio_weight = payload.portfolio_weight if payload.entry_kind == "position" else None
            record.updated_at = now
        return record

    def delete_portfolio(self, installation_id: UUID, entry_id: UUID) -> None:
        with self.session_factory.begin() as session:
            session.execute(
                delete(PortfolioRecord).where(
                    PortfolioRecord.installation_id == str(installation_id),
                    PortfolioRecord.entry_id == str(entry_id),
                )
            )

    def put_signal_state(
        self,
        installation_id: UUID,
        signal_id: UUID,
        payload: SignalUserStateInput,
    ) -> SignalStateRecord:
        now = _utc_now()
        key = (str(installation_id), str(signal_id))
        with self.session_factory.begin() as session:
            record = session.get(SignalStateRecord, key)
            if record is None:
                record = SignalStateRecord(
                    installation_id=key[0],
                    signal_id=key[1],
                    is_read=False,
                    is_saved=False,
                    is_ignored=False,
                    updated_at=now,
                )
                session.add(record)
            record.is_read = payload.is_read
            record.is_saved = payload.is_saved
            record.is_ignored = payload.is_ignored
            record.feedback = payload.feedback
            record.updated_at = now
        return record

    def get_notification_preferences(self, installation_id: UUID) -> NotificationPreferences:
        with self.session_factory() as session:
            record = session.get(NotificationPreferencesRecord, str(installation_id))
            if record is None:
                return NotificationPreferences.defaults()
            return NotificationPreferences(
                instantAlertsEnabled=record.instant_alerts_enabled,
                dailyDigestEnabled=record.daily_digest_enabled,
                dailyDigestMinutes=record.daily_digest_minutes,
                quietHoursEnabled=record.quiet_hours_enabled,
                quietHoursStartMinutes=record.quiet_hours_start_minutes,
                quietHoursEndMinutes=record.quiet_hours_end_minutes,
                mutedTickers=json.loads(record.muted_tickers_json),
            )

    def put_notification_preferences(
        self,
        installation_id: UUID,
        payload: NotificationPreferences,
    ) -> NotificationPreferences:
        now = _utc_now()
        with self.session_factory.begin() as session:
            record = session.get(NotificationPreferencesRecord, str(installation_id))
            if record is None:
                record = NotificationPreferencesRecord(
                    installation_id=str(installation_id),
                    instant_alerts_enabled=True,
                    daily_digest_enabled=True,
                    daily_digest_minutes=8 * 60,
                    quiet_hours_enabled=True,
                    quiet_hours_start_minutes=22 * 60,
                    quiet_hours_end_minutes=7 * 60,
                    muted_tickers_json="[]",
                    updated_at=now,
                )
                session.add(record)
            record.instant_alerts_enabled = payload.instant_alerts_enabled
            record.daily_digest_enabled = payload.daily_digest_enabled
            record.daily_digest_minutes = payload.daily_digest_minutes
            record.quiet_hours_enabled = payload.quiet_hours_enabled
            record.quiet_hours_start_minutes = payload.quiet_hours_start_minutes
            record.quiet_hours_end_minutes = payload.quiet_hours_end_minutes
            record.muted_tickers_json = json.dumps(payload.muted_tickers)
            record.updated_at = now
        return payload

    def put_device(self, installation_id: UUID, payload: DeviceRegistrationInput) -> None:
        now = _utc_now()
        with self.session_factory.begin() as session:
            record = session.get(DeviceRecord, str(installation_id))
            if record is None:
                record = DeviceRecord(
                    installation_id=str(installation_id),
                    apns_token=payload.apns_token,
                    environment=payload.environment,
                    app_version=payload.app_version,
                    locale=payload.locale,
                    time_zone=payload.time_zone,
                    updated_at=now,
                )
                session.add(record)
            record.apns_token = payload.apns_token
            record.environment = payload.environment
            record.app_version = payload.app_version
            record.locale = payload.locale
            record.time_zone = payload.time_zone
            record.updated_at = now

    def notification_targets(self, ticker: str) -> list[NotificationTarget]:
        normalized = ticker.upper()
        with self.session_factory() as session:
            rows = session.execute(
                select(DeviceRecord, NotificationPreferencesRecord)
                .join(
                    PortfolioRecord,
                    PortfolioRecord.installation_id == DeviceRecord.installation_id,
                )
                .outerjoin(
                    NotificationPreferencesRecord,
                    NotificationPreferencesRecord.installation_id == DeviceRecord.installation_id,
                )
                .where(PortfolioRecord.ticker == normalized)
            )
            targets: dict[str, NotificationTarget] = {}
            for device, preferences in rows:
                targets[device.installation_id] = NotificationTarget(
                    installation_id=UUID(device.installation_id),
                    apns_token=device.apns_token,
                    environment=device.environment,
                    locale=device.locale,
                    time_zone=device.time_zone,
                    preferences=_notification_preferences(preferences),
                )
            return list(targets.values())

    def enqueue_notification(
        self,
        *,
        installation_id: UUID,
        signal_id: UUID,
        ticker: str,
        title: str,
        body: str,
        deep_link: str,
        status_value: str,
        reason: str | None,
        scheduled_at: datetime,
    ) -> bool:
        now = _utc_now()
        key = (str(installation_id), str(signal_id))
        with self.session_factory.begin() as session:
            if session.get(NotificationDeliveryRecord, key) is not None:
                return False
            session.add(NotificationDeliveryRecord(
                installation_id=key[0],
                signal_id=key[1],
                ticker=ticker.upper(),
                title=title,
                body=body,
                deep_link=deep_link,
                status=status_value,
                reason=reason,
                scheduled_at=scheduled_at,
                created_at=now,
                updated_at=now,
            ))
        return True

    def has_active_notification_since(
        self,
        installation_id: UUID,
        *,
        since: datetime,
        ticker: str | None = None,
    ) -> bool:
        with self.session_factory() as session:
            conditions = [
                NotificationDeliveryRecord.installation_id == str(installation_id),
                NotificationDeliveryRecord.status.in_(("pending", "sending", "sent")),
                NotificationDeliveryRecord.scheduled_at >= since.astimezone(UTC),
            ]
            if ticker is not None:
                conditions.append(NotificationDeliveryRecord.ticker == ticker.upper())
            return session.scalar(
                select(NotificationDeliveryRecord.installation_id).where(*conditions).limit(1)
            ) is not None

    def active_notification_count_since(
        self,
        installation_id: UUID,
        *,
        since: datetime,
    ) -> int:
        with self.session_factory() as session:
            return int(session.scalar(
                select(func.count()).select_from(NotificationDeliveryRecord).where(
                    NotificationDeliveryRecord.installation_id == str(installation_id),
                    NotificationDeliveryRecord.status.in_(("pending", "sending", "sent")),
                    NotificationDeliveryRecord.scheduled_at >= since.astimezone(UTC),
                )
            ) or 0)

    def notification_deliveries(self) -> list[NotificationDelivery]:
        with self.session_factory() as session:
            records = session.scalars(
                select(NotificationDeliveryRecord).order_by(NotificationDeliveryRecord.created_at)
            )
            return [NotificationDelivery(
                installation_id=UUID(record.installation_id),
                signal_id=UUID(record.signal_id),
                ticker=record.ticker,
                status=record.status,
                reason=record.reason,
                scheduled_at=_as_utc(record.scheduled_at),
                title=record.title,
                body=record.body,
                deep_link=record.deep_link,
            ) for record in records]

    def daily_digest_targets(self) -> list[DailyDigestTarget]:
        with self.session_factory() as session:
            rows = session.execute(
                select(DeviceRecord, NotificationPreferencesRecord, PortfolioRecord.ticker)
                .join(
                    PortfolioRecord,
                    PortfolioRecord.installation_id == DeviceRecord.installation_id,
                )
                .outerjoin(
                    NotificationPreferencesRecord,
                    NotificationPreferencesRecord.installation_id == DeviceRecord.installation_id,
                )
                .order_by(DeviceRecord.installation_id)
            )
            grouped: dict[str, tuple[DeviceRecord, NotificationPreferencesRecord | None, set[str]]] = {}
            for device, preferences, ticker in rows:
                if device.installation_id not in grouped:
                    grouped[device.installation_id] = (device, preferences, set())
                grouped[device.installation_id][2].add(ticker.upper())
            return [DailyDigestTarget(
                installation_id=UUID(device.installation_id),
                apns_token=device.apns_token,
                environment=device.environment,
                locale=device.locale,
                time_zone=device.time_zone,
                preferences=_notification_preferences(preferences),
                tickers=frozenset(tickers),
            ) for device, preferences, tickers in grouped.values()]

    def put_daily_digest(
        self,
        *,
        installation_id: UUID,
        digest_id: UUID,
        local_date: str,
        generated_at: datetime,
        period_start: datetime,
        period_end: datetime,
        data_as_of: datetime,
        title: str,
        summary: str,
        signals: list[dict],
    ) -> DailyDigestSnapshotRecord:
        key = (str(installation_id), str(digest_id))
        with self.session_factory.begin() as session:
            record = session.get(DailyDigestRecord, key)
            if record is None:
                record = DailyDigestRecord(
                    installation_id=key[0],
                    digest_id=key[1],
                    local_date=local_date,
                    generated_at=generated_at.astimezone(UTC),
                    period_start=period_start.astimezone(UTC),
                    period_end=period_end.astimezone(UTC),
                    data_as_of=data_as_of.astimezone(UTC),
                    title=title,
                    summary=summary,
                    signals_json=json.dumps(signals, ensure_ascii=False, separators=(",", ":")),
                )
                session.add(record)
                session.flush()
            return _daily_digest_snapshot(record)

    def latest_daily_digest(
        self,
        installation_id: UUID,
    ) -> DailyDigestSnapshotRecord | None:
        with self.session_factory() as session:
            record = session.scalar(
                select(DailyDigestRecord)
                .where(DailyDigestRecord.installation_id == str(installation_id))
                .order_by(DailyDigestRecord.generated_at.desc())
                .limit(1)
            )
            return _daily_digest_snapshot(record) if record is not None else None

    def claim_due_notifications(
        self,
        *,
        now: datetime,
        limit: int = 100,
        lease_timeout: timedelta = timedelta(minutes=5),
    ) -> list[ClaimedNotification]:
        current_time = now.astimezone(UTC)
        stale_before = current_time - lease_timeout
        claimed: list[ClaimedNotification] = []
        with self.session_factory.begin() as session:
            records = session.scalars(
                select(NotificationDeliveryRecord)
                .where(
                    or_(
                        (
                            (NotificationDeliveryRecord.status == "pending")
                            & (NotificationDeliveryRecord.scheduled_at <= current_time)
                        ),
                        (
                            (NotificationDeliveryRecord.status == "sending")
                            & (NotificationDeliveryRecord.updated_at <= stale_before)
                        ),
                    )
                )
                .order_by(NotificationDeliveryRecord.scheduled_at)
                .limit(limit)
                .with_for_update(skip_locked=True)
            )
            for record in records:
                device = session.get(DeviceRecord, record.installation_id)
                if device is None:
                    record.status = "failed"
                    record.reason = "device_missing"
                    record.updated_at = current_time
                    continue
                record.status = "sending"
                record.updated_at = current_time
                claimed.append(ClaimedNotification(
                    installation_id=UUID(record.installation_id),
                    signal_id=UUID(record.signal_id),
                    ticker=record.ticker,
                    title=record.title,
                    body=record.body,
                    deep_link=record.deep_link,
                    apns_token=device.apns_token,
                    environment=device.environment,
                ))
        return claimed

    def finish_notification_attempt(
        self,
        delivery: ClaimedNotification,
        *,
        outcome: str,
        status_code: int | None,
        reason: str | None,
        retry_at: datetime | None = None,
        invalidate_device: bool = False,
    ) -> None:
        now = _utc_now()
        key = (str(delivery.installation_id), str(delivery.signal_id))
        with self.session_factory.begin() as session:
            record = session.get(NotificationDeliveryRecord, key)
            if record is None:
                return
            if outcome == "sent":
                record.status = "sent"
                record.reason = None
            elif retry_at is not None:
                record.status = "pending"
                record.reason = reason
                record.scheduled_at = retry_at.astimezone(UTC)
            else:
                record.status = "failed"
                record.reason = reason
            record.updated_at = now
            session.add(NotificationAttemptRecord(
                installation_id=key[0],
                signal_id=key[1],
                outcome=outcome,
                status_code=status_code,
                reason=reason,
                attempted_at=now,
            ))
            if invalidate_device:
                session.execute(
                    delete(DeviceRecord).where(DeviceRecord.installation_id == key[0])
                )

    def notification_attempts(self) -> list[NotificationAttempt]:
        with self.session_factory() as session:
            records = session.scalars(
                select(NotificationAttemptRecord).order_by(NotificationAttemptRecord.id)
            )
            return [NotificationAttempt(
                installation_id=UUID(record.installation_id),
                signal_id=UUID(record.signal_id),
                outcome=record.outcome,
                status_code=record.status_code,
                reason=record.reason,
            ) for record in records]

    def record_telemetry(self, installation_id: UUID, batch: ClientTelemetryBatch) -> int:
        now = _utc_now()
        inserted = 0
        with self.session_factory.begin() as session:
            session.execute(
                delete(ClientTelemetryRecord).where(
                    ClientTelemetryRecord.received_at < now - self.telemetry_retention
                )
            )
            for event in batch.events:
                key = (str(installation_id), str(event.id))
                if session.get(ClientTelemetryRecord, key) is not None:
                    continue
                session.add(ClientTelemetryRecord(
                    installation_id=key[0],
                    event_id=key[1],
                    name=event.name,
                    occurred_at=event.occurred_at.astimezone(UTC),
                    received_at=now,
                    signal_id=str(event.signal_id) if event.signal_id else None,
                    ticker=event.ticker,
                    evidence_id=str(event.evidence_id) if event.evidence_id else None,
                    source=event.source,
                    context=event.context,
                ))
                inserted += 1
        return inserted

    def telemetry_events(self, installation_id: UUID | None = None) -> list[ClientTelemetry]:
        with self.session_factory() as session:
            query = select(ClientTelemetryRecord).order_by(ClientTelemetryRecord.received_at)
            if installation_id is not None:
                query = query.where(
                    ClientTelemetryRecord.installation_id == str(installation_id)
                )
            records = session.scalars(query)
            return [ClientTelemetry(
                installation_id=UUID(record.installation_id),
                event_id=UUID(record.event_id),
                name=record.name,
                signal_id=UUID(record.signal_id) if record.signal_id else None,
                ticker=record.ticker,
                evidence_id=UUID(record.evidence_id) if record.evidence_id else None,
                source=record.source,
                context=record.context,
            ) for record in records]

    def dispose(self) -> None:
        self.engine.dispose()


def _notification_preferences(
    record: NotificationPreferencesRecord | None,
) -> NotificationPreferences:
    if record is None:
        return NotificationPreferences.defaults()
    return NotificationPreferences(
        instantAlertsEnabled=record.instant_alerts_enabled,
        dailyDigestEnabled=record.daily_digest_enabled,
        dailyDigestMinutes=record.daily_digest_minutes,
        quietHoursEnabled=record.quiet_hours_enabled,
        quietHoursStartMinutes=record.quiet_hours_start_minutes,
        quietHoursEndMinutes=record.quiet_hours_end_minutes,
        mutedTickers=json.loads(record.muted_tickers_json),
    )


def _daily_digest_snapshot(record: DailyDigestRecord) -> DailyDigestSnapshotRecord:
    return DailyDigestSnapshotRecord(
        installation_id=UUID(record.installation_id),
        digest_id=UUID(record.digest_id),
        local_date=record.local_date,
        generated_at=_as_utc(record.generated_at),
        period_start=_as_utc(record.period_start),
        period_end=_as_utc(record.period_end),
        data_as_of=_as_utc(record.data_as_of),
        title=record.title,
        summary=record.summary,
        signals=json.loads(record.signals_json),
    )
