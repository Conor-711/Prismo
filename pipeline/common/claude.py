"""Anthropic Claude 封装：JSON 输出 + prompt caching + 可选 Batch。"""
from __future__ import annotations

import json
import re
import time
from typing import Any, Optional

from .config import settings


def get_client():
    try:
        import anthropic
    except ImportError as e:  # pragma: no cover
        raise RuntimeError("anthropic 未安装，请先运行 `make install`") from e
    if not settings.has_anthropic:
        raise RuntimeError("缺少 ANTHROPIC_API_KEY（请在 .env 填写）。")
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


def extract_json(text: str) -> Optional[Any]:
    """从模型输出中稳健地解析 JSON（容忍代码围栏与前后缀文本）。"""
    if not text:
        return None
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```[a-zA-Z]*\n?", "", t)
        t = re.sub(r"\n?```$", "", t).strip()
    try:
        return json.loads(t)
    except (ValueError, TypeError):
        pass
    start, end = t.find("{"), t.rfind("}")
    if start != -1 and end > start:
        try:
            return json.loads(t[start : end + 1])
        except (ValueError, TypeError):
            return None
    return None


def _system_blocks(system: str, cache: bool) -> list[dict]:
    block: dict = {"type": "text", "text": system}
    if cache:
        block["cache_control"] = {"type": "ephemeral"}
    return [block]


def messages_text(
    system: str,
    user: str,
    model: str,
    max_tokens: int = 1500,
    cache: bool = True,
    temperature: float = 0.0,
) -> str:
    client = get_client()
    resp = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        temperature=temperature,
        system=_system_blocks(system, cache),
        messages=[{"role": "user", "content": user}],
    )
    return "".join(getattr(b, "text", "") for b in resp.content if getattr(b, "type", "") == "text")


def messages_json(
    system: str,
    user: str,
    model: str,
    max_tokens: int = 1024,
    cache: bool = True,
    temperature: float = 0.0,
) -> tuple[Optional[Any], str]:
    """同步调用，返回 (解析后的 JSON 或 None, 原始文本)。"""
    raw = messages_text(system, user, model, max_tokens, cache, temperature)
    return extract_json(raw), raw


# ----------------------------- Batch API（规模化用） -----------------------------
def submit_batch(requests: list[dict]) -> str:
    """提交 Message Batches（省 50%）。requests 为 anthropic 规范的请求列表，返回 batch_id。"""
    client = get_client()
    batch = client.messages.batches.create(requests=requests)
    return batch.id


def poll_batch(batch_id: str, interval: float = 10.0, timeout: float = 86400.0) -> dict:
    """轮询直到 batch 结束，返回 custom_id -> 文本结果 的映射。"""
    client = get_client()
    waited = 0.0
    while True:
        batch = client.messages.batches.retrieve(batch_id)
        if batch.processing_status == "ended":
            break
        if waited >= timeout:
            raise TimeoutError(f"batch {batch_id} 超时")
        time.sleep(interval)
        waited += interval

    out: dict[str, str] = {}
    for result in client.messages.batches.results(batch_id):
        if result.result.type == "succeeded":
            msg = result.result.message
            out[result.custom_id] = "".join(
                getattr(b, "text", "") for b in msg.content if getattr(b, "type", "") == "text"
            )
        else:
            out[result.custom_id] = ""
    return out


def build_batch_request(custom_id: str, system: str, user: str, model: str, max_tokens: int = 1024, cache: bool = True) -> dict:
    return {
        "custom_id": custom_id,
        "params": {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": 0.0,
            "system": _system_blocks(system, cache),
            "messages": [{"role": "user", "content": user}],
        },
    }
