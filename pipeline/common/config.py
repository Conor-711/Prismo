"""集中配置：从 .env 与环境变量读取，提供路径与参数。"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

try:
    from dotenv import load_dotenv
except Exception:  # python-dotenv 未装时降级
    def load_dotenv(*_a, **_k):  # type: ignore
        return False

# 仓库根目录： pipeline/common/config.py -> parents[2]
ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")

PIPELINE_DIR = ROOT / "pipeline"
PKG_DATA_DIR = PIPELINE_DIR / "data"      # 随仓库的字典/样本/板块清单
RUNTIME_DATA_DIR = ROOT / "data"          # 本地 db 等运行期数据（git 忽略）
RUNTIME_DATA_DIR.mkdir(parents=True, exist_ok=True)


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "") or default)
    except ValueError:
        return default


def normalize_db_url(url: str) -> str:
    """规范化数据库连接串，让 Supabase 的连接串可直接用：
    - `postgres://` / `postgresql://`（Supabase/Heroku 风格）→ SQLAlchemy + psycopg(3) 用的
      `postgresql+psycopg://`；
    - Postgres 连接自动强制 SSL（Supabase 必须）。
    SQLite 原样返回。这样用户把 Supabase 控制台复制的串直接粘进 DATABASE_URL 即可，无需手改。
    """
    if not url:
        return url
    if url.startswith("postgres://"):
        url = "postgresql+psycopg://" + url[len("postgres://"):]
    elif url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    if url.startswith("postgresql+psycopg://") and "sslmode=" not in url:
        url += ("&" if "?" in url else "?") + "sslmode=require"
    return url


@dataclass(frozen=True)
class Settings:
    database_url: str = os.environ.get("DATABASE_URL", "sqlite:///./data/dev.db")

    reddit_client_id: str = os.environ.get("REDDIT_CLIENT_ID", "")
    reddit_client_secret: str = os.environ.get("REDDIT_CLIENT_SECRET", "")
    reddit_user_agent: str = os.environ.get(
        "REDDIT_USER_AGENT", "reddit-kaito-pro/0.1 (by u/unknown)"
    )

    anthropic_api_key: str = os.environ.get("ANTHROPIC_API_KEY", "")
    model_tag: str = os.environ.get("ANTHROPIC_MODEL_TAG", "claude-haiku-4-5")
    model_synth: str = os.environ.get("ANTHROPIC_MODEL_SYNTH", "claude-sonnet-4-6")
    model_brief: str = os.environ.get("ANTHROPIC_MODEL_BRIEF", "claude-sonnet-4-6")

    # 通义千问（DashScope, OpenAI 兼容）—— 高档任务（逐帖投资打标，开思考模式）
    qwen_api_key: str = os.environ.get("QWEN_API_KEY", "")
    qwen_model: str = os.environ.get("QWEN_MODEL", "qwen3.7-plus")
    qwen_model_low: str = os.environ.get("QWEN_MODEL_LOW", "qwen-flash")  # 低档便宜模型（DeepSeek 没余额时 LOW 走它）
    qwen_base_url: str = os.environ.get(
        "QWEN_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1"
    )

    # DeepSeek（OpenAI 兼容）—— 低档(flash)/中档(pro)任务
    deepseek_api_key: str = os.environ.get("DEEPSEEK_API_KEY", "")
    deepseek_base_url: str = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
    deepseek_model_low: str = os.environ.get("DEEPSEEK_MODEL_LOW", "deepseek-v4-flash")
    deepseek_model_mid: str = os.environ.get("DEEPSEEK_MODEL_MID", "deepseek-v4-pro")

    # Gemini（Google Generative Language API）—— YouTube 视频理解 + 字幕文本总结（「YouTube 观点」模块）
    # 一把 Google key 可两用：同一 GCP 项目启用 Generative Language API + YouTube Data API v3 即可
    # （GEMINI_API_KEY / YOUTUBE_API_KEY 单独设则优先，否则都回退到 GOOGLE_API_KEY）。
    gemini_api_key: str = os.environ.get("GEMINI_API_KEY", "") or os.environ.get("GOOGLE_API_KEY", "")
    # 注：免费档各模型「每天请求数」差异极大——3.5-flash 仅 20/天、2.0-flash 已降为 0/天，
    # 2.5-flash 仍有可用额度且支持视频理解，故默认用它（要换在 .env 设 GEMINI_MODEL）。
    gemini_model: str = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    gemini_base_url: str = os.environ.get(
        "GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta"
    )
    # YouTube Data API v3 —— 视频发现（按标的近 24h 搜，配额 1万 units/天）
    youtube_api_key: str = os.environ.get("YOUTUBE_API_KEY", "") or os.environ.get("GOOGLE_API_KEY", "")
    # 「YouTube 观点」预算：每天原生看视频的总分钟上限（Gemini 限 8h/天=480min；留余量）
    yt_daily_video_minutes: int = field(default_factory=lambda: _int("YT_DAILY_VIDEO_MINUTES", 420))
    yt_min_views: int = field(default_factory=lambda: _int("YT_MIN_VIEWS", 1000))

    ingest_post_limit: int = field(default_factory=lambda: _int("INGEST_POST_LIMIT", 120))
    ingest_comment_min_score: int = field(
        default_factory=lambda: _int("INGEST_COMMENT_MIN_SCORE", 15)
    )
    mindshare_window_hours: int = field(
        default_factory=lambda: _int("MINDSHARE_WINDOW_HOURS", 24)
    )

    @property
    def has_reddit(self) -> bool:
        return bool(self.reddit_client_id and self.reddit_client_secret)

    @property
    def has_anthropic(self) -> bool:
        return bool(self.anthropic_api_key)

    @property
    def has_qwen(self) -> bool:
        return bool(self.qwen_api_key)

    @property
    def has_deepseek(self) -> bool:
        return bool(self.deepseek_api_key)

    @property
    def has_gemini(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def has_youtube(self) -> bool:
        return bool(self.youtube_api_key)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
