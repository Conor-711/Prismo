from uuid import UUID

from fastapi import Depends, HTTPException, Response
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

from .deletion_models import (DeletionInput, DeletionStatus, DeletionStatusInput,
                              DeletionRejected, DeletionReauthenticationRequired)
from .deletion_service import AccountDeletionService
from .deletion_work import AccountDeletionWorkRepository


def add_deletion_routes(router, settings, accounts, client, authenticated, require_installation, available, no_store):
    repository = AccountDeletionWorkRepository(accounts)
    service = AccountDeletionService(repository, settings.apple, client)

    @router.post("/account/deletions", response_model=DeletionStatus, status_code=202)
    async def request_deletion(payload: DeletionInput, response: Response, session=Depends(authenticated)):
        no_store(response)
        if settings.uses_supabase:
            # Do not report full deletion while the Supabase identity still exists.
            raise HTTPException(503, "Supabase account deletion is not available yet.")
        try:
            # Commit acceptance before any external revocation. Status works without the now-revoked account token.
            result = await run_in_threadpool(repository.begin, session[0].id, session[1], payload,
                                            settings.apple.client_id if settings.apple else None)
            await service.process(payload.id)
            # Only return the accepted receipt here; the status endpoint confirms durable completion.
            return result
        except DeletionReauthenticationRequired:
            raise HTTPException(409, "Sign in again before deleting this account.")
        except DeletionRejected:
            raise HTTPException(401, "Account deletion could not be authorized.")
        except SQLAlchemyError:
            raise HTTPException(503, "Deletion status is unavailable. Check the saved request.")

    @router.post("/account/deletions/{identifier}/status", response_model=DeletionStatus)
    async def deletion_status(identifier: UUID, payload: DeletionStatusInput, response: Response,
                              installation=Depends(require_installation)):
        no_store(response)
        available()
        try:
            await run_in_threadpool(repository.status, identifier, installation.installation_id,
                                    payload.statusToken.get_secret_value())
            await service.process(identifier)
            return await run_in_threadpool(repository.status, identifier, installation.installation_id,
                                           payload.statusToken.get_secret_value())
        except DeletionRejected:
            raise HTTPException(404, "Deletion request not found.")
        except SQLAlchemyError:
            raise HTTPException(503, "Deletion status is unavailable. Check the saved request.")
