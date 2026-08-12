from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable, Protocol

from sqlalchemy import DateTime, Integer, String, Text, create_engine, delete, select, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from services.client_api.config import normalize_database_url


READ_MODEL_COLLECTIONS = (
    "portfolio-signals",
    "smart-account-updates",
    "smart-account-evidence",
    "smart-money-movements",
    "ticker-intelligence",
    "smart-accounts",
    "smart-money",
    "events",
    "research",
)


class ReadModelBase(DeclarativeBase):
    pass


class ReadModelDocument(ReadModelBase):
    __tablename__ = "client_read_model_document"

    collection: Mapped[str] = mapped_column(String(64), primary_key=True)
    document_id: Mapped[str] = mapped_column(String(160), primary_key=True)
    ticker: Mapped[str | None] = mapped_column(String(16), nullable=True, index=True)
    sort_order: Mapped[int] = mapped_column(Integer)
    payload_json: Mapped[str] = mapped_column(Text)
    producer: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class RealtimeReadModelCollection(ReadModelBase):
    __tablename__ = "client_realtime_read_model_collection"

    collection: Mapped[str] = mapped_column(String(64), primary_key=True)
    source_version: Mapped[str] = mapped_column(String(160))
    schema_version: Mapped[str] = mapped_column(String(32))
    content_hash: Mapped[str] = mapped_column(String(64))
    document_count: Mapped[int] = mapped_column(Integer)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class ReadModelRelease(ReadModelBase):
    __tablename__ = "client_read_model_release"

    release_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    source_version: Mapped[str] = mapped_column(String(160))
    schema_version: Mapped[str] = mapped_column(String(32))
    content_hash: Mapped[str] = mapped_column(String(64), unique=True)
    collection_hashes_json: Mapped[str] = mapped_column(Text)
    document_count: Mapped[int] = mapped_column(Integer)
    published_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class ActiveReadModelRelease(ReadModelBase):
    __tablename__ = "client_read_model_active_release"

    channel: Mapped[str] = mapped_column(String(32), primary_key=True)
    release_id: Mapped[str] = mapped_column(String(64), index=True)
    activated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class VersionedReadModelDocument(ReadModelBase):
    __tablename__ = "client_read_model_release_document"

    release_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    collection: Mapped[str] = mapped_column(String(64), primary_key=True)
    document_id: Mapped[str] = mapped_column(String(160), primary_key=True)
    ticker: Mapped[str | None] = mapped_column(String(16), nullable=True, index=True)
    sort_order: Mapped[int] = mapped_column(Integer)
    payload_json: Mapped[str] = mapped_column(Text)


@dataclass(frozen=True)
class ReadModelPublishResult:
    release_id: str
    content_hash: str
    document_count: int
    counts: dict[str, int]
    existing: bool


@dataclass(frozen=True)
class RealtimeReadModelPublishResult:
    content_hashes: dict[str, str]
    counts: dict[str, int]
    updated_at: datetime


class ReadModelRepository(Protocol):
    def portfolio_signals(self) -> list[dict[str, Any]]: ...

    def smart_account_updates(self) -> list[dict[str, Any]]: ...

    def smart_account_evidence(self, account_id: str) -> list[dict[str, Any]]: ...

    def smart_money_movements(self) -> list[dict[str, Any]]: ...

    def ticker_intelligence(self) -> list[dict[str, Any]]: ...

    def smart_accounts(self) -> list[dict[str, Any]]: ...

    def smart_money(self) -> list[dict[str, Any]]: ...

    def legacy_events(self) -> list[dict[str, Any]]: ...

    def legacy_research(self) -> list[dict[str, Any]]: ...

    def signal(self, signal_id: str) -> dict[str, Any] | None: ...

    def current_price(self, ticker: str) -> float: ...

    def etag(self, collection: str) -> str: ...

    def updated_at(self, collection: str) -> datetime | None: ...

    def dispose(self) -> None: ...


class FixtureReadModelRepository:
    """Development-only read model backed by versioned contract fixtures."""

    def __init__(self, fixture_root: Path):
        self.fixture_root = fixture_root

    def portfolio_signals(self) -> list[dict[str, Any]]:
        return self._load("portfolio-signals")

    def smart_account_updates(self) -> list[dict[str, Any]]:
        return self._load("smart-account-updates")

    def smart_account_evidence(self, account_id: str) -> list[dict[str, Any]]:
        return [
            item for item in self._load("smart-account-evidence")
            if item.get("authorId") == account_id
        ]

    def smart_money_movements(self) -> list[dict[str, Any]]:
        return self._load("smart-money-movements")

    def ticker_intelligence(self) -> list[dict[str, Any]]:
        return self._load("ticker-intelligence")

    def smart_accounts(self) -> list[dict[str, Any]]:
        return self._load("smart-accounts")

    def smart_money(self) -> list[dict[str, Any]]:
        return self._load("smart-money")

    def legacy_events(self) -> list[dict[str, Any]]:
        return self._load("events")

    def legacy_research(self) -> list[dict[str, Any]]:
        return self._load("research")

    def signal(self, signal_id: str) -> dict[str, Any] | None:
        return next((item for item in self.portfolio_signals() if item.get("id") == signal_id), None)

    def current_price(self, ticker: str) -> float:
        normalized = ticker.upper()
        item = next(
            (item for item in self.ticker_intelligence() if item.get("ticker", "").upper() == normalized),
            None,
        )
        return float(item.get("currentPrice", 0)) if item else 0

    def etag(self, collection: str) -> str:
        return _collection_hash(self._load(collection))

    def updated_at(self, collection: str) -> datetime | None:
        path = self.fixture_root / f"{collection}.json"
        return datetime.fromtimestamp(path.stat().st_mtime, tz=UTC) if path.exists() else None

    def dispose(self) -> None:
        return None

    def _load(self, name: str) -> list[dict[str, Any]]:
        path = self.fixture_root / f"{name}.json"
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        if not isinstance(payload, list):
            raise RuntimeError(f"Fixture {path} must contain a JSON array.")
        return payload


class DatabaseReadModelRepository:
    """Read-only contract documents published by a separate materialization job."""

    def __init__(self, database_url: str):
        self.engine = _create_engine(database_url)
        self.session_factory = sessionmaker(self.engine, expire_on_commit=False)
        ReadModelBase.metadata.create_all(self.engine)

    def portfolio_signals(self) -> list[dict[str, Any]]:
        return self._collection("portfolio-signals")

    def smart_account_updates(self) -> list[dict[str, Any]]:
        return self._collection("smart-account-updates")

    def smart_account_evidence(self, account_id: str) -> list[dict[str, Any]]:
        return [
            item for item in self._collection("smart-account-evidence")
            if item.get("authorId") == account_id
        ]

    def smart_money_movements(self) -> list[dict[str, Any]]:
        return self._collection("smart-money-movements")

    def ticker_intelligence(self) -> list[dict[str, Any]]:
        return self._collection("ticker-intelligence")

    def smart_accounts(self) -> list[dict[str, Any]]:
        return self._collection("smart-accounts")

    def smart_money(self) -> list[dict[str, Any]]:
        return self._collection("smart-money")

    def legacy_events(self) -> list[dict[str, Any]]:
        return self._collection("events")

    def legacy_research(self) -> list[dict[str, Any]]:
        return self._collection("research")

    def signal(self, signal_id: str) -> dict[str, Any] | None:
        with self.session_factory() as session:
            if session.get(RealtimeReadModelCollection, "portfolio-signals") is not None:
                record = session.get(ReadModelDocument, ("portfolio-signals", signal_id))
                return _decode_document(record) if record else None
            release_id = _active_release_id(session)
            if release_id:
                record = session.get(
                    VersionedReadModelDocument,
                    (release_id, "portfolio-signals", signal_id),
                )
                return _decode_versioned_document(record) if record else None
            record = session.get(ReadModelDocument, ("portfolio-signals", signal_id))
            return _decode_document(record) if record else None

    def current_price(self, ticker: str) -> float:
        with self.session_factory() as session:
            if session.get(RealtimeReadModelCollection, "ticker-intelligence") is not None:
                record = session.scalar(
                    select(ReadModelDocument).where(
                        ReadModelDocument.collection == "ticker-intelligence",
                        ReadModelDocument.ticker == ticker.upper(),
                    )
                )
                payload = _decode_document(record) if record else {}
            elif release_id := _active_release_id(session):
                record = session.scalar(
                    select(VersionedReadModelDocument).where(
                        VersionedReadModelDocument.release_id == release_id,
                        VersionedReadModelDocument.collection == "ticker-intelligence",
                        VersionedReadModelDocument.ticker == ticker.upper(),
                    )
                )
                payload = _decode_versioned_document(record) if record else {}
            else:
                record = session.scalar(
                    select(ReadModelDocument).where(
                        ReadModelDocument.collection == "ticker-intelligence",
                        ReadModelDocument.ticker == ticker.upper(),
                    )
                )
                payload = _decode_document(record) if record else {}
            return float(payload.get("currentPrice", 0))

    def etag(self, collection: str) -> str:
        with self.session_factory() as session:
            realtime = session.get(RealtimeReadModelCollection, collection)
            if realtime is not None:
                return realtime.content_hash
            release_id = _active_release_id(session)
            if release_id:
                release = session.get(ReadModelRelease, release_id)
                if release:
                    hashes = json.loads(release.collection_hashes_json)
                    if collection in hashes:
                        return str(hashes[collection])
            records = session.scalars(
                select(ReadModelDocument)
                .where(ReadModelDocument.collection == collection)
                .order_by(ReadModelDocument.sort_order)
            )
            return _payload_hashes_etag(record.payload_json for record in records)

    def updated_at(self, collection: str) -> datetime | None:
        with self.session_factory() as session:
            realtime = session.get(RealtimeReadModelCollection, collection)
            if realtime is not None:
                value = realtime.updated_at
            else:
                release_id = _active_release_id(session)
                release = session.get(ReadModelRelease, release_id) if release_id else None
                value = release.published_at if release is not None else None
            if value is not None and value.tzinfo is None:
                return value.replace(tzinfo=UTC)
            return value

    def dispose(self) -> None:
        self.engine.dispose()

    def _collection(self, name: str) -> list[dict[str, Any]]:
        with self.session_factory() as session:
            if session.get(RealtimeReadModelCollection, name) is not None:
                records = session.scalars(
                    select(ReadModelDocument)
                    .where(ReadModelDocument.collection == name)
                    .order_by(ReadModelDocument.sort_order)
                )
                return [_decode_document(record) for record in records]
            release_id = _active_release_id(session)
            if release_id:
                records = session.scalars(
                    select(VersionedReadModelDocument)
                    .where(
                        VersionedReadModelDocument.release_id == release_id,
                        VersionedReadModelDocument.collection == name,
                    )
                    .order_by(VersionedReadModelDocument.sort_order)
                )
                return [_decode_versioned_document(record) for record in records]
            records = session.scalars(
                select(ReadModelDocument)
                .where(ReadModelDocument.collection == name)
                .order_by(ReadModelDocument.sort_order)
            )
            return [_decode_document(record) for record in records]


class ReadModelPublisher:
    """Publishes complete immutable snapshots and atomically activates them."""

    def __init__(self, database_url: str, *, channel: str = "production"):
        self.engine = _create_engine(database_url)
        self.channel = channel
        ReadModelBase.metadata.create_all(self.engine)

    def publish(
        self,
        collections: dict[str, list[dict[str, Any]]],
        *,
        source_version: str,
        schema_version: str = "1.3.0",
    ) -> ReadModelPublishResult:
        if not source_version.strip():
            raise ValueError("Read model source_version must not be empty.")
        normalized = _validate_release_collections(collections)
        collection_hashes = {
            collection: _collection_hash(normalized[collection])
            for collection in READ_MODEL_COLLECTIONS
        }
        serialized_release = json.dumps(
            normalized,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        content_hash = hashlib.sha256(serialized_release.encode("utf-8")).hexdigest()
        release_id = content_hash
        now = datetime.now(UTC)
        document_count = sum(len(items) for items in normalized.values())

        with Session(self.engine) as session, session.begin():
            existing = session.get(ReadModelRelease, release_id) is not None
            if not existing:
                session.add(ReadModelRelease(
                    release_id=release_id,
                    source_version=source_version,
                    schema_version=schema_version,
                    content_hash=content_hash,
                    collection_hashes_json=json.dumps(
                        collection_hashes,
                        sort_keys=True,
                        separators=(",", ":"),
                    ),
                    document_count=document_count,
                    published_at=now,
                ))
                for collection in READ_MODEL_COLLECTIONS:
                    for index, item in enumerate(normalized[collection]):
                        session.add(VersionedReadModelDocument(
                            release_id=release_id,
                            collection=collection,
                            document_id=_document_id(item, index),
                            ticker=_ticker(item),
                            sort_order=index,
                            payload_json=json.dumps(
                                item,
                                ensure_ascii=False,
                                sort_keys=True,
                                separators=(",", ":"),
                            ),
                        ))

            pointer = session.get(ActiveReadModelRelease, self.channel)
            if pointer is None:
                session.add(ActiveReadModelRelease(
                    channel=self.channel,
                    release_id=release_id,
                    activated_at=now,
                ))
            else:
                pointer.release_id = release_id
                pointer.activated_at = now

        return ReadModelPublishResult(
            release_id=release_id,
            content_hash=content_hash,
            document_count=document_count,
            counts={key: len(value) for key, value in normalized.items()},
            existing=existing,
        )

    def activate(self, release_id: str) -> None:
        now = datetime.now(UTC)
        with Session(self.engine) as session, session.begin():
            if session.get(ReadModelRelease, release_id) is None:
                raise ValueError(f"Unknown read model release: {release_id}")
            pointer = session.get(ActiveReadModelRelease, self.channel)
            if pointer is None:
                session.add(ActiveReadModelRelease(
                    channel=self.channel,
                    release_id=release_id,
                    activated_at=now,
                ))
            else:
                pointer.release_id = release_id
                pointer.activated_at = now

    def dispose(self) -> None:
        self.engine.dispose()


class RealtimeReadModelPublisher:
    """Atomically replace high-frequency collections without cloning a release."""

    def __init__(self, database_url: str):
        self.engine = _create_engine(database_url)
        ReadModelBase.metadata.create_all(self.engine)

    def publish(
        self,
        collections: dict[str, list[dict[str, Any]]],
        *,
        source_version: str,
        schema_version: str = "1.4.0",
    ) -> RealtimeReadModelPublishResult:
        if not source_version.strip():
            raise ValueError("Realtime source_version must not be empty.")
        if not collections:
            raise ValueError("At least one realtime collection is required.")
        unexpected = set(collections) - set(READ_MODEL_COLLECTIONS)
        if unexpected:
            raise ValueError(f"Unknown realtime collections: {sorted(unexpected)}")

        normalized: dict[str, list[dict[str, Any]]] = {}
        for collection, items in collections.items():
            if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
                raise ValueError(f"Read model collection {collection} must be an object array.")
            ids = [_document_id(item, index) for index, item in enumerate(items)]
            if len(ids) != len(set(ids)):
                raise ValueError(f"Read model collection {collection} contains duplicate document IDs.")
            normalized[collection] = items

        now = datetime.now(UTC)
        hashes = {name: _collection_hash(items) for name, items in normalized.items()}
        with Session(self.engine) as session, session.begin():
            for collection, items in normalized.items():
                session.execute(
                    delete(ReadModelDocument).where(ReadModelDocument.collection == collection)
                )
                for index, item in enumerate(items):
                    session.add(ReadModelDocument(
                        collection=collection,
                        document_id=_document_id(item, index),
                        ticker=_ticker(item),
                        sort_order=index,
                        payload_json=json.dumps(
                            item,
                            ensure_ascii=False,
                            sort_keys=True,
                            separators=(",", ":"),
                        ),
                        producer=None,
                        updated_at=now,
                    ))
                marker = session.get(RealtimeReadModelCollection, collection)
                if marker is None:
                    session.add(RealtimeReadModelCollection(
                        collection=collection,
                        source_version=source_version,
                        schema_version=schema_version,
                        content_hash=hashes[collection],
                        document_count=len(items),
                        updated_at=now,
                    ))
                else:
                    marker.source_version = source_version
                    marker.schema_version = schema_version
                    marker.content_hash = hashes[collection]
                    marker.document_count = len(items)
                    marker.updated_at = now
        return RealtimeReadModelPublishResult(
            content_hashes=hashes,
            counts={name: len(items) for name, items in normalized.items()},
            updated_at=now,
        )

    def publish_partitioned(
        self,
        collections: dict[str, list[dict[str, Any]]],
        *,
        producer: str,
        source_version: str,
        schema_version: str = "1.4.0",
        owns_document: Callable[[str, dict[str, Any]], bool] | None = None,
    ) -> RealtimeReadModelPublishResult:
        """Replace one producer's documents while retaining other live and base data."""
        producer = producer.strip()
        if not producer:
            raise ValueError("Realtime producer must not be empty.")
        if not source_version.strip():
            raise ValueError("Realtime source_version must not be empty.")
        if not collections:
            raise ValueError("At least one realtime collection is required.")
        unexpected = set(collections) - set(READ_MODEL_COLLECTIONS)
        if unexpected:
            raise ValueError(f"Unknown realtime collections: {sorted(unexpected)}")
        for collection, items in collections.items():
            if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
                raise ValueError(f"Read model collection {collection} must be an object array.")
            ids = [_document_id(item, index) for index, item in enumerate(items)]
            if len(ids) != len(set(ids)):
                raise ValueError(f"Read model collection {collection} contains duplicate document IDs.")

        now = datetime.now(UTC)
        combined_hashes: dict[str, str] = {}
        combined_counts: dict[str, int] = {}
        with Session(self.engine) as session, session.begin():
            for collection, incoming in collections.items():
                if self.engine.dialect.name == "postgresql":
                    session.execute(
                        text("SELECT pg_advisory_xact_lock(hashtext(:lock_key))"),
                        {"lock_key": f"bsmart-read-model:{collection}"},
                    )
                marker = session.get(RealtimeReadModelCollection, collection)
                if marker is not None and self.engine.dialect.name == "postgresql":
                    marker = session.scalar(
                        select(RealtimeReadModelCollection)
                        .where(RealtimeReadModelCollection.collection == collection)
                        .with_for_update()
                    )

                retained: list[tuple[dict[str, Any], str | None]] = []
                if marker is not None:
                    prior_default_producer = _producer_from_source_version(marker.source_version)
                    records = list(
                        session.scalars(
                            select(ReadModelDocument)
                            .where(ReadModelDocument.collection == collection)
                            .order_by(ReadModelDocument.sort_order)
                        )
                    )
                    for record in records:
                        record_producer = record.producer or prior_default_producer
                        payload = _decode_document(record)
                        owned = bool(owns_document and owns_document(collection, payload))
                        if record_producer is not None and record_producer != producer and not owned:
                            retained.append((payload, record_producer))
                retained.extend(
                    (item, None)
                    for item in _base_collection(session, collection)
                    if not (owns_document and owns_document(collection, item))
                )

                combined: list[tuple[dict[str, Any], str | None]] = []
                seen_ids: set[str] = set()
                for index, (item, item_producer) in enumerate(
                    [(item, producer) for item in incoming] + retained
                ):
                    document_id = _document_id(item, index)
                    if document_id in seen_ids:
                        continue
                    seen_ids.add(document_id)
                    combined.append((item, item_producer))

                session.execute(
                    delete(ReadModelDocument).where(ReadModelDocument.collection == collection)
                )
                for index, (item, item_producer) in enumerate(combined):
                    session.add(ReadModelDocument(
                        collection=collection,
                        document_id=_document_id(item, index),
                        ticker=_ticker(item),
                        sort_order=index,
                        payload_json=json.dumps(
                            item,
                            ensure_ascii=False,
                            sort_keys=True,
                            separators=(",", ":"),
                        ),
                        producer=item_producer,
                        updated_at=now,
                    ))

                items_only = [item for item, _ in combined]
                content_hash = _collection_hash(items_only)
                combined_hashes[collection] = content_hash
                combined_counts[collection] = len(items_only)
                marker_source = f"partitioned:{producer}:{source_version}"
                if marker is None:
                    session.add(RealtimeReadModelCollection(
                        collection=collection,
                        source_version=marker_source,
                        schema_version=schema_version,
                        content_hash=content_hash,
                        document_count=len(items_only),
                        updated_at=now,
                    ))
                else:
                    marker.source_version = marker_source
                    marker.schema_version = schema_version
                    marker.content_hash = content_hash
                    marker.document_count = len(items_only)
                    marker.updated_at = now

        return RealtimeReadModelPublishResult(
            content_hashes=combined_hashes,
            counts=combined_counts,
            updated_at=now,
        )

    def clear(self, *collections: str) -> None:
        with Session(self.engine) as session, session.begin():
            for collection in collections:
                session.execute(
                    delete(ReadModelDocument).where(ReadModelDocument.collection == collection)
                )
                marker = session.get(RealtimeReadModelCollection, collection)
                if marker is not None:
                    session.delete(marker)

    def dispose(self) -> None:
        self.engine.dispose()


def materialize_fixture_read_models(database_url: str, fixture_root: Path) -> dict[str, int]:
    """Development seed path; production publishers write the same document boundary."""

    collections = {
        collection: _load_fixture_collection(fixture_root, collection)
        for collection in READ_MODEL_COLLECTIONS
    }
    publisher = ReadModelPublisher(database_url, channel="development")
    try:
        result = publisher.publish(
            collections,
            source_version="contract-fixtures",
        )
    finally:
        publisher.dispose()
    return result.counts


def _create_engine(database_url: str):
    database_url = normalize_database_url(database_url)
    if database_url.startswith("sqlite:///"):
        database_path = Path(database_url.removeprefix("sqlite:///"))
        if str(database_path) != ":memory:":
            database_path.parent.mkdir(parents=True, exist_ok=True)
    connect_args = (
        {"check_same_thread": False}
        if database_url.startswith("sqlite")
        else {"prepare_threshold": None}
    )
    return create_engine(database_url, pool_pre_ping=True, connect_args=connect_args)


def _load_fixture_collection(fixture_root: Path, collection: str) -> list[dict[str, Any]]:
    path = fixture_root / f"{collection}.json"
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, list) or any(not isinstance(item, dict) for item in payload):
        raise RuntimeError(f"Fixture {path} must contain a JSON object array.")
    return payload


def load_read_model_directory(input_dir: Path) -> dict[str, list[dict[str, Any]]]:
    return {
        collection: _load_fixture_collection(input_dir, collection)
        for collection in READ_MODEL_COLLECTIONS
    }


def _validate_release_collections(
    collections: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    missing = set(READ_MODEL_COLLECTIONS) - set(collections)
    unexpected = set(collections) - set(READ_MODEL_COLLECTIONS)
    if missing or unexpected:
        raise ValueError(
            f"Read model snapshot collections mismatch; missing={sorted(missing)}, "
            f"unexpected={sorted(unexpected)}"
        )

    normalized: dict[str, list[dict[str, Any]]] = {}
    for collection in READ_MODEL_COLLECTIONS:
        items = collections[collection]
        if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
            raise ValueError(f"Read model collection {collection} must be an object array.")
        ids = [_document_id(item, index) for index, item in enumerate(items)]
        if len(ids) != len(set(ids)):
            raise ValueError(f"Read model collection {collection} contains duplicate document IDs.")
        normalized[collection] = items
    return normalized


def _document_id(item: dict[str, Any], index: int) -> str:
    for key in ("id", "ticker", "accountId", "authorId"):
        if item.get(key):
            return str(item[key])
    return str(index)


def _ticker(item: dict[str, Any]) -> str | None:
    value = item.get("ticker")
    return str(value).upper() if value else None


def _decode_document(record: ReadModelDocument) -> dict[str, Any]:
    payload = json.loads(record.payload_json)
    if not isinstance(payload, dict):
        raise RuntimeError(f"Read model document {record.collection}/{record.document_id} is invalid.")
    return payload


def _decode_versioned_document(record: VersionedReadModelDocument) -> dict[str, Any]:
    payload = json.loads(record.payload_json)
    if not isinstance(payload, dict):
        raise RuntimeError(
            f"Read model document {record.release_id}/{record.collection}/{record.document_id} is invalid."
        )
    return payload


def _active_release_id(session: Session, channel: str = "production") -> str | None:
    pointer = session.get(ActiveReadModelRelease, channel)
    if pointer is not None:
        return pointer.release_id
    development_pointer = session.get(ActiveReadModelRelease, "development")
    return development_pointer.release_id if development_pointer else None


def _base_collection(session: Session, collection: str) -> list[dict[str, Any]]:
    release_id = _active_release_id(session)
    if release_id:
        records = session.scalars(
            select(VersionedReadModelDocument)
            .where(
                VersionedReadModelDocument.release_id == release_id,
                VersionedReadModelDocument.collection == collection,
            )
            .order_by(VersionedReadModelDocument.sort_order)
        )
        return [_decode_versioned_document(record) for record in records]
    records = session.scalars(
        select(ReadModelDocument)
        .where(ReadModelDocument.collection == collection)
        .order_by(ReadModelDocument.sort_order)
    )
    return [_decode_document(record) for record in records]


def _producer_from_source_version(source_version: str) -> str | None:
    if source_version.startswith("partitioned:"):
        return None
    if source_version.startswith("hyperliquid-live"):
        return "hyperliquid-live"
    if source_version.startswith("x-realtime"):
        return "x-realtime"
    return None


def _collection_hash(items: list[dict[str, Any]]) -> str:
    payload = json.dumps(
        items,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _payload_hashes_etag(payloads: Any) -> str:
    digest = hashlib.sha256()
    for payload in payloads:
        digest.update(str(payload).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()
