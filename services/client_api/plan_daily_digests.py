from __future__ import annotations

import argparse
from datetime import datetime

from services.client_api.config import ClientAPISettings
from services.client_api.daily_digest_planner import DailyDigestPlanner
from services.client_api.read_models import DatabaseReadModelRepository, FixtureReadModelRepository
from services.client_api.state_store import ClientStateStore


def main() -> None:
    parser = argparse.ArgumentParser(description="Plan due bSmart daily digest notifications.")
    parser.add_argument(
        "--now",
        help="Optional ISO-8601 planning time used by deterministic smoke tests.",
    )
    args = parser.parse_args()
    planning_time = datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now else None

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
    try:
        result = DailyDigestPlanner(state_store).plan(
            read_models.portfolio_signals(),
            now=planning_time,
        )
    finally:
        read_models.dispose()
        state_store.dispose()

    print("Daily digest planning complete:")
    for key in ("queued", "existing", "disabled", "not_due", "no_changes"):
        print(f"{key}: {getattr(result, key)}")


if __name__ == "__main__":
    main()
