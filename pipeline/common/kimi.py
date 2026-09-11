"""Kimi K2.6 JSON adapter with an explicit shared run budget and usage ledger."""
from __future__ import annotations

import json
import os
from pathlib import Path

import requests

from .config import settings
from .deepseek import extract_json
from .kimi_budget import BudgetLedger

# CNY per million tokens, verified 2026-09-05 against official K2.6 pricing.
# Integer nanoyuan/token: uncached input 6.50, cached input 1.10, output 27.00.
INPUT_RATE, CACHED_RATE, OUTPUT_RATE = 6500, 1100, 27000


def available() -> bool:
    return bool(settings.kimi_api_key)


def model_label() -> str:
    return "kimi:" + settings.kimi_model


def usage_cost(usage: dict) -> int:
    prompt = int(usage["prompt_tokens"])
    completion = int(usage["completion_tokens"])
    cached = int((usage.get("prompt_tokens_details") or {}).get("cached_tokens", 0))
    cached = min(prompt, max(0, cached))
    return (prompt - cached) * INPUT_RATE + cached * CACHED_RATE + completion * OUTPUT_RATE


def chat(system: str, user: str, max_tokens: int = 1200) -> str:
    if settings.kimi_model != "kimi-k2.6":
        raise ValueError("Kimi pricing must be verified before enabling another model")
    path = os.environ.get("KIMI_BUDGET_FILE")
    cap = os.environ.get("KIMI_BUDGET_CNY")
    if not path or not cap:
        raise ValueError("KIMI_BUDGET_FILE and KIMI_BUDGET_CNY are required")
    if not 1 <= max_tokens <= 32768:
        raise ValueError("Unsupported Kimi output token limit")
    ledger = BudgetLedger(Path(path), cap)
    # Text token counts cannot exceed UTF-8 byte counts; include a generous bound
    # for the fixed two-message framing. Do not assume prompt caching in advance.
    input_bound = len(system.encode()) + len(user.encode()) + 2048
    reservation = ledger.reserve(input_bound * INPUT_RATE + max_tokens * OUTPUT_RATE)
    body = {
        "model": settings.kimi_model,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "max_tokens": max_tokens, "thinking": {"type": "disabled"},
    }
    try:
        response = requests.post(
            settings.kimi_base_url.rstrip("/") + "/chat/completions", json=body,
            headers={"Authorization": "Bearer " + settings.kimi_api_key}, timeout=90,
        )
    except requests.RequestException:
        ledger.abandon(reservation, uncertain=True)
        raise RuntimeError("Kimi transport failed; reserved maximum retained") from None
    if response.status_code != 200:
        ledger.abandon(reservation, uncertain=response.status_code >= 500)
        raise RuntimeError(f"Kimi HTTP {response.status_code}; request stopped")
    try:
        data = response.json()
        usage = data["usage"]
        cost = usage_cost(usage)
    except (ValueError, KeyError, TypeError):
        ledger.abandon(reservation, uncertain=True)
        raise RuntimeError("Kimi response missing accountable usage") from None
    ledger.finish(reservation, cost, {"model": settings.kimi_model, "usage": usage})
    choice = data["choices"][0]
    if choice.get("finish_reason") == "length":
        raise RuntimeError("Kimi output truncated; billed result was not accepted")
    return choice["message"].get("content") or ""


def messages_json(system: str, user: str, max_tokens: int = 1200):
    return extract_json(chat(system, user, max_tokens=max_tokens))
