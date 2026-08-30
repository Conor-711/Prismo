from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Any, Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from services.client_api.config import ClientAPISettings
from services.client_api.read_models import (
    DatabaseReadModelRepository,
    FixtureReadModelRepository,
    ReadModelRepository,
)
from services.client_api.mr_collie import (
    MrCollieConfig,
    MrCollieRateLimiter,
    MrCollieRateLimitExceeded,
    MrCollieService,
    MrCollieUnavailable,
    MrCollieUpstreamError,
)
from services.client_api.schemas import (
    ClientTelemetryBatch,
    DailyDigestSnapshot,
    DeviceRegistrationInput,
    HealthResponse,
    InstallationRegistration,
    InstallationSession,
    MrCollieQuery,
    MrCollieResponse,
    NotificationPreferences,
    PortfolioEntryInput,
    PortfolioPosition,
    PortfolioValuePoint,
    SignalUserState,
    SignalUserStateInput,
)
from services.client_api.state_store import AuthenticatedInstallation, ClientStateStore


bearer = HTTPBearer(auto_error=False)


def require_installation(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> AuthenticatedInstallation:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing installation token.")
    installation = request.app.state.state_store.authenticate(credentials.credentials)
    if installation is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid installation token.")
    return installation


InstallationDependency = Annotated[AuthenticatedInstallation, Depends(require_installation)]


def _document_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    else:
        raw = str(value or "").strip()
        if not raw:
            return None
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def create_app(
    settings: ClientAPISettings | None = None,
    mr_collie_service: MrCollieService | None = None,
) -> FastAPI:
    resolved_settings = settings or ClientAPISettings.from_environment()
    read_models: ReadModelRepository
    if resolved_settings.read_model_mode == "fixture":
        read_models = FixtureReadModelRepository(resolved_settings.fixture_root)
    else:
        read_models = DatabaseReadModelRepository(
            resolved_settings.read_model_database_url or resolved_settings.database_url
        )
    state_store = ClientStateStore(
        resolved_settings.database_url,
        session_lifetime_days=resolved_settings.session_lifetime_days,
        telemetry_retention_days=resolved_settings.telemetry_retention_days,
    )
    collie = mr_collie_service or MrCollieService(MrCollieConfig(
        api_key=resolved_settings.deepseek_api_key,
        base_url=resolved_settings.deepseek_base_url,
        model=resolved_settings.mr_collie_model,
        timeout_seconds=resolved_settings.mr_collie_timeout_seconds,
    ))
    collie_rate_limiter = MrCollieRateLimiter(resolved_settings.mr_collie_requests_per_minute)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        await collie.close()
        read_models.dispose()
        state_store.dispose()

    app = FastAPI(
        title="bSmart Client API",
        version="1.6.0",
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.read_models = read_models
    app.state.state_store = state_store
    app.state.mr_collie = collie

    @app.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        return HealthResponse(
            status="ok",
            environment=resolved_settings.environment,
            readModelMode=resolved_settings.read_model_mode,
        )

    @app.post(
        "/v1/installations",
        response_model=InstallationSession,
        status_code=status.HTTP_201_CREATED,
    )
    def create_installation(registration: InstallationRegistration) -> InstallationSession:
        token, expires_at = state_store.register_installation(registration)
        return InstallationSession(
            installationId=registration.installation_id,
            accessToken=token,
            expiresAt=expires_at,
        )

    @app.get("/v1/portfolio", response_model=list[PortfolioPosition])
    def get_portfolio(installation: InstallationDependency) -> list[PortfolioPosition]:
        return [portfolio_response(item) for item in state_store.list_portfolio(installation.installation_id)]

    @app.get("/v1/portfolio/history", response_model=list[PortfolioValuePoint])
    def get_portfolio_history(_: InstallationDependency) -> list[PortfolioValuePoint]:
        # Populated by brokerage valuation snapshots once an account is connected.
        return []

    @app.put("/v1/portfolio/{entry_id}", response_model=PortfolioPosition)
    def put_portfolio_entry(
        entry_id: UUID,
        payload: PortfolioEntryInput,
        installation: InstallationDependency,
    ) -> PortfolioPosition:
        record = state_store.upsert_portfolio(installation.installation_id, entry_id, payload)
        return portfolio_response(record)

    @app.delete("/v1/portfolio/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
    def delete_portfolio_entry(entry_id: UUID, installation: InstallationDependency) -> Response:
        state_store.delete_portfolio(installation.installation_id, entry_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/v1/feed", response_model=list[dict[str, Any]])
    def get_feed(response: Response, _: InstallationDependency) -> list[dict[str, Any]]:
        set_read_model_headers(response, "portfolio-signals")
        return read_models.portfolio_signals()

    @app.get("/v1/signals/{signal_id}", response_model=dict[str, Any])
    def get_signal(
        signal_id: UUID,
        response: Response,
        _: InstallationDependency,
    ) -> dict[str, Any]:
        set_read_model_headers(response, "portfolio-signals")
        signal = read_models.signal(str(signal_id))
        if signal is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Signal not found.")
        return signal

    @app.put("/v1/signals/{signal_id}/state", response_model=SignalUserState)
    def put_signal_state(
        signal_id: UUID,
        payload: SignalUserStateInput,
        installation: InstallationDependency,
    ) -> SignalUserState:
        record = state_store.put_signal_state(installation.installation_id, signal_id, payload)
        return SignalUserState(
            signalId=UUID(record.signal_id),
            isRead=record.is_read,
            isSaved=record.is_saved,
            isIgnored=record.is_ignored,
            feedback=record.feedback,
            updatedAt=record.updated_at,
        )

    @app.get("/v1/notification-preferences", response_model=NotificationPreferences)
    def get_notification_preferences(installation: InstallationDependency) -> NotificationPreferences:
        return state_store.get_notification_preferences(installation.installation_id)

    @app.put("/v1/notification-preferences", response_model=NotificationPreferences)
    def put_notification_preferences(
        payload: NotificationPreferences,
        installation: InstallationDependency,
    ) -> NotificationPreferences:
        return state_store.put_notification_preferences(installation.installation_id, payload)

    @app.get("/v1/daily-digest", response_model=DailyDigestSnapshot)
    def get_daily_digest(installation: InstallationDependency) -> DailyDigestSnapshot:
        digest = state_store.latest_daily_digest(installation.installation_id)
        if digest is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No daily digest has been generated yet.",
            )
        return DailyDigestSnapshot(
            id=digest.digest_id,
            generatedAt=digest.generated_at,
            dataAsOf=digest.data_as_of,
            periodStart=digest.period_start,
            periodEnd=digest.period_end,
            title=digest.title,
            summary=digest.summary,
            signals=digest.signals,
        )

    @app.post("/v1/mr-collie/query", response_model=MrCollieResponse)
    async def query_mr_collie(
        payload: MrCollieQuery,
        response: Response,
        installation: InstallationDependency,
    ) -> MrCollieResponse:
        try:
            response.headers["Cache-Control"] = "no-store"
            collie_rate_limiter.check(str(installation.installation_id))
            portfolio = [
                portfolio_response(item).model_dump(by_alias=True, mode="json")
                for item in state_store.list_portfolio(installation.installation_id)
            ]
            return await collie.answer(
                payload,
                portfolio=portfolio,
                signals=read_models.portfolio_signals(),
                intelligence=read_models.ticker_intelligence(),
            )
        except MrCollieRateLimitExceeded as error:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=str(error),
            ) from error
        except MrCollieUnavailable as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=str(error),
            ) from error
        except MrCollieUpstreamError as error:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=str(error),
            ) from error

    @app.put("/v1/devices", status_code=status.HTTP_204_NO_CONTENT)
    def put_device(payload: DeviceRegistrationInput, installation: InstallationDependency) -> Response:
        state_store.put_device(installation.installation_id, payload)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.post("/v1/telemetry/events", status_code=status.HTTP_202_ACCEPTED)
    def post_telemetry_events(
        payload: ClientTelemetryBatch,
        installation: InstallationDependency,
    ) -> Response:
        state_store.record_telemetry(installation.installation_id, payload)
        return Response(status_code=status.HTTP_202_ACCEPTED)

    @app.get("/v1/smart-account-updates", response_model=list[dict[str, Any]])
    def get_smart_account_updates(
        response: Response,
        _: InstallationDependency,
    ) -> list[dict[str, Any]]:
        result = read_models.smart_account_updates()
        set_read_model_headers(
            response,
            "smart-account-updates",
            items=result,
            content_timestamp_fields=("publishedAt",),
        )
        return result

    @app.get("/v1/smart-accounts/{account_id}/evidence", response_model=list[dict[str, Any]])
    def get_smart_account_evidence(
        account_id: str,
        response: Response,
        _: InstallationDependency,
    ) -> list[dict[str, Any]]:
        result = read_models.smart_account_evidence(account_id)
        set_read_model_headers(
            response,
            "smart-account-evidence",
            items=result,
            content_timestamp_fields=("publishedAt", "authorScoreAsOf"),
        )
        return result

    @app.get("/v1/smart-money-movements", response_model=list[dict[str, Any]])
    def get_smart_money_movements(
        response: Response,
        _: InstallationDependency,
        ticker: str | None = None,
        account_id: str | None = None,
        after: datetime | None = None,
        before: datetime | None = None,
        limit: int = 250,
    ) -> list[dict[str, Any]]:
        if limit < 1 or limit > 1_000:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="limit must be between 1 and 1000.",
            )
        all_movements = read_models.smart_money_movements()
        normalized_ticker = ticker.upper() if ticker else None
        normalized_account = account_id.lower() if account_id else None
        after_utc = _document_datetime(after)
        before_utc = _document_datetime(before)
        result: list[dict[str, Any]] = []
        for movement in all_movements:
            if normalized_ticker and str(movement.get("ticker") or "").upper() != normalized_ticker:
                continue
            if normalized_account and str(movement.get("accountId") or "").lower() != normalized_account:
                continue
            observed = _document_datetime(movement.get("observedAt"))
            if after_utc and (observed is None or observed <= after_utc):
                continue
            if before_utc and (observed is None or observed >= before_utc):
                continue
            result.append(movement)
            if len(result) >= limit:
                break
        response.headers["X-BSmart-Result-Count"] = str(len(result))
        set_read_model_headers(
            response,
            "smart-money-movements",
            items=result,
            content_timestamp_fields=("observedAt",),
        )
        return result

    @app.get("/v1/intelligence", response_model=list[dict[str, Any]])
    def get_intelligence(response: Response, _: InstallationDependency) -> list[dict[str, Any]]:
        set_read_model_headers(response, "ticker-intelligence")
        return read_models.ticker_intelligence()

    @app.get("/v1/tickers/{symbol}/intelligence", response_model=dict[str, Any])
    def get_ticker_intelligence(
        symbol: str,
        response: Response,
        _: InstallationDependency,
    ) -> dict[str, Any]:
        set_read_model_headers(response, "ticker-intelligence")
        normalized = symbol.upper()
        result = next(
            (item for item in read_models.ticker_intelligence() if item.get("ticker", "").upper() == normalized),
            None,
        )
        if result is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ticker not found.")
        return result

    @app.get("/v1/smart-accounts", response_model=list[dict[str, Any]])
    def get_smart_accounts(response: Response, _: InstallationDependency) -> list[dict[str, Any]]:
        set_read_model_headers(response, "smart-accounts")
        return read_models.smart_accounts()

    @app.get("/v1/smart-money", response_model=list[dict[str, Any]])
    def get_smart_money(response: Response, _: InstallationDependency) -> list[dict[str, Any]]:
        result = read_models.smart_money()
        set_read_model_headers(
            response,
            "smart-money",
            items=result,
            content_timestamp_fields=("sourceUpdatedAt", "changedAt"),
        )
        return result

    @app.get("/v1/smart-money/{account_id}/evidence", response_model=list[dict[str, Any]])
    def get_smart_money_evidence(
        account_id: str,
        response: Response,
        _: InstallationDependency,
    ) -> list[dict[str, Any]]:
        result = read_models.smart_money_evidence(account_id)
        set_read_model_headers(
            response,
            "smart-money-evidence",
            items=result,
            content_timestamp_fields=("latestEntryAt",),
        )
        return result

    @app.get("/v1/events", response_model=list[dict[str, Any]], deprecated=True)
    def get_legacy_events(_: InstallationDependency) -> list[dict[str, Any]]:
        return read_models.legacy_events()

    @app.get("/v1/research", response_model=list[dict[str, Any]], deprecated=True)
    def get_legacy_research(_: InstallationDependency) -> list[dict[str, Any]]:
        return read_models.legacy_research()

    @app.get("/v1/tickers/{symbol}/research", response_model=dict[str, Any], deprecated=True)
    def get_legacy_ticker_research(symbol: str, _: InstallationDependency) -> dict[str, Any]:
        normalized = symbol.upper()
        result = next(
            (item for item in read_models.legacy_research() if item.get("ticker", "").upper() == normalized),
            None,
        )
        if result is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ticker not found.")
        return result

    def portfolio_response(record: Any) -> PortfolioPosition:
        current_price = read_models.current_price(record.ticker)
        return PortfolioPosition(
            id=UUID(record.entry_id),
            ticker=record.ticker,
            companyName=record.company_name,
            shares=record.shares or 0,
            averageCost=record.average_cost or 0,
            currentPrice=current_price,
            entryKind=record.entry_kind,
            portfolioWeight=record.portfolio_weight,
        )

    def set_read_model_headers(
        response: Response,
        collection: str,
        *,
        items: list[dict[str, Any]] | None = None,
        content_timestamp_fields: tuple[str, ...] = (),
    ) -> None:
        response.headers["ETag"] = f'"{read_models.etag(collection)}"'
        response.headers["Cache-Control"] = "private, max-age=0, must-revalidate"
        updated_at = read_models.updated_at(collection)
        if updated_at is not None:
            response.headers["X-BSmart-Data-As-Of"] = updated_at.isoformat()
        if items is not None:
            response.headers["X-BSmart-Source-Item-Count"] = str(len(items))
            timestamps = [
                parsed
                for item in items
                for field in content_timestamp_fields
                if (parsed := _document_datetime(item.get(field))) is not None
            ]
            if timestamps:
                response.headers["X-BSmart-Latest-Content-At"] = max(timestamps).isoformat()

    return app
