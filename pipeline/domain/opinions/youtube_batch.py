"""Asynchronous Gemini Batch transport for transcript-backed YouTube SV."""
from __future__ import annotations

import datetime as dt
import json
import sqlite3
import time
from pathlib import Path
from typing import Any

import requests

from ...common.config import settings
from ...common.deepseek import extract_json
from .youtube_analysis import SYSTEM_FULLTEXT, _split_speech_text, _strip_md


TERMINAL_STATES = {
    "BATCH_STATE_SUCCEEDED",
    "BATCH_STATE_FAILED",
    "BATCH_STATE_CANCELLED",
    "BATCH_STATE_EXPIRED",
}


def _now() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


def _connect(db: Path) -> sqlite3.Connection:
    con = sqlite3.connect(db, timeout=30)
    con.execute("PRAGMA busy_timeout=30000")
    return con


def _ensure_tables(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_fulltext_batch_job (
             name TEXT PRIMARY KEY,
             model TEXT NOT NULL,
             state TEXT NOT NULL,
             request_count INTEGER NOT NULL,
             video_ids_json TEXT NOT NULL,
             created_at TEXT NOT NULL,
             updated_at TEXT NOT NULL,
             collected_at TEXT,
             success_count INTEGER NOT NULL DEFAULT 0,
             failure_count INTEGER NOT NULL DEFAULT 0,
             error TEXT NOT NULL DEFAULT ''
           )"""
    )
    con.commit()


def _endpoint(path: str) -> str:
    return f"{settings.gemini_base_url.rstrip('/')}/{path.lstrip('/')}"


def _request_for_video(row: sqlite3.Row) -> dict[str, Any]:
    prompt = f"标的 {row['ticker']}。频道《{row['channel']}》。按系统要求结构化还原该视频。"
    return {
        "contents": [{
            "parts": [
                {"file_data": {"file_uri": row["url"]}},
                {"text": prompt},
            ]
        }],
        "systemInstruction": {"parts": [{"text": SYSTEM_FULLTEXT}]},
        "generationConfig": {
            "maxOutputTokens": 8000,
            "temperature": 0.2,
            "thinkingConfig": {"thinkingBudget": 0},
            "mediaResolution": "MEDIA_RESOLUTION_LOW",
        },
    }


def submit_fulltext_batch(
    db_path: str | Path,
    video_ids: set[str],
    model: str = "gemini-3-flash-preview",
) -> str:
    """Submit one idempotently-recorded inline batch and return its resource name."""
    db = Path(db_path).expanduser().resolve()
    with _connect(db) as con:
        con.row_factory = sqlite3.Row
        _ensure_tables(con)
        ids = sorted(video_ids)
        rows: list[sqlite3.Row] = []
        for offset in range(0, len(ids), 500):
            batch = ids[offset : offset + 500]
            placeholders = ",".join("?" for _ in batch)
            rows.extend(con.execute(
                f"""SELECT id,ticker,channel,url FROM yt_video
                      WHERE id IN ({placeholders})
                        AND NOT EXISTS (
                          SELECT 1 FROM yt_fulltext f WHERE f.video_id=yt_video.id
                        )""",
                batch,
            ).fetchall())
    if not rows:
        raise ValueError("no videos need batch fulltext generation")

    requests_payload = [
        {"request": _request_for_video(row), "metadata": {"key": row["id"]}}
        for row in rows
    ]
    body = {
        "batch": {
            "display_name": f"prismo-youtube-sv-{dt.datetime.now(dt.UTC):%Y%m%d-%H%M%S}",
            "input_config": {"requests": {"requests": requests_payload}},
        }
    }
    response = requests.post(
        _endpoint(f"models/{model}:batchGenerateContent"),
        headers={"x-goog-api-key": settings.gemini_api_key, "Content-Type": "application/json"},
        json=body,
        timeout=180,
    )
    response.raise_for_status()
    payload = response.json()
    name = str(payload["name"])
    state = str((payload.get("metadata") or {}).get("state") or "BATCH_STATE_PENDING")
    now = _now()
    with _connect(db) as con:
        _ensure_tables(con)
        con.execute(
            """INSERT INTO yt_fulltext_batch_job
               (name,model,state,request_count,video_ids_json,created_at,updated_at)
               VALUES (?,?,?,?,?,?,?)""",
            (name, model, state, len(rows), json.dumps([row["id"] for row in rows]), now, now),
        )
        con.commit()
    print(f"[yt-batch] submitted name={name} requests={len(rows)} model={model}", flush=True)
    return name


def _batch_payload(name: str) -> dict[str, Any]:
    last_error: Exception | None = None
    for attempt in range(1, 6):
        try:
            response = requests.get(
                _endpoint(name),
                headers={"x-goog-api-key": settings.gemini_api_key},
                timeout=180,
            )
            response.raise_for_status()
            return response.json()
        except (requests.RequestException, ValueError) as exc:
            last_error = exc
            if attempt < 5:
                time.sleep(2**attempt)
    raise RuntimeError(f"failed to read Gemini batch {name}: {last_error}")


def _state(payload: dict[str, Any]) -> str:
    return str((payload.get("metadata") or payload).get("state") or "")


def _inline_responses(payload: dict[str, Any]) -> list[dict[str, Any]]:
    output = payload.get("response") or (payload.get("metadata") or {}).get("output") or {}
    return list(((output.get("inlinedResponses") or {}).get("inlinedResponses") or []))


def _normalized_segments(item: dict[str, Any]) -> list[dict[str, str]]:
    response = item.get("response") or {}
    candidates = response.get("candidates") or []
    parts = (((candidates[0] if candidates else {}).get("content") or {}).get("parts") or [])
    raw = "".join(str(part.get("text") or "") for part in parts)
    data = extract_json(raw)
    source_segments = (data or {}).get("segments") if isinstance(data, dict) else None
    if not isinstance(source_segments, list):
        return []
    result: list[dict[str, str]] = []
    for source in source_segments:
        if not isinstance(source, dict) or source.get("type") != "speech":
            continue
        text = str(source.get("text") or "").strip()
        speaker = str(source.get("speaker") or "").strip()
        for paragraph in _split_speech_text(text):
            segment = {"type": "speech", "text": paragraph}
            if speaker:
                segment["speaker"] = speaker
            result.append(segment)
    return result


def collect_fulltext_batch(db_path: str | Path, name: str) -> dict[str, Any]:
    """Collect one completed job into yt_fulltext; safe to call repeatedly."""
    db = Path(db_path).expanduser().resolve()
    payload = _batch_payload(name)
    state = _state(payload)
    with _connect(db) as con:
        _ensure_tables(con)
        con.execute(
            "UPDATE yt_fulltext_batch_job SET state=?,updated_at=? WHERE name=?",
            (state, _now(), name),
        )
        con.commit()
    if state not in TERMINAL_STATES:
        return {"name": name, "state": state, "success": 0, "failure": 0}
    if state != "BATCH_STATE_SUCCEEDED":
        error = json.dumps(payload.get("error") or {}, ensure_ascii=False)[:2000]
        with _connect(db) as con:
            con.execute(
                "UPDATE yt_fulltext_batch_job SET error=?,collected_at=?,updated_at=? WHERE name=?",
                (error, _now(), _now(), name),
            )
            con.commit()
        return {"name": name, "state": state, "success": 0, "failure": 0, "error": error}

    success = 0
    failure = 0
    now = _now()
    with _connect(db) as con:
        con.row_factory = sqlite3.Row
        for item in _inline_responses(payload):
            video_id = str((item.get("metadata") or {}).get("key") or "")
            segments = _normalized_segments(item)
            if not video_id or not segments:
                failure += 1
                continue
            row = con.execute("SELECT ticker FROM yt_video WHERE id=?", (video_id,)).fetchone()
            if row is None:
                failure += 1
                continue
            flat = "\n\n".join(
                f"{segment['speaker']}：{_strip_md(segment['text'])}"
                if segment.get("speaker") else _strip_md(segment["text"])
                for segment in segments
            )
            con.execute(
                """INSERT INTO yt_fulltext
                   (video_id,ticker,content_zh,content_en,model,created_at,segments)
                   VALUES (?,?,?,?,?,?,?)
                   ON CONFLICT(video_id) DO UPDATE SET
                     ticker=excluded.ticker,content_zh=excluded.content_zh,
                     content_en=excluded.content_en,model=excluded.model,
                     created_at=excluded.created_at,segments=excluded.segments""",
                (video_id, row["ticker"], flat, "", f"gemini-batch:{payload['metadata']['model']}", now,
                 json.dumps(segments, ensure_ascii=False)),
            )
            con.execute("DELETE FROM yt_fulltext_fail WHERE video_id=?", (video_id,))
            success += 1
        con.execute(
            """UPDATE yt_fulltext_batch_job
                  SET state=?,success_count=?,failure_count=?,collected_at=?,updated_at=?
                WHERE name=?""",
            (state, success, failure, now, now, name),
        )
        con.commit()
    result = {"name": name, "state": state, "success": success, "failure": failure}
    print(f"[yt-batch] collected {result}", flush=True)
    return result


def wait_and_collect_fulltext_batch(
    db_path: str | Path,
    name: str,
    poll_seconds: int = 30,
    timeout_seconds: int = 86_400,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    while True:
        result = collect_fulltext_batch(db_path, name)
        print(f"[yt-batch] state={result['state']} name={name}", flush=True)
        if result["state"] in TERMINAL_STATES:
            return result
        if time.monotonic() >= deadline:
            raise TimeoutError(f"batch did not finish before timeout: {name}")
        time.sleep(max(5, poll_seconds))
