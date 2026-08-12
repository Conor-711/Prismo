from __future__ import annotations

import asyncio
import logging
import os

from services.client_api.apns import APNsPushProvider, APNsSettings
from services.client_api.config import ClientAPISettings
from services.client_api.notification_delivery import NotificationDispatcher
from services.client_api.state_store import ClientStateStore


logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
LOGGER = logging.getLogger("bsmart.client_api.notifications")


async def run() -> None:
    interval = max(5, int(os.environ.get("BSMART_NOTIFICATION_DISPATCH_INTERVAL_SECONDS", "30")))
    limit = max(1, int(os.environ.get("BSMART_NOTIFICATION_DISPATCH_LIMIT", "100")))
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
        while True:
            try:
                result = await dispatcher.dispatch_due(limit=limit)
                LOGGER.info("notification dispatch completed: %s", result)
            except Exception:  # noqa: BLE001 - keep later notification batches alive
                LOGGER.exception("notification dispatch failed")
            await asyncio.sleep(interval)
    finally:
        await dispatcher.close()
        state_store.dispose()


def main() -> None:
    asyncio.run(run())


if __name__ == "__main__":
    main()
