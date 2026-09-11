"""Opt-in pre-production worker for already accepted account-deletion requests."""
import asyncio
import logging
from contextlib import asynccontextmanager

from sqlalchemy.exc import SQLAlchemyError

from .deletion_service import AccountDeletionService
from .deletion_work import AccountDeletionWorkRepository

logger = logging.getLogger(__name__)


async def run_deletion_worker(service, *, sleep=asyncio.sleep):
    while True:
        try:
            await service.process_due(limit=10)
        except SQLAlchemyError:
            # Never include exception repr/SQL, request tickets or provider credential material.
            logger.warning("Account deletion storage is unavailable; pending work retained.")
        await sleep(30)


@asynccontextmanager
async def deletion_worker_lifecycle(settings, accounts, client):
    task = None
    if settings.enabled and settings.deletion_worker_enabled:
        service = AccountDeletionService(AccountDeletionWorkRepository(accounts), settings.apple, client)
        task = asyncio.create_task(run_deletion_worker(service), name="bsmart-account-deletion")
    try:
        yield
    finally:
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
