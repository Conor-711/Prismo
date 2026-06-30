"""按「任务档位」路由到具体大模型 provider 的统一层。

全站 AI 任务分三档，改档位只需动这一张路由表：
  - LOW  低档 → 通义千问 qwen-flash（走量：翻译 / KOL 提炼·视角·论点；原 DeepSeek flash，余额耗尽后切此）
  - MID  中档 → 通义千问 qwen3.7-plus （叙事聚类 / 每日简报 / 正文重排版；原 DeepSeek pro，按要求切千问）
  - HIGH 高档 → 通义千问 qwen3.7-plus（思考模式：逐帖投资打标，全站分析大脑）

调用方只关心档位，不关心是谁家的模型：
    from ..common.llm import messages_json, chat, MID, HIGH
    data = messages_json(HIGH, system, user, max_tokens=2600, enable_thinking=True)
    text = chat(MID, system, user, max_tokens=1800)
"""
from __future__ import annotations

from typing import Any

from . import deepseek, qwen
from .config import settings

LOW = "low"
MID = "mid"
HIGH = "high"

# provider 标识
_QWEN = "qwen"
_DEEPSEEK = "deepseek"


def _route(tier: str) -> tuple[str, str]:
    """档位 → (provider, model)。"""
    if tier == HIGH:
        return _QWEN, settings.qwen_model
    if tier == MID:
        return _QWEN, settings.qwen_model  # MID → 千问（原 DeepSeek pro；按要求全面切千问）
    return _QWEN, settings.qwen_model_low  # LOW → 千问便宜档（原 DeepSeek flash；账户余额耗尽后切千问）


def model_label(tier: str) -> str:
    """该档位实际使用的「provider:model」标识，用于写入 DB 的 model 字段。"""
    provider, model = _route(tier)
    return f"{provider}:{model}"


def available(tier: str) -> bool:
    """该档位对应 provider 的 key 是否就绪（不就绪时调用方应回退 mock）。"""
    provider, _ = _route(tier)
    return settings.has_qwen if provider == _QWEN else settings.has_deepseek


def chat(tier: str, system: str, user: str, max_tokens: int = 1200,
         temperature: float = 0.2, enable_thinking: bool = False) -> str:
    provider, model = _route(tier)
    if provider == _QWEN:
        return qwen.chat(system, user, model=model, max_tokens=max_tokens,
                         temperature=temperature, enable_thinking=enable_thinking)
    return deepseek.chat(system, user, model=model, max_tokens=max_tokens, temperature=temperature)


def messages_json(tier: str, system: str, user: str, max_tokens: int = 1200,
                  enable_thinking: bool = False) -> Any | None:
    provider, model = _route(tier)
    if provider == _QWEN:
        return qwen.messages_json(system, user, model=model, max_tokens=max_tokens,
                                  enable_thinking=enable_thinking)
    return deepseek.messages_json(system, user, model=model, max_tokens=max_tokens)
