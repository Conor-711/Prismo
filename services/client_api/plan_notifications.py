from __future__ import annotations

from services.client_api.config import ClientAPISettings
from services.client_api.notification_planner import NotificationPlanner
from services.client_api.read_models import DatabaseReadModelRepository, FixtureReadModelRepository
from services.client_api.state_store import ClientStateStore


def main() -> None:
    settings = ClientAPISettings.from_environment()
    if settings.read_model_mode == "fixture":
        read_models = FixtureReadModelRepository(settings.fixture_root)
    else:
        read_models = DatabaseReadModelRepository(
            settings.read_model_database_url or settings.database_url
        )
    state_store = ClientStateStore(
        settings.database_url,
        session_lifetime_days=settings.session_lifetime_days,
    )
    totals = {"queued": 0, "deferred": 0, "skipped": 0, "existing": 0}
    try:
        planner = NotificationPlanner(state_store)
        for signal in read_models.portfolio_signals():
            result = planner.plan_signal(signal)
            for key in totals:
                totals[key] += getattr(result, key)
    finally:
        read_models.dispose()
        state_store.dispose()

    print("Notification planning complete:")
    for key, value in totals.items():
        print(f"{key}: {value}")


if __name__ == "__main__":
    main()
