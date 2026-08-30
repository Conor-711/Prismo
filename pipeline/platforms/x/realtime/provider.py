"""Provider boundary for realtime X collection."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol


@dataclass(frozen=True)
class ProviderRule:
    rule_id: str
    tag: str
    value: str
    interval_seconds: float
    active: bool


class TweetProvider(Protocol):
    def list_rules(self) -> list[ProviderRule]: ...

    def add_rule(self, *, tag: str, value: str, interval_seconds: float) -> str: ...

    def activate_rule(
        self,
        *,
        rule_id: str,
        tag: str,
        value: str,
        interval_seconds: float,
    ) -> None: ...

    def deactivate_rule(
        self,
        *,
        rule_id: str,
        tag: str,
        value: str,
        interval_seconds: float,
    ) -> None: ...

    def delete_rule(self, rule_id: str) -> None: ...

    def search_recent(
        self,
        *,
        query: str,
        since: datetime,
        until: datetime,
        max_pages: int = 20,
    ) -> list[dict[str, Any]]: ...

    def get_posts(self, post_ids: list[str]) -> dict[str, dict[str, Any]]: ...
