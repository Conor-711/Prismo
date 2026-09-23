"""Bounded opinion projection for the authenticated native Feed registrar."""
from datetime import UTC, datetime
import math
import os
import secrets
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response


def resolve_context(read_models, opinion_id: UUID, author_id: str, *, require_top_quartile: bool = True):
    author = next((a for a in read_models.smart_accounts() if a['id'] == author_id), None)
    percentile = author.get('platformPercentile') if author else None
    if (isinstance(percentile, bool) or not isinstance(percentile, (int, float))
            or not math.isfinite(percentile) or not 0 <= percentile <= (.25 if require_top_quartile else 1)):
        raise ValueError('ineligible_author')
    opinion = next((o for o in read_models.smart_account_evidence(author_id)
                    + read_models.smart_account_updates()
                    if o['id'].lower() == str(opinion_id) and o['authorId'] == author_id), None)
    if not opinion or opinion['platform'] != author['platform']:
        raise ValueError('unknown_opinion')
    if datetime.fromisoformat(opinion['publishedAt'].replace('Z', '+00:00')) > datetime.now(UTC):
        raise ValueError('future_opinion')
    keys = ('id', 'ticker', 'companyName', 'authorId', 'authorName', 'platform', 'score',
            'platformPercentile', 'direction', 'lifecycle', 'horizon', 'targetPrice',
            'thesis', 'invalidation', 'publishedAt', 'evidenceURL', 'authorAvatarURL',
            'sourceURL', 'sourcePostId', 'authorScoreAsOf')
    result = {k: opinion[k] for k in keys if k in opinion}
    result.update(score=author['score'], platformPercentile=percentile)
    # Feed is an excerpt; full evidence remains available through the original opinion.
    for key in ('originalText', 'evidenceSpan', 'translatedTextZH', 'translatedTextEN'):
        if opinion.get(key):
            result[key] = opinion[key][:1500]
    return result


def make_feed_context_router(read_models):
    router = APIRouter()

    def require_catalog_service(request: Request):
        token = os.environ.get('BSMART_FEED_CATALOG_TOKEN', '')
        if len(token) < 32:
            raise HTTPException(503, 'Feed catalog not configured', headers={'Cache-Control': 'no-store'})
        received = request.headers.get('authorization', '')
        if len(received) > 4096 or not secrets.compare_digest(received.encode(), ('Bearer ' + token).encode()):
            raise HTTPException(401, 'Catalog service authentication required', headers={'Cache-Control': 'no-store'})

    @router.get('/v1/opinions/{opinion_id}/feed-context')
    def context(opinion_id: UUID, authorId: str, response: Response,
                service=Depends(require_catalog_service)):
        response.headers['Cache-Control'] = 'no-store'
        if not 1 <= len(authorId) <= 256:
            raise HTTPException(422, 'Invalid author')
        try:
            return resolve_context(read_models, opinion_id, authorId)
        except (ValueError, KeyError):
            raise HTTPException(404, 'Eligible opinion unavailable',
                                headers={'Cache-Control': 'no-store'}) from None
    return router
