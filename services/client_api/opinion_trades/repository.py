from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, String, create_engine, delete, func, inspect, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from ..accounts.repository import AccountRepository


class TradeBase(DeclarativeBase):
    pass


class PublicTrader(TradeBase):
    __tablename__ = "opinion_public_trader"
    account_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    public_id: Mapped[str] = mapped_column(String(36), unique=True)
    nickname: Mapped[str] = mapped_column(String(28))
    avatar_url: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    visible: Mapped[bool] = mapped_column(Boolean, default=False)
    feed_visible: Mapped[bool] = mapped_column(Boolean, default=False)


class OpinionFill(TradeBase):
    __tablename__ = "opinion_verified_fill"
    venue: Mapped[str] = mapped_column(String(32), primary_key=True)
    fill_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    opinion_id: Mapped[str] = mapped_column(String(36), index=True)
    account_id: Mapped[str] = mapped_column(String(36), index=True)
    order_id: Mapped[str] = mapped_column(String(128))
    ticker: Mapped[str] = mapped_column(String(32))
    side: Mapped[str] = mapped_column(String(5))
    traded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    notional_usd: Mapped[str | None] = mapped_column(String(64), nullable=True)
    market_coin: Mapped[str | None] = mapped_column(String(64), nullable=True)


@dataclass(frozen=True)
class ConfirmedOpinionFill:
    """Internal adapter output, NOT an HTTP input or proof from a client.

    The real reconciler must verify the pre-submission source, account-bound
    order and exchange evidence before constructing this record.
    """
    venue: str
    fill_id: str
    opinion_id: UUID
    account_id: UUID
    order_id: str
    ticker: str
    side: str
    traded_at: datetime
    quantity: Decimal
    mainnet: bool
    final: bool
    notional_usd: Decimal | None = None
    market_coin: str | None = None


class OpinionTradeRepository:
    def __init__(self, database_url: str):
        self.engine = create_engine(database_url, pool_pre_ping=True)
        self.sessions = sessionmaker(self.engine)
        # Schema is operator-managed; never migrate an app database here.

    @staticmethod
    def delete_account_data(db, account_id: UUID):
        """Join the caller's deletion transaction; never erase another account's records."""
        schema = inspect(db.connection())
        for model in (PublicTrader, OpinionFill):
            # This optional domain has not been installed in every account database.
            if schema.has_table(model.__tablename__):
                db.execute(delete(model).where(model.account_id == str(account_id)))

    def record_confirmed(self, fill: ConfirmedOpinionFill) -> bool:
        if (fill.venue != "hyperliquid" or not fill.mainnet or not fill.final
                or not fill.quantity.is_finite() or fill.quantity <= 0
                or fill.side not in ("long", "short") or fill.traded_at.tzinfo is None
                or fill.traded_at > datetime.now(UTC)
                or not 1 <= len(fill.fill_id) <= 128 or not 1 <= len(fill.order_id) <= 128
                or not 1 <= len(fill.ticker) <= 32):
            raise ValueError("Not an eligible confirmed mainnet execution")
        if (fill.notional_usd is None) != (fill.market_coin is None):
            raise ValueError("Feed execution value and market must be verified together")
        if fill.notional_usd is not None and (
                not fill.notional_usd.is_finite() or not 0 < fill.notional_usd < Decimal('1e20')
                or len(format(fill.notional_usd, 'f')) > 64
                or not 1 <= len(fill.market_coin) <= 64):
            raise ValueError("Invalid verified Feed execution")
        values = dict(venue=fill.venue, fill_id=fill.fill_id, opinion_id=str(fill.opinion_id),
                      account_id=str(fill.account_id), order_id=fill.order_id, ticker=fill.ticker,
                      side=fill.side, traded_at=fill.traded_at.astimezone(UTC),
                      notional_usd=format(fill.notional_usd, 'f') if fill.notional_usd is not None else None,
                      market_coin=fill.market_coin)
        try:
            with self.sessions.begin() as db:
                AccountRepository.require_personal_data_write(db, fill.account_id)
                existing = db.scalar(select(OpinionFill).where(
                    OpinionFill.venue == fill.venue, OpinionFill.account_id == str(fill.account_id),
                    OpinionFill.order_id == fill.order_id).limit(1))
                if existing is not None:
                    for key in ('opinion_id', 'ticker', 'side'):
                        if getattr(existing, key) != values[key]:
                            raise ValueError('Conflicting order attribution')
                    if existing.market_coin is not None and fill.market_coin != existing.market_coin:
                        raise ValueError('Conflicting order market')
                db.add(OpinionFill(**values))
            return True
        except IntegrityError:
            with self.sessions() as db:
                previous = db.get(OpinionFill, (fill.venue, fill.fill_id))
                if previous is None:
                    raise
                for key, value in values.items():
                    old = getattr(previous, key)
                    if key == "traded_at":
                        old = old.replace(tzinfo=UTC) if old.tzinfo is None else old.astimezone(UTC)
                    if key == 'notional_usd' and old is not None and value is not None:
                        old, value = Decimal(old), Decimal(value)
                    if old != value:
                        raise ValueError("Conflicting duplicate execution")
            return False

    def update_public_profile(self, account_id: UUID, *, nickname: str,
                              avatar_url: str | None, visible: bool, feed_visible: bool | None = None):
        """Called only by a future authenticated profile/consent service."""
        nickname = nickname.strip()
        if not 1 <= len(nickname) <= 28:
            raise ValueError("Invalid public nickname")
        # Public avatars must come from the controlled upload pipeline, not arbitrary URLs.
        if avatar_url is not None and (not avatar_url.startswith("https://api.bsmart.today/v1/public-avatars/")
                                       or len(avatar_url) > 2048):
            raise ValueError("Unapproved public avatar")
        with self.sessions.begin() as db:
            AccountRepository.require_personal_data_write(db, account_id)
            profile = db.get(PublicTrader, str(account_id))
            if profile is None:
                profile = PublicTrader(account_id=str(account_id), public_id=str(uuid4()))
                db.add(profile)
            profile.nickname, profile.avatar_url, profile.visible = nickname, avatar_url, visible
            if not visible:
                profile.feed_visible = False
            elif feed_visible is not None:
                profile.feed_visible = feed_visible

    def page(self, opinion_id: UUID, *, offset: int = 0, limit: int = 30) -> dict:
        if offset < 0 or not 1 <= limit <= 50:
            raise ValueError("Invalid page")
        latest = select(
            OpinionFill.account_id, OpinionFill.side, OpinionFill.traded_at,
            func.row_number().over(partition_by=OpinionFill.account_id,
                                   order_by=(OpinionFill.traded_at.desc(), OpinionFill.fill_id.desc())).label("rank")
        ).where(OpinionFill.opinion_id == str(opinion_id)).subquery()
        visible = select(PublicTrader.public_id, PublicTrader.nickname, PublicTrader.avatar_url,
                         latest.c.side, latest.c.traded_at).join(
            latest, latest.c.account_id == PublicTrader.account_id
        ).where(latest.c.rank == 1, PublicTrader.visible.is_(True))
        with self.sessions() as db:
            total = db.scalar(select(func.count(func.distinct(OpinionFill.account_id))).where(
                OpinionFill.opinion_id == str(opinion_id)))
            public = db.scalar(select(func.count()).select_from(visible.subquery()))
            rows = db.execute(visible.order_by(latest.c.traded_at.desc(), PublicTrader.public_id)
                              .offset(offset).limit(limit)).all()
        return dict(totalTraders=total, publicTraders=public,
                    nextOffset=offset + len(rows) if offset + len(rows) < public else None,
                    traders=[dict(id=row.public_id, nickname=row.nickname, avatarURL=row.avatar_url,
                                  side=row.side, tradedAt=(row.traded_at.replace(tzinfo=UTC)
                                      if row.traded_at.tzinfo is None else row.traded_at).isoformat()) for row in rows])
