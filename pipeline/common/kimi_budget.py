"""Cross-process, conservative CNY reservations for explicitly budgeted Kimi runs."""
from __future__ import annotations

import fcntl
import json
import os
import uuid
from contextlib import contextmanager
from decimal import Decimal
from pathlib import Path

UNIT = 1_000_000_000  # integer nanoyuan, avoiding floating-point budget drift


class BudgetExceeded(RuntimeError):
    pass


class BudgetLedger:
    def __init__(self, path: Path, cap_cny: str):
        self.path = path
        self.cap = int(Decimal(cap_cny) * UNIT)
        if self.cap <= 0:
            raise ValueError("Kimi budget must be positive")

    @contextmanager
    def locked(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.with_suffix(".lock").open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                state = json.loads(self.path.read_text()) if self.path.exists() else {
                    "cap_nanoyuan": self.cap, "spent_nanoyuan": 0,
                    "reservations": {}, "requests": [],
                }
                if state["cap_nanoyuan"] != self.cap:
                    raise ValueError("Existing budget cap cannot be changed implicitly")
                yield state
                temporary = self.path.with_suffix(".tmp")
                temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
                os.replace(temporary, self.path)
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)

    def reserve(self, maximum: int) -> str:
        with self.locked() as state:
            used = state["spent_nanoyuan"] + sum(state["reservations"].values())
            if maximum < 0 or used + maximum > self.cap:
                raise BudgetExceeded("Kimi run budget cannot cover the next request")
            request_id = uuid.uuid4().hex
            state["reservations"][request_id] = maximum
            return request_id

    def finish(self, request_id: str, cost: int, metadata: dict) -> None:
        with self.locked() as state:
            reserved = state["reservations"].pop(request_id)
            state["spent_nanoyuan"] += cost
            state["requests"].append({"id": request_id, "cost_nanoyuan": cost, **metadata})
            exceeded = cost > reserved or state["spent_nanoyuan"] > self.cap
        if exceeded:
            raise BudgetExceeded("Provider usage exceeded its reservation; stop and audit pricing")

    def abandon(self, request_id: str, *, uncertain: bool) -> None:
        with self.locked() as state:
            maximum = state["reservations"].pop(request_id)
            if uncertain:
                # An ambiguous timeout may have been billed. Keep its full bound.
                state["spent_nanoyuan"] += maximum
            state["requests"].append({"id": request_id, "uncertain": uncertain,
                                      "cost_nanoyuan": maximum if uncertain else 0})
