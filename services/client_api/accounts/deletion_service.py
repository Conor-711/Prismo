"""Resumable deletion processing; a failed provider call never means completed."""
import asyncio

from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

from .apple_revocation import AppleTokenRevocation
from .credential_cipher import CredentialUnavailable
from .deletion_models import DeletionRejected
from .oidc import IdentityUnavailable


class AccountDeletionService:
    def __init__(self, repository, apple_settings, client):
        self.repository, self.apple_settings, self.client = repository, apple_settings, client

    async def process(self, identifier):
        work = await run_in_threadpool(self.repository.claim, identifier)
        if work is None:
            return
        try:
            if work.provider == "apple":
                settings = self.apple_settings
                if (settings is None or work.client_id != settings.client_id
                        or work.key_id is None or work.ciphertext is None):
                    raise CredentialUnavailable()
                token = settings.cipher.open(work.key_id, work.ciphertext, work.account_id, work.subject, work.client_id)
                await AppleTokenRevocation(settings, self.client).revoke(token)
            await run_in_threadpool(self.repository.complete, work)
        except asyncio.CancelledError:
            # A process death/cancelled request leaves the durable lease for a later worker.
            raise
        except (CredentialUnavailable, IdentityUnavailable, SQLAlchemyError, DeletionRejected):
            await run_in_threadpool(self.repository.retry, work)

    async def process_due(self, limit=100):
        for identifier in await run_in_threadpool(self.repository.due, limit):
            await self.process(identifier)
        await run_in_threadpool(self.repository.prune_receipts)
