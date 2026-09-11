from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.exc import SQLAlchemyError

from .repository import OpinionTradeRepository


def make_opinion_trade_router(require_installation, repository: OpinionTradeRepository | None):
    router = APIRouter()

    @router.get("/v1/opinions/{opinion_id}/traders")
    def traders(opinion_id: UUID, response: Response,
                offset: Annotated[int, Query(ge=0)] = 0,
                limit: Annotated[int, Query(ge=1, le=50)] = 30,
                installation=Depends(require_installation)):
        response.headers["Cache-Control"] = "no-store"
        if repository is None:
            raise HTTPException(503, "Real trade statistics are not available.", headers={"Cache-Control": "no-store"})
        try:
            return repository.page(opinion_id, offset=offset, limit=limit)
        except SQLAlchemyError:
            raise HTTPException(503, "Trade statistics temporarily unavailable.", headers={"Cache-Control": "no-store"}) from None

    return router
