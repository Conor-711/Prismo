from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class APIModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class InstallationRegistration(APIModel):
    installation_id: UUID = Field(alias="installationId")
    platform: Literal["ios"]
    app_version: str = Field(alias="appVersion", min_length=1)
    locale: str = Field(min_length=1)
    time_zone: str = Field(alias="timeZone", min_length=1)


class InstallationSession(APIModel):
    installation_id: UUID = Field(alias="installationId")
    access_token: str = Field(alias="accessToken", min_length=1)
    expires_at: datetime = Field(alias="expiresAt")


class PortfolioEntryInput(APIModel):
    ticker: str = Field(min_length=1, max_length=16)
    company_name: str | None = Field(default=None, alias="companyName")
    entry_kind: Literal["position", "watchlist"] = Field(alias="entryKind")
    shares: float | None = Field(default=None, ge=0)
    average_cost: float | None = Field(default=None, alias="averageCost", ge=0)
    portfolio_weight: float | None = Field(default=None, alias="portfolioWeight", ge=0, le=1)

    @field_validator("ticker")
    @classmethod
    def normalize_ticker(cls, value: str) -> str:
        return value.strip().upper()

    @model_validator(mode="after")
    def validate_position_values(self) -> "PortfolioEntryInput":
        if self.entry_kind == "position" and not (
            (self.shares or 0) > 0 or (self.portfolio_weight or 0) > 0
        ):
            raise ValueError("A position requires positive shares or portfolioWeight.")
        return self


class PortfolioPosition(APIModel):
    id: UUID
    ticker: str
    company_name: str = Field(alias="companyName")
    shares: float
    average_cost: float = Field(alias="averageCost")
    current_price: float = Field(alias="currentPrice")
    entry_kind: Literal["position", "watchlist"] = Field(alias="entryKind")
    portfolio_weight: float | None = Field(default=None, alias="portfolioWeight")


class PortfolioValuePoint(APIModel):
    timestamp: datetime
    value: float = Field(ge=0)


SignalFeedback = Literal["useful", "not_relevant", "too_late", "unclear"]


class SignalUserStateInput(APIModel):
    is_read: bool = Field(alias="isRead")
    is_saved: bool = Field(alias="isSaved")
    is_ignored: bool = Field(alias="isIgnored")
    feedback: SignalFeedback | None = None


class SignalUserState(SignalUserStateInput):
    signal_id: UUID = Field(alias="signalId")
    updated_at: datetime = Field(alias="updatedAt")


class NotificationPreferences(APIModel):
    instant_alerts_enabled: bool = Field(alias="instantAlertsEnabled")
    daily_digest_enabled: bool = Field(alias="dailyDigestEnabled")
    daily_digest_minutes: int = Field(alias="dailyDigestMinutes", ge=0, le=1439)
    quiet_hours_enabled: bool = Field(alias="quietHoursEnabled")
    quiet_hours_start_minutes: int = Field(alias="quietHoursStartMinutes", ge=0, le=1439)
    quiet_hours_end_minutes: int = Field(alias="quietHoursEndMinutes", ge=0, le=1439)
    muted_tickers: list[str] = Field(alias="mutedTickers")

    @field_validator("muted_tickers")
    @classmethod
    def normalize_tickers(cls, values: list[str]) -> list[str]:
        return sorted({value.strip().upper() for value in values if value.strip()})

    @classmethod
    def defaults(cls) -> "NotificationPreferences":
        return cls(
            instantAlertsEnabled=True,
            dailyDigestEnabled=True,
            dailyDigestMinutes=8 * 60,
            quietHoursEnabled=True,
            quietHoursStartMinutes=22 * 60,
            quietHoursEndMinutes=7 * 60,
            mutedTickers=[],
        )


class DeviceRegistrationInput(APIModel):
    apns_token: str = Field(alias="apnsToken", min_length=1)
    environment: Literal["development", "production"]
    app_version: str = Field(alias="appVersion", min_length=1)
    locale: str = Field(min_length=1)
    time_zone: str = Field(alias="timeZone", min_length=1)


TelemetryEventName = Literal[
    "notification_opened",
    "daily_digest_opened",
    "signal_opened",
    "evidence_opened",
    "signal_saved",
    "signal_ignored",
    "signal_feedback",
]
TelemetryContext = Literal[
    "push",
    "today",
    "signal_detail",
    "daily_digest",
    "research",
    "opportunity",
    "smart",
]
TelemetrySource = Literal["smart_account", "smart_money"]


class ClientTelemetryEvent(APIModel):
    id: UUID
    name: TelemetryEventName
    occurred_at: datetime = Field(alias="occurredAt")
    signal_id: UUID | None = Field(default=None, alias="signalId")
    ticker: str | None = Field(default=None, max_length=16)
    evidence_id: UUID | None = Field(default=None, alias="evidenceId")
    source: TelemetrySource | None = None
    context: TelemetryContext

    @field_validator("occurred_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.utcoffset() is None:
            raise ValueError("occurredAt must include a timezone offset.")
        return value

    @field_validator("ticker")
    @classmethod
    def normalize_optional_ticker(cls, value: str | None) -> str | None:
        return value.strip().upper() if value and value.strip() else None


class ClientTelemetryBatch(APIModel):
    events: list[ClientTelemetryEvent] = Field(min_length=1, max_length=100)


class DailyDigestSnapshot(APIModel):
    id: UUID
    generated_at: datetime = Field(alias="generatedAt")
    data_as_of: datetime = Field(alias="dataAsOf")
    period_start: datetime = Field(alias="periodStart")
    period_end: datetime = Field(alias="periodEnd")
    title: str
    summary: str
    signals: list[dict[str, Any]]


class MrCollieConversationTurn(APIModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2_400)

    @field_validator("content")
    @classmethod
    def normalize_content(cls, value: str) -> str:
        return value.strip()


class MrCollieQuery(APIModel):
    question: str = Field(min_length=1, max_length=1_500)
    locale: str = Field(default="en", min_length=2, max_length=32)
    conversation: list[MrCollieConversationTurn] = Field(default_factory=list, max_length=8)

    @field_validator("question")
    @classmethod
    def normalize_question(cls, value: str) -> str:
        return value.strip()


class MrCollieEvidence(APIModel):
    id: str
    source: Literal["Smart Account", "Smart Money"]
    source_type: Literal["smart_account", "smart_money"] = Field(alias="sourceType")
    title: str
    detail: str
    metric: str | None = None
    observed_at: datetime | None = Field(default=None, alias="observedAt")


class MrCollieResponse(APIModel):
    question: str
    title: str
    summary: str
    context: str | None = None
    next_step: str = Field(alias="nextStep")
    ticker: str | None = None
    signal_id: UUID | None = Field(default=None, alias="signalId")
    evidence: list[MrCollieEvidence]
    generated_at: datetime = Field(alias="generatedAt")
    data_as_of: datetime = Field(alias="dataAsOf")
    context_version: str = Field(alias="contextVersion")
    model: str


class HealthResponse(APIModel):
    status: Literal["ok"]
    environment: str
    read_model_mode: str = Field(alias="readModelMode")
