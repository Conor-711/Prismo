from __future__ import annotations

import argparse
import asyncio

from services.client_api.apns import APNsPushProvider, APNsSettings
from services.client_api.config import ClientAPISettings
from services.client_api.notification_delivery import NotificationDispatcher
from services.client_api.state_store import ClientStateStore


async def dispatch(limit: int) -> None:
    settings = ClientAPISettings.from_environment()
    state_store = ClientStateStore(
        settings.database_url,
        session_lifetime_days=settings.session_lifetime_days,
    )
    dispatcher = NotificationDispatcher(
        state_store,
        APNsPushProvider(APNsSettings.from_environment()),
    )
    try:
        result = await dispatcher.dispatch_due(limit=limit)
    finally:
        await dispatcher.close()
        state_store.dispose()
    print(f"sent: {result.sent}")
    print(f"retried: {result.retried}")
    print(f"failed: {result.failed}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Dispatch due bSmart notifications through APNs.")
    parser.add_argument("--limit", type=int, default=100)
    arguments = parser.parse_args()
    asyncio.run(dispatch(max(1, arguments.limit)))


if __name__ == "__main__":
    main()
