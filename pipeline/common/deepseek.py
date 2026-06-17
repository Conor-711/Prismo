"""DeepSeek（OpenAI 兼容端点）封装：结构化 JSON 输出。

与 qwen.py 接口对齐，便于被统一的档位路由层（common.llm）调度。
deepseek-v4-pro 为推理型，会在响应里附带 reasoning_content；真正答案在
message.content，本封装只取 content（忽略思维链）。服务端自带 prompt 缓存。
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
    retries: int = 4,
    timeout: int = 180,
) -> str:
    model = model or settings.deepseek_model_low
    url = settings.deepseek_base_url.rstrip("/") + "/chat/completions"
    headers = {"Authorization": f"Bearer {settings.deepseek_api_key}", "Content-Type": "application/json"}
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    last = ""
    for i in range(retries):
        try:
            r = requests.post(url, json=body, headers=headers, timeout=timeout)
            if r.status_code == 200:
                return r.json()["choices"][0]["message"].get("content") or ""
            last = f"HTTP {r.status_code}: {r.text[:300]}"
        except Exception as e:  # noqa: BLE001
            last = str(e)
        time.sleep(1.2 * (i + 1))
    raise RuntimeError(f"deepseek 请求失败: {last}")


def messages_json(system: str, user: str, model: str | None = None, max_tokens: int = 1200):
    return extract_json(chat(system, user, model=model, max_tokens=max_tokens))
