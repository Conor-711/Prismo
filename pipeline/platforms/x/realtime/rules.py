"""Deterministic TwitterAPI.io rule construction."""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass


HANDLE_RE = re.compile(r"^[A-Za-z0-9_]{1,15}$")


@dataclass(frozen=True)
class DesiredRule:
    key: str
    tag: str
    value: str
    handles: tuple[str, ...]


def build_rules(
    handles: list[str] | tuple[str, ...],
    *,
    pool_version: str,
    max_value_length: int = 255,
) -> list[DesiredRule]:
    """Pack ``from:handle`` terms without exceeding the provider limit."""
    clean = sorted(
        {
            handle.strip().lstrip("@").lower()
            for handle in handles
            if HANDLE_RE.fullmatch(handle.strip().lstrip("@"))
        }
    )
    groups: list[list[str]] = []
    current: list[str] = []
    for handle in clean:
        candidate = current + [handle]
        value = " OR ".join(f"from:{item}" for item in candidate)
        if current and len(value) > max_value_length:
            groups.append(current)
            current = [handle]
        else:
            current = candidate
    if current:
        groups.append(current)

    version_hash = hashlib.sha256(pool_version.encode("utf-8")).hexdigest()[:10]
    rules: list[DesiredRule] = []
    for index, group in enumerate(groups, start=1):
        value = " OR ".join(f"from:{item}" for item in group)
        content_hash = hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]
        key = f"{version_hash}-{index:03d}-{content_hash}"
        rules.append(
            DesiredRule(
                key=key,
                tag=f"bsmart-x-{version_hash}-{index:03d}",
                value=value,
                handles=tuple(group),
            )
        )
    return rules
