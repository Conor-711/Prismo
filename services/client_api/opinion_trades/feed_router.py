from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.exc import SQLAlchemyError


def make_trade_feed_router(require_installation, repository):
    router = APIRouter()
    headers = {'Cache-Control': 'no-store'}

    def unavailable():
        return HTTPException(503, 'Verified trade Feed unavailable.', headers=headers)

    @router.get('/v1/trade-feed')
    def feed(response: Response, offset: Annotated[int, Query(ge=0)] = 0,
             limit: Annotated[int, Query(ge=1, le=50)] = 30,
             profileId: UUID | None = None, installation=Depends(require_installation)):
        response.headers.update(headers)
        if repository is None:
            raise unavailable()
        try:
            return repository.page(offset=offset, limit=limit, profile_id=profileId)
        except SQLAlchemyError:
            raise unavailable() from None

    @router.get('/v1/public-traders/{profile_id}')
    def profile(profile_id: UUID, response: Response, installation=Depends(require_installation)):
        response.headers.update(headers)
        if repository is None:
            raise unavailable()
        try:
            result = repository.profile(profile_id)
        except SQLAlchemyError:
            raise unavailable() from None
        if result is None:
            raise HTTPException(404, 'Public profile unavailable.', headers=headers)
        return result

    return router
