"""TwitterAPI.io implementation of the realtime provider boundary."""
from __future__ import annotations

import time
from datetime import UTC, datetime
from typing import Any

import requests

from .provider import ProviderRule


class TwitterAPIIOError(RuntimeError):
    pass


class TwitterAPIIOProvider:
    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = "https://api.twitterapi.io",
        timeout_seconds: float = 30.0,
        max_retries: int = 4,
    ):
        if not api_key.strip():
            raise ValueError("TWITTERAPI_IO_KEY is required")
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds
        self.max_retries = max(1, max_retries)
        self.session = requests.Session()
        self.session.headers.update({"X-API-Key": api_key, "Accept": "application/json"})

    def _request(self, method: str, path: str, **kwargs: Any) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        last_status: int | None = None
        last_body = ""
        for attempt in range(self.max_retries):
            try:
                response = self.session.request(
                    method,
                    url,
                    timeout=self.timeout_seconds,
                    **kwargs,
                )
            except requests.RequestException as exc:
                if attempt + 1 < self.max_retries:
                    time.sleep(min(30.0, 2 ** attempt))
                    continue
                raise TwitterAPIIOError(
                    f"TwitterAPI.io {method} {path} failed after retries: {exc}"
                ) from exc
            if response.status_code < 400:
                try:
                    payload = response.json()
                except ValueError as exc:
                    raise TwitterAPIIOError(
                        f"TwitterAPI.io {method} {path} returned invalid JSON"
                    ) from exc
                if isinstance(payload, dict) and payload.get("status") == "error":
                    raise TwitterAPIIOError(str(payload.get("message") or payload.get("msg") or payload))
                return payload if isinstance(payload, dict) else {}
            last_status = response.status_code
            last_body = response.text[:300]
            if response.status_code != 429 and response.status_code < 500:
                raise TwitterAPIIOError(
                    f"TwitterAPI.io {method} {path} returned {response.status_code}: {response.text[:300]}"
                )
            retry_after = response.headers.get("Retry-After")
            delay = float(retry_after) if retry_after and retry_after.isdigit() else min(30.0, 2 ** attempt)
            if attempt + 1 < self.max_retries:
                time.sleep(delay)
        suffix = f"; last response {last_status}: {last_body}" if last_status else ""
        raise TwitterAPIIOError(
            f"TwitterAPI.io {method} {path} exhausted retries{suffix}"
        )

    def list_rules(self) -> list[ProviderRule]:
        payload = self._request("GET", "/oapi/tweet_filter/get_rules")
        rules: list[ProviderRule] = []
        for row in payload.get("rules") or []:
            if not isinstance(row, dict) or not row.get("rule_id"):
                continue
            rules.append(
                ProviderRule(
                    rule_id=str(row["rule_id"]),
                    tag=str(row.get("tag") or ""),
                    value=str(row.get("value") or ""),
                    interval_seconds=float(row.get("interval_seconds") or 60),
                    active=int(row.get("is_effect") or 0) == 1,
                )
            )
        return rules

    def add_rule(self, *, tag: str, value: str, interval_seconds: float) -> str:
        payload = self._request(
            "POST",
            "/oapi/tweet_filter/add_rule",
            json={"tag": tag, "value": value, "interval_seconds": interval_seconds},
        )
        rule_id = str(payload.get("rule_id") or "")
        if not rule_id:
            raise TwitterAPIIOError("add_rule response did not contain rule_id")
        return rule_id

    def activate_rule(
        self,
        *,
        rule_id: str,
        tag: str,
        value: str,
        interval_seconds: float,
    ) -> None:
        self._set_rule_active(
            rule_id=rule_id,
            tag=tag,
            value=value,
            interval_seconds=interval_seconds,
            active=True,
        )

    def deactivate_rule(
        self,
        *,
        rule_id: str,
        tag: str,
        value: str,
        interval_seconds: float,
    ) -> None:
        self._set_rule_active(
            rule_id=rule_id,
            tag=tag,
            value=value,
            interval_seconds=interval_seconds,
            active=False,
        )

    def _set_rule_active(
        self,
        *,
        rule_id: str,
        tag: str,
        value: str,
        interval_seconds: float,
        active: bool,
    ) -> None:
        self._request(
            "POST",
            "/oapi/tweet_filter/update_rule",
            json={
                "rule_id": rule_id,
                "tag": tag,
                "value": value,
                "interval_seconds": interval_seconds,
                "is_effect": 1 if active else 0,
            },
        )

    def delete_rule(self, rule_id: str) -> None:
        self._request(
            "DELETE",
            "/oapi/tweet_filter/delete_rule",
            json={"rule_id": rule_id},
        )

    def search_recent(
        self,
        *,
        query: str,
        since: datetime,
        until: datetime,
        max_pages: int = 20,
    ) -> list[dict[str, Any]]:
        since_epoch = int(_as_utc(since).timestamp())
        until_epoch = int(_as_utc(until).timestamp())
        request_budget = max(1, max_pages)
        request_count = 0

        def fetch_window(start: int, end: int) -> list[dict[str, Any]]:
            nonlocal request_count
            if request_count >= request_budget:
                raise TwitterAPIIOError(
                    "advanced search time-window split exhausted its request budget"
                )
            request_count += 1
            timed_query = f"({query}) since_time:{start} until_time:{end}"
            payload = self._request(
                "GET",
                "/twitter/tweet/advanced_search",
                params={"query": timed_query, "queryType": "Latest"},
            )
            rows = payload.get("tweets")
            posts = [row for row in rows or [] if isinstance(row, dict)]
            # TwitterAPI.io documents time-window splitting instead of cursor
            # pagination. In practice it can report has_next_page=true for a
            # sparse result, so only a full page proves that this window needs
            # another split.
            saturated = len(posts) >= 20
            if saturated and end - start > 1:
                midpoint = start + ((end - start) // 2)
                return fetch_window(start, midpoint) + fetch_window(midpoint, end)
            return posts

        deduplicated: dict[str, dict[str, Any]] = {}
        for post in fetch_window(since_epoch, until_epoch):
            post_id = str(post.get("id") or "")
            if post_id:
                deduplicated[post_id] = post
        return list(deduplicated.values())

    def get_posts(self, post_ids: list[str]) -> dict[str, dict[str, Any]]:
        found: dict[str, dict[str, Any]] = {}
        clean = list(dict.fromkeys(str(item) for item in post_ids if item))
        for offset in range(0, len(clean), 100):
            batch = clean[offset : offset + 100]
            payload = self._request(
                "GET",
                "/twitter/tweets",
                params={"tweet_ids": ",".join(batch)},
            )
            for row in payload.get("tweets") or []:
                if isinstance(row, dict) and row.get("id"):
                    found[str(row["id"])] = row
        return found


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
