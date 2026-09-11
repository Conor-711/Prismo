"""Read projection of the independently verified ledger, never a public fill writer."""
from datetime import UTC, datetime
from decimal import Decimal
import math
from uuid import UUID, NAMESPACE_URL, uuid5

from sqlalchemy import Boolean, DateTime, JSON, String, func, select, tuple_
from sqlalchemy.orm import Mapped, mapped_column

from .repository import OpinionFill, OpinionTradeRepository, PublicTrader, TradeBase


class FeedOpinionContext(TradeBase):
    __tablename__ = 'opinion_feed_context'
    opinion_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    ticker: Mapped[str] = mapped_column(String(32))
    payload: Mapped[dict] = mapped_column(JSON)
    registered_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    visible: Mapped[bool] = mapped_column(Boolean, default=True)


def utc(value):
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def public_profile(profile):
    return dict(id=profile.public_id, nickname=profile.nickname, avatarURL=profile.avatar_url)


class TradeFeedRepository:
    def __init__(self, ledger: OpinionTradeRepository, read_models):
        self.ledger = ledger
        self.read_models = read_models

    def register_opinion(self, opinion_id: UUID, author_id: str, *, now=None):
        """Internal pre-submission hook. Resolve facts from the server catalog only.

        Real order attribution/verification remains the executor's responsibility.
        Clients cannot register contexts or declare themselves high-score authors.
        """
        now = now or datetime.now(UTC)
        author = next((a for a in self.read_models.smart_accounts() if a['id'] == author_id), None)
        if author is None:
            raise ValueError('Unknown author')
        percentile = author.get('platformPercentile')
        if (not isinstance(percentile, (float, int)) or isinstance(percentile, bool)
                or not math.isfinite(percentile) or not 0 <= percentile <= .25):
            raise ValueError('Author is not in the explicit platform Top 25%')
        candidates = self.read_models.smart_account_evidence(author_id) + self.read_models.smart_account_updates()
        opinion = next((o for o in candidates if o['id'].lower() == str(opinion_id)
                        and o['authorId'] == author_id), None)
        if opinion is None or opinion['platform'] != author['platform']:
            raise ValueError('Opinion does not belong to this author')
        if utc(datetime.fromisoformat(opinion['publishedAt'].replace('Z', '+00:00'))) > now:
            raise ValueError('Opinion is not yet published')
        required = ('id', 'ticker', 'companyName', 'authorId', 'authorName', 'platform',
                    'score', 'platformPercentile', 'direction', 'lifecycle', 'horizon',
                    'targetPrice', 'thesis', 'invalidation', 'publishedAt', 'evidenceURL')
        payload = {key: opinion[key] for key in required}
        for key in ('originalText', 'evidenceSpan', 'authorAvatarURL', 'sourceURL', 'sourcePostId',
                    'translatedTextZH', 'translatedTextEN', 'authorScoreAsOf'):
            if key in opinion:
                payload[key] = opinion[key]
        payload['platformPercentile'] = percentile
        payload['score'] = author['score']
        with self.ledger.sessions.begin() as db:
            previous = db.get(FeedOpinionContext, str(opinion_id))
            if previous:
                # Existing historical contexts are immutable, including explicit withdrawal.
                if previous.ticker != opinion['ticker'] or previous.payload['authorId'] != author_id:
                    raise ValueError('Conflicting opinion context')
                return
            db.add(FeedOpinionContext(opinion_id=str(opinion_id), ticker=opinion['ticker'],
                                      payload=payload, registered_at=now, visible=True))

    def withdraw_opinion(self, opinion_id: UUID):
        with self.ledger.sessions.begin() as db:
            context = db.get(FeedOpinionContext, str(opinion_id))
            if context:
                context.visible = False

    def profile(self, public_id: UUID):
        with self.ledger.sessions() as db:
            profile = db.scalar(select(PublicTrader).where(
                PublicTrader.public_id == str(public_id), PublicTrader.visible.is_(True),
                PublicTrader.feed_visible.is_(True)))
            return public_profile(profile) if profile else None

    def page(self, *, offset=0, limit=30, profile_id: UUID | None = None):
        if offset < 0 or not 1 <= limit <= 50:
            raise ValueError('Invalid page')
        # Group before pagination: partial fills never produce separate social posts.
        group_keys = (OpinionFill.venue, OpinionFill.account_id, OpinionFill.order_id)
        first = func.min(OpinionFill.traded_at).label('first_fill')
        grouped = select(*group_keys, first).join(
            PublicTrader, PublicTrader.account_id == OpinionFill.account_id
        ).join(FeedOpinionContext, FeedOpinionContext.opinion_id == OpinionFill.opinion_id).where(
            PublicTrader.visible.is_(True), PublicTrader.feed_visible.is_(True),
            FeedOpinionContext.visible.is_(True), FeedOpinionContext.ticker == OpinionFill.ticker
        )
        if profile_id:
            grouped = grouped.where(PublicTrader.public_id == str(profile_id))
        grouped = grouped.group_by(*group_keys).having(
            func.count(OpinionFill.notional_usd) == func.count(),
            func.count(OpinionFill.market_coin) == func.count(),
            func.count(func.distinct(OpinionFill.opinion_id)) == 1,
            func.count(func.distinct(OpinionFill.ticker)) == 1,
            func.count(func.distinct(OpinionFill.side)) == 1,
            func.count(func.distinct(OpinionFill.market_coin)) == 1,
            func.min(OpinionFill.traded_at) >= func.max(FeedOpinionContext.registered_at)
        ).order_by(first.desc(), *group_keys).offset(offset).limit(limit + 1)
        with self.ledger.sessions() as db:
            groups = db.execute(grouped).all()
            chosen = groups[:limit]
            if not chosen:
                return dict(items=[], nextOffset=None)
            rows = db.execute(select(OpinionFill, PublicTrader, FeedOpinionContext).join(
                PublicTrader, PublicTrader.account_id == OpinionFill.account_id
            ).join(FeedOpinionContext, FeedOpinionContext.opinion_id == OpinionFill.opinion_id).where(
                tuple_(*group_keys).in_([tuple(g[:3]) for g in chosen]),
                PublicTrader.visible.is_(True), PublicTrader.feed_visible.is_(True),
                FeedOpinionContext.visible.is_(True)
            )).all()
            by_order = {}
            for fill, profile, context in rows:
                key = (fill.venue, fill.account_id, fill.order_id)
                value = by_order.setdefault(key, dict(fills=[], profile=profile, context=context))
                value['fills'].append(fill)
            items = []
            for group in chosen:
                key = tuple(group[:3])
                value = by_order.get(key)
                if value is None:
                    continue
                fills = value['fills']
                representative = fills[0]
                amount = sum((Decimal(f.notional_usd) for f in fills), Decimal(0))
                items.append(dict(id=str(uuid5(NAMESPACE_URL, 'bsmart:trade:' + ':'.join(key))),
                                  trader=public_profile(value['profile']), opinion=value['context'].payload,
                                  side=representative.side, notionalUSD=format(amount, 'f'),
                                  marketCoin=representative.market_coin, executedAt=utc(group.first_fill).isoformat()))
        # A concurrent privacy change may remove rows. Refresh restarts pagination.
        return dict(items=items, nextOffset=offset + len(items) if len(groups) > limit and items else None)
