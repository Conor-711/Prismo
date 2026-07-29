"""Second-pass ownership and intent audit for Private Telegram calls."""
from __future__ import annotations

import concurrent.futures
import re
import sqlite3
from typing import Any

from .v0_impl import (
    sv_extract_messages_json,
    sv_extract_model_label,
    sv_extract_provider_available,
    sv_extract_provider_order,
)


PRIVATE_TELEGRAM_AUDIT_VERSION = "private-telegram-audit-v2"
PRIVATE_TELEGRAM_AUDIT_SYSTEM = (
    "You are the final evidence auditor for an investment-call scoring system. "
    "The input is a Telegram channel post and a previously accepted ticker call. "
    "Return strict JSON only: "
    '{"keep":boolean,"direction":"bull|bear|neutral",'
    '"evidence_span":"exact verbatim quote","reason":"short reason"}. '
    "Keep only the channel owner's real forward-looking investment view, actual "
    "position action, explicit hold, or directional risk management for the specified "
    "ticker. Reject course/webinar announcements, promises to post analysis later, "
    "questions without an answer, giveaways/referral campaigns, broker reward mechanics, "
    "educational or hypothetical trades, third-party views, price celebrations, and past "
    "performance recaps. Basket calls are valid only when the direction clearly applies "
    "to that ticker. The evidence quote must itself prove direction and investment intent; "
    "a ticker name, price, or phrase such as 'will share thoughts tomorrow' is insufficient. "
    "For options, score the underlying: sell put=bull, buy put=bear; closing an old option "
    "without a new view does not create a fresh opposite call."
)
PROMOTION_RE = re.compile(
    r"\b(webull|moomoo|referral|free shares?|stock reward|credited|sign[- ]?up bonus|"
    r"deposit\s+\$?\d+|withdraw everything|eligible for the free)\b",
    re.IGNORECASE,
)
BULL_EVIDENCE_RE = re.compile(
    r"\b(bull(?:ish)?|buy|bought|add(?:ed|ing)?|enter(?:ed|ing)?|long|hold(?:ing)?|"
    r"not selling|maintain(?:ing)?|allocation|position|upside|higher|outperform|"
    r"rally|rebound|growth|opportunity|attractive|compelling|target|buy[- ]the[- ]dip|"
    r"sell(?:ing)? puts?|cash[- ]secured puts?)\b",
    re.IGNORECASE,
)
BEAR_EVIDENCE_RE = re.compile(
    r"\b(bear(?:ish)?|sell(?:ing)?|sold|trim(?:med|ming)?|short(?:ing| position| thesis| setup)|buy(?:ing)? puts?|"
    r"take profits?|taking profits?|de[- ]risk|exit(?:ing)?|close(?:d|ing)?|downside|"
    r"lower|drop(?:ping)?|fall(?:ing)?|overvalued|not confident|avoid)\b",
    re.IGNORECASE,
)


def _compact(value: object) -> str:
    return " ".join(str(value or "").split())


def _verbatim(evidence: str, text: str) -> bool:
    return bool(evidence and _compact(evidence).casefold() in _compact(text).casefold())


def _direction_supported(direction: str, evidence: str, text: str) -> bool:
    compact_text = _compact(text)
    compact_evidence = _compact(evidence)
    index = compact_text.casefold().find(compact_evidence.casefold())
    if index < 0:
        return False
    context = compact_text[max(0, index - 260) : index + len(compact_evidence) + 260]
    pattern = BULL_EVIDENCE_RE if direction == "bull" else BEAR_EVIDENCE_RE
    # Bear actions are especially easy to invent from nearby retrospective
    # language. Require the quoted evidence itself to carry the bearish action.
    return bool(pattern.search(compact_evidence if direction == "bear" else context))


def _audit_prompt(row: sqlite3.Row) -> str:
    return (
        f"Ticker: {row['ticker']}\n"
        f"Previous direction: {row['current_direction']}\n"
        f"Previous evidence: {row['current_evidence']}\n"
        f"Published at: {row['created_at']}\n"
        f"Full Telegram post:\n{str(row['text'] or '')[:5000]}"
    )


def _semantic_revalidate(con: sqlite3.Connection, investor_id: str) -> int:
    rejected = 0
    for row in con.execute(
        """
        SELECT c.candidate_id,c.direction,c.evidence_span,cc.text
          FROM sv_call c
          JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
         WHERE c.source='telegram' AND c.investor_id=?
           AND c.is_actionable_call=1
           AND c.model LIKE ?
        """,
        (investor_id, f"audit:{PRIVATE_TELEGRAM_AUDIT_VERSION}:%"),
    ).fetchall():
        if _direction_supported(
            str(row["direction"]),
            str(row["evidence_span"] or ""),
            str(row["text"] or ""),
        ):
            continue
        con.execute(
            """
            UPDATE sv_call
               SET is_actionable_call=0,direction='neutral',evidence_span='',
                   exclusion_reason='audit evidence does not prove the assigned direction'
             WHERE candidate_id=?
            """,
            (row["candidate_id"],),
        )
        rejected += 1
    con.commit()
    return rejected


def audit_private_telegram_calls(
    con: sqlite3.Connection,
    *,
    investor_id: str,
    workers: int = 4,
    limit: int = 0,
    force: bool = False,
) -> dict[str, int]:
    providers = [
        provider
        for provider in sv_extract_provider_order()
        if sv_extract_provider_available(provider)
    ]
    if not providers:
        raise RuntimeError("no Smart Voice extraction provider is available")
    clauses = [
        "c.source='telegram'",
        "c.investor_id=?",
        "c.is_actionable_call=1",
    ]
    params: list[Any] = [investor_id]
    if not force:
        clauses.append("c.model NOT LIKE ?")
        params.append(f"audit:{PRIVATE_TELEGRAM_AUDIT_VERSION}:%")
    sql = f"""
        SELECT cc.*,c.direction AS current_direction,
               c.evidence_span AS current_evidence,c.model AS current_model
          FROM sv_call c
          JOIN sv_call_candidate cc ON cc.candidate_id=c.candidate_id
         WHERE {' AND '.join(clauses)}
         ORDER BY cc.candidate_rank,cc.created_at,cc.candidate_id
    """
    if limit > 0:
        sql += " LIMIT ?"
        params.append(limit)
    rows = con.execute(sql, params).fetchall()
    if not rows:
        return {
            "audited": 0,
            "kept": 0,
            "rejected": 0,
            "failed": 0,
            "semantic_rejected": _semantic_revalidate(con, investor_id),
        }

    def request(row: sqlite3.Row) -> tuple[sqlite3.Row, dict[str, Any], str]:
        text = str(row["text"] or "")
        if PROMOTION_RE.search(text):
            return row, {
                "keep": False,
                "direction": "neutral",
                "evidence_span": "",
                "reason": "broker promotion or reward mechanics, not an investment call",
            }, "deterministic"
        for provider in providers:
            for _ in range(2):
                data = sv_extract_messages_json(
                    provider,
                    PRIVATE_TELEGRAM_AUDIT_SYSTEM,
                    _audit_prompt(row),
                    420,
                )
                if isinstance(data, dict):
                    return row, data, sv_extract_model_label(provider)
        raise RuntimeError("all Smart Voice audit providers failed")

    kept = rejected = failed = 0
    buffer: list[tuple[sqlite3.Row, dict[str, Any], str]] = []

    def flush() -> None:
        nonlocal kept, rejected
        for row, audit, provider_model in buffer:
            direction = str(audit.get("direction") or "neutral").lower()
            evidence = _compact(audit.get("evidence_span"))
            keep = (
                bool(audit.get("keep"))
                and direction in {"bull", "bear"}
                and _verbatim(evidence, str(row["text"] or ""))
                and _direction_supported(
                    direction,
                    evidence,
                    str(row["text"] or ""),
                )
            )
            reason = str(audit.get("reason") or "")[:180]
            if not keep and not reason:
                reason = "private Telegram final audit rejected the call"
            model = (
                f"audit:{PRIVATE_TELEGRAM_AUDIT_VERSION}:{provider_model}|"
                f"base:{row['current_model'] or ''}"
            )[:240]
            con.execute(
                """
                UPDATE sv_call
                   SET is_actionable_call=?,direction=?,evidence_span=?,
                       exclusion_reason=?,call_owner='post_author',model=?
                 WHERE candidate_id=?
                """,
                (
                    int(keep),
                    direction if keep else "neutral",
                    evidence if keep else "",
                    "" if keep else reason,
                    model,
                    row["candidate_id"],
                ),
            )
            if keep:
                kept += 1
            else:
                rejected += 1
        con.commit()
        buffer.clear()

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futures = [pool.submit(request, row) for row in rows]
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                buffer.append(future.result())
            except Exception:
                failed += 1
            if len(buffer) >= 30:
                flush()
            if index % 100 == 0:
                print(
                    f"[private-sv-audit] {index}/{len(rows)} "
                    f"kept={kept}+buffer{len(buffer)} rejected={rejected} failed={failed}",
                    flush=True,
                )
    flush()
    semantic_rejected = _semantic_revalidate(con, investor_id)
    return {
        "audited": len(rows),
        "kept": kept,
        "rejected": rejected,
        "failed": failed,
        "semantic_rejected": semantic_rejected,
    }
