"""Build a versioned Xueqiu author discovery pool for Smart Account."""
from __future__ import annotations

import csv
import datetime as dt
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from sqlalchemy import delete, select

from ...common.db import engine, session_scope
from ...common.models import Base, XueqiuAuthorPoolCandidate, XueqiuAuthorSnapshot


PUBLISHER_NAME_MARKERS = (
    "每日经济新闻",
    "财联社",
    "快讯",
    "华尔街见闻",
    "新浪财经",
    "科创板日报",
    "中国基金报",
    "证券时报",
    "第一财经",
    "经济观察报",
    "财经网",
    "钛媒体",
    "智东西",
    "界面新闻",
    "中新经纬",
    "新华社",
    "人民网",
    "央视",
    "donews",
)


@dataclass(frozen=True)
class XueqiuPoolSummary:
    pool_version: str
    considered: int
    selected: int
    reserve: int
    publishers: int
    target_size: int
    min_followers: int
    min_statuses: int


def _to_int(value: Any) -> int:
    try:
        return int(float(value or 0))
    except (TypeError, ValueError):
        return 0


def _to_float(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def classify_author_type(
    *,
    screen_name: str,
    statuses_count: int,
    sampled_posts: int,
    sampled_tickers: int,
    snapshot_raw: dict[str, Any] | None,
) -> tuple[str, str]:
    """Conservatively separate publishers from individual investing voices."""
    normalized_name = (screen_name or "").strip().lower()
    for marker in PUBLISHER_NAME_MARKERS:
        if marker.lower() in normalized_name:
            return "publisher", f"publisher_name:{marker}"

    raw = snapshot_raw or {}
    verified_text = " ".join(
        str(value or "")
        for value in (
            raw.get("verified_description"),
            raw.get("description"),
            *[
                info.get("verified_desc")
                for info in (raw.get("verified_infos") or [])
                if isinstance(info, dict)
            ],
        )
    )
    organization_markers = ("官方账号", "官方帐号", "官方账户", "官方帐户", "新闻", "媒体")
    for marker in organization_markers:
        if marker in verified_text:
            return "publisher", f"verified_text:{marker}"

    if statuses_count >= 100_000 and sampled_posts >= 20 and sampled_tickers >= 7:
        return "publisher", "publisher_volume"
    return "creator", "creator_default"


def _latest_snapshots() -> dict[str, dict[str, Any]]:
    with session_scope() as session:
        rows = session.execute(
            select(XueqiuAuthorSnapshot).order_by(
                XueqiuAuthorSnapshot.user_id,
                XueqiuAuthorSnapshot.snapshot_date.desc(),
                XueqiuAuthorSnapshot.id.desc(),
            )
        ).scalars()
        latest: dict[str, dict[str, Any]] = {}
        for row in rows:
            latest.setdefault(
                row.user_id,
                {
                    "raw": row.raw if isinstance(row.raw, dict) else {},
                    "profile": row.profile or "",
                },
            )
    return latest


def import_discovery_pool(
    csv_path: str | Path,
    *,
    pool_version: str,
    target_size: int = 300,
    minimum_size: int = 300,
    min_followers: int = 500,
    min_statuses: int = 300,
) -> XueqiuPoolSummary:
    """Persist a discovery CSV, exclude obvious publishers, and rank creators."""
    if target_size < minimum_size:
        raise ValueError("target_size must be greater than or equal to minimum_size")
    path = Path(csv_path)
    if not path.exists():
        raise FileNotFoundError(path)

    Base.metadata.create_all(
        engine,
        tables=[XueqiuAuthorSnapshot.__table__, XueqiuAuthorPoolCandidate.__table__],
    )
    with path.open(encoding="utf-8-sig", newline="") as handle:
        source_rows = list(csv.DictReader(handle))
    snapshots = _latest_snapshots()
    candidates: list[dict[str, Any]] = []
    for source in source_rows:
        user_id = str(source.get("author_id") or "").strip()
        if not user_id:
            continue
        followers_count = _to_int(source.get("followers_count"))
        statuses_count = _to_int(source.get("statuses_count"))
        verified = bool(_to_int(source.get("verified")))
        if not (followers_count >= min_followers or verified) or statuses_count < min_statuses:
            continue
        sampled_posts = _to_int(source.get("sampled_posts"))
        sampled_tickers = _to_int(source.get("sampled_tickers"))
        author_type, type_reason = classify_author_type(
            screen_name=str(source.get("author") or ""),
            statuses_count=statuses_count,
            sampled_posts=sampled_posts,
            sampled_tickers=sampled_tickers,
            snapshot_raw=snapshots.get(user_id, {}).get("raw"),
        )
        candidates.append(
            {
                "user_id": user_id,
                "screen_name": str(source.get("author") or "")[:160],
                "discovery_rank": _to_int(source.get("pool_rank")) or None,
                "followers_count": followers_count,
                "friends_count": _to_int(source.get("friends_count")),
                "statuses_count": statuses_count,
                "verified": verified,
                "sampled_posts": sampled_posts,
                "sampled_tickers": sampled_tickers,
                "discovery_score": _to_float(source.get("discovery_score")),
                "author_type": author_type,
                "type_reason": type_reason,
            }
        )

    creators = sorted(
        (row for row in candidates if row["author_type"] == "creator"),
        key=lambda row: (
            -row["discovery_score"],
            -row["sampled_tickers"],
            -row["sampled_posts"],
            -row["followers_count"],
            row["user_id"],
        ),
    )
    if len(creators) < minimum_size:
        raise ValueError(f"creator candidates below minimum: {len(creators)} < {minimum_size}")
    rank_by_user = {row["user_id"]: rank for rank, row in enumerate(creators, 1)}
    now = dt.datetime.utcnow()

    with session_scope() as session:
        session.execute(
            delete(XueqiuAuthorPoolCandidate).where(
                XueqiuAuthorPoolCandidate.pool_version == pool_version
            )
        )
        for row in candidates:
            rank = rank_by_user.get(row["user_id"])
            selected = row["author_type"] == "creator" and rank is not None and rank <= target_size
            if row["author_type"] == "publisher":
                pool_status = "publisher"
            elif selected:
                pool_status = "selected"
            else:
                pool_status = "reserve"
            session.add(
                XueqiuAuthorPoolCandidate(
                    pool_version=pool_version,
                    pool_rank=rank,
                    pool_status=pool_status,
                    selected=selected,
                    created_at=now,
                    updated_at=now,
                    **row,
                )
            )

    selected = min(target_size, len(creators))
    return XueqiuPoolSummary(
        pool_version=pool_version,
        considered=len(candidates),
        selected=selected,
        reserve=max(0, len(creators) - selected),
        publishers=len(candidates) - len(creators),
        target_size=target_size,
        min_followers=min_followers,
        min_statuses=min_statuses,
    )
