from sqlalchemy import JSON, ForeignKey, Integer, String, DateTime
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from datetime import datetime, timezone


class Base(DeclarativeBase):
    pass


class Release(Base):
    __tablename__ = "bsmart_content_releases"
    revision: Mapped[str] = mapped_column(String, primary_key=True)
    manifest: Mapped[dict] = mapped_column(JSON)
    provenance: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Page(Base):
    __tablename__ = "bsmart_content_pages"
    revision: Mapped[str] = mapped_column(ForeignKey(Release.revision), primary_key=True)
    collection: Mapped[str] = mapped_column(String, primary_key=True)
    owner: Mapped[str] = mapped_column(String, primary_key=True)
    page: Mapped[int] = mapped_column(Integer, primary_key=True)
    payload: Mapped[dict] = mapped_column(JSON)


class Active(Base):
    __tablename__ = "bsmart_content_active"
    channel: Mapped[str] = mapped_column(String, primary_key=True)
    revision: Mapped[str] = mapped_column(ForeignKey(Release.revision))
    activated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
