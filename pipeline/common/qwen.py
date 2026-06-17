"""通义千问（DashScope, OpenAI 兼容端点）封装：结构化 JSON 输出。

依赖 requests（已在 pipeline/.venv）。可选 enable_thinking（默认关，更快更省）。
"""
from __future__ import annotations

import json
import re
import time

import requests

from .config import settings


def extract_json(text: str):
    """从模型输出里稳健解析 JSON（容忍 ```fence 与前后缀）。"""
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
    a, b = t.find("{"), t.rfind("}")
    if a != -1 and b > a:
        try:
            return json.loads(t[a : b + 1])
        except (ValueError, TypeError):
            return None
    return None


def chat(
    system: str,
    user: str,
    model: str | None = None,
    max_tokens: int = 1200,
    temperature: float = 0.2,
    enable_thinking: bool = False,
    retries: int = 4,
    timeout: int = 120,
) -> str:
    model = model or settings.qwen_model
    url = settings.qwen_base_url.rstrip("/") + "/chat/completions"
    headers = {"Authorization": f"Bearer {settings.qwen_api_key}", "Content-Type": "application/json"}
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "enable_thinking": enable_thinking,  # DashScope 扩展字段；关闭思考更快
    }
    last = ""
    for i in range(retries):
        try:
            r = requests.post(url, json=body, headers=headers, timeout=timeout)
            if r.status_code == 200:
                return r.json()["choices"][0]["message"].get("content") or ""
            last = f"HTTP {r.status_code}: {r.text[:300]}"
            # 400 多为参数问题（如 enable_thinking 不支持），去掉该字段再试一次
            if r.status_code == 400 and "enable_thinking" in body:
                body.pop("enable_thinking", None)
        except Exception as e:  # noqa: BLE001
            last = str(e)
        time.sleep(1.2 * (i + 1))
    raise RuntimeError(f"qwen 请求失败: {last}")


def messages_json(system: str, user: str, model: str | None = None, max_tokens: int = 1200,
                  enable_thinking: bool = False):
    # 投资分析 → enable_thinking=True（更强推理）；普通翻译 → False（更快更省）。
    return extract_json(chat(system, user, model=model, max_tokens=max_tokens, enable_thinking=enable_thinking))
