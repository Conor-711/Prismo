"""Gemini（Google Generative Language API）封装：文本 + YouTube 视频理解。

用于「YouTube 观点」模块：
  - analyze_video(url, ...)：把 **YouTube URL 直接交给 Gemini**（看画面+音频），官方支持
    `file_data.file_uri`，preview 阶段免费但限 8 小时视频/天/项目。
  - chat(...)：纯文本（字幕总结等）。
缺 key 时由调用方回退 mock；接口风格与 deepseek/qwen 对齐。
"""
from __future__ import annotations

import re
import time

import requests

from .config import settings
from .deepseek import extract_json  # 复用稳健 JSON 解析（容忍 ```fence）

# 429 限流响应里 Google 给的建议等待时长（RetryInfo.retryDelay: "38s"）
_RETRY_DELAY_RE = re.compile(r'"retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s"')


def _endpoint(model: str) -> str:
    base = settings.gemini_base_url.rstrip("/")
    return f"{base}/models/{model}:generateContent?key={settings.gemini_api_key}"


def _gen(parts: list, system: str | None, max_tokens: int, temperature: float,
         low_res: bool, model: str | None, retries: int, timeout: int) -> str:
    model = model or settings.gemini_model
    # 关思考(thinkingBudget=0)：本项目都是结构化抽取/总结，直接出答案——省 token、避免思考型 flash
    # 把 maxOutputTokens 全耗在 thoughtSignature 上而 MAX_TOKENS 截断（实测 3.5-flash 默认开思考会截断）。
    cfg = {"maxOutputTokens": max_tokens, "temperature": temperature,
           "thinkingConfig": {"thinkingBudget": 0}}
    if low_res:
        cfg["mediaResolution"] = "MEDIA_RESOLUTION_LOW"  # 视频 ~100 tok/秒（默认 ~300）
    body: dict = {"contents": [{"parts": parts}], "generationConfig": cfg}
    if system:
        body["systemInstruction"] = {"parts": [{"text": system}]}
    last = ""
    tries = 0          # 普通错误（5xx/网络）重试预算
    rate_waits = 0     # 429 限流等待次数（独立、更耐心——限流是 per-minute、会过去）
    MAX_RATE_WAITS = 12
    while True:
        try:
            r = requests.post(_endpoint(model), json=body, timeout=timeout)
            if r.status_code == 200:
                cands = r.json().get("candidates") or []
                if not cands:
                    return ""
                out = (cands[0].get("content") or {}).get("parts") or []
                return "".join(p.get("text", "") for p in out)
            if r.status_code == 429:  # 限流：按 Google 给的 retryDelay 耐心等，不消耗普通重试预算
                if rate_waits >= MAX_RATE_WAITS:
                    last = f"HTTP 429 限流，已等 {rate_waits} 次仍未通过"
                    break
                m = _RETRY_DELAY_RE.search(r.text)
                delay = float(m.group(1)) if m else min(60.0, 8.0 * (rate_waits + 1))
                rate_waits += 1
                time.sleep(min(delay + 1.5, 90.0))
                continue
            last = f"HTTP {r.status_code}: {r.text[:300]}"
        except Exception as e:  # noqa: BLE001
            last = str(e)
        tries += 1
        if tries >= retries:
            break
        time.sleep(2.0 * tries)
    raise RuntimeError(f"gemini 请求失败: {last}")


def chat(system: str, user: str, model: str | None = None, max_tokens: int = 1500,
         temperature: float = 0.2, retries: int = 5, timeout: int = 120) -> str:
    return _gen([{"text": user}], system, max_tokens, temperature, False, model, retries, timeout)


def analyze_video(url: str, prompt: str, system: str | None = None, low_res: bool = False,
                  model: str | None = None, max_tokens: int = 1500, timeout: int = 600) -> str:
    """把 YouTube URL 交给 Gemini 看（画面+音频）并按 prompt 输出。"""
    parts = [{"file_data": {"file_uri": url}}, {"text": prompt}]
    return _gen(parts, system, max_tokens, 0.2, low_res, model, 8, timeout)  # 多重试穿过 flaky egress


def messages_json(system: str, user: str, model: str | None = None, max_tokens: int = 1500):
    return extract_json(chat(system, user, model=model, max_tokens=max_tokens))


def video_json(url: str, prompt: str, system: str | None = None, low_res: bool = False,
               model: str | None = None, max_tokens: int = 1500):
    return extract_json(analyze_video(url, prompt, system=system, low_res=low_res,
                                      model=model, max_tokens=max_tokens))
