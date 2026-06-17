"""PRAW 客户端工厂（只读、app-only OAuth）。"""
from __future__ import annotations

from .config import settings


def get_reddit():
    """返回只读 praw.Reddit 实例；缺依赖或凭证时给出清晰报错。"""
    try:
        import praw
    except ImportError as e:  # pragma: no cover
        raise RuntimeError("praw 未安装，请先运行 `make install`") from e

    if not settings.has_reddit:
        raise RuntimeError(
            "缺少 Reddit 凭证。请在 .env 填写 "
            "REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET / REDDIT_USER_AGENT。"
        )

    reddit = praw.Reddit(
        client_id=settings.reddit_client_id,
        client_secret=settings.reddit_client_secret,
        user_agent=settings.reddit_user_agent,
        check_for_async=False,
    )
    reddit.read_only = True
    return reddit
