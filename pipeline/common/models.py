"""SQLAlchemy 数据模型 = schema 单一真源（SQLite 开发 / Postgres 生产通用）。

JSON 字段统一用 JSONText（Text 存 JSON 字符串），保证跨方言一致，
也便于 Web 侧 Prisma 以 String 读取后再解析。
"""
from __future__ import annotations

import datetime as dt
import json
from typing import Optional

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import TypeDecorator


class Base(DeclarativeBase):
    pass


class JSONText(TypeDecorator):
    """可移植 JSON 列：以 Text 存储 JSON 字符串。"""

    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return json.dumps(value, ensure_ascii=False)

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        try:
            return json.loads(value)
        except (ValueError, TypeError):
            return None


def utcnow() -> dt.datetime:
    return dt.datetime.utcnow()


# ----------------------------- 原始数据 -----------------------------
class Subreddit(Base):
    __tablename__ = "subreddits"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 小写名
    display_name: Mapped[str] = mapped_column(String(128), default="")
    subscribers: Mapped[int] = mapped_column(Integer, default=0)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)  # us | cn（中概+港股+A股）
    # tracked=展示在侧边栏「追踪社区」；A 股关键词扫描的来源版块(r/China 等)设 False 不展示。
    tracked: Mapped[bool] = mapped_column(Boolean, default=True)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class Author(Base):
    __tablename__ = "authors"
    id: Mapped[str] = mapped_column(String(80), primary_key=True)  # 用户名
    created_utc: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)
    comment_karma: Mapped[int] = mapped_column(Integer, default=0)
    link_karma: Mapped[int] = mapped_column(Integer, default=0)
    first_seen: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    last_seen: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    post_count: Mapped[int] = mapped_column(Integer, default=0)
    influence_score: Mapped[float] = mapped_column(Float, default=0.0)
    # 作者库：上次爬取其历史帖的时间。NULL=从未爬过；用于每日增量（只爬 NULL 或过期的）。
    crawled_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime, nullable=True)


class Post(Base):
    __tablename__ = "posts"
    id: Mapped[str] = mapped_column(String(16), primary_key=True)  # reddit base36 id
    subreddit_id: Mapped[str] = mapped_column(String(64), ForeignKey("subreddits.id"), index=True)
    author_id: Mapped[Optional[str]] = mapped_column(String(80), ForeignKey("authors.id"), nullable=True, index=True)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)  # 随板块归属：us | cn
    # 来源：scan=板块扫描（进实时舆情聚合）；author=作者库历史爬取（只进作者页，不污染实时聚合）。
    source: Mapped[str] = mapped_column(String(8), default="scan", index=True)
    title: Mapped[str] = mapped_column(Text, default="")
    selftext: Mapped[str] = mapped_column(Text, default="")
    title_zh: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # 中文译文（按需）
    selftext_zh: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    selftext_fmt: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # AI 重排版后的 Markdown（提升可读性）
    url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    permalink: Mapped[str] = mapped_column(Text, default="")
    flair: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    is_self: Mapped[bool] = mapped_column(Boolean, default=True)
    created_utc: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    score: Mapped[int] = mapped_column(Integer, default=0)
    upvote_ratio: Mapped[float] = mapped_column(Float, default=0.0)
    num_comments: Mapped[int] = mapped_column(Integer, default=0)
    total_awards: Mapped[int] = mapped_column(Integer, default=0)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    last_refreshed_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class Comment(Base):
    __tablename__ = "comments"
    id: Mapped[str] = mapped_column(String(16), primary_key=True)
    post_id: Mapped[str] = mapped_column(String(16), ForeignKey("posts.id"), index=True)
    author_id: Mapped[Optional[str]] = mapped_column(String(80), ForeignKey("authors.id"), nullable=True)
    body: Mapped[str] = mapped_column(Text, default="")
    body_zh: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # 中文译文（按需）
    score: Mapped[int] = mapped_column(Integer, default=0)
    created_utc: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    parent_id: Mapped[Optional[str]] = mapped_column(String(24), nullable=True)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


# ----------------------------- 字典 / 抽取 -----------------------------
class TickerMeta(Base):
    __tablename__ = "ticker_meta"
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True)  # 大写（美股代码 / 港股 0700.HK / A股 600519.SS）
    company_name: Mapped[str] = mapped_column(String(256), default="")
    cik: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    exchange: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    sector: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    market: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)  # 标记策划的中概/港股宇宙（cn）；美股 SEC 字典留空
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    aliases: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)


class Mention(Base):
    __tablename__ = "mentions"
    # 复合主键 = 一条 item 对一个 ticker 唯一；让 merge() 能正确幂等 upsert。
    ticker: Mapped[str] = mapped_column(String(16), ForeignKey("ticker_meta.ticker"), primary_key=True, index=True)
    item_id: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    item_type: Mapped[str] = mapped_column(String(8), primary_key=True)  # post | comment
    subreddit_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True, index=True)
    author_id: Mapped[Optional[str]] = mapped_column(String(80), nullable=True)
    context_snippet: Mapped[str] = mapped_column(Text, default="")
    confidence: Mapped[float] = mapped_column(Float, default=0.0)
    method: Mapped[str] = mapped_column(String(16), default="")  # cashtag|dict|company|context
    created_utc: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


# ----------------------------- AI 分析 -----------------------------
class ItemAnalysis(Base):
    __tablename__ = "item_analysis"
    item_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    item_type: Mapped[str] = mapped_column(String(8), primary_key=True)  # post|comment
    sentiment_label: Mapped[str] = mapped_column(String(16), default="neutral")
    sentiment_score: Mapped[float] = mapped_column(Float, default=0.0)  # -1..1
    stance: Mapped[str] = mapped_column(String(16), default="neutral")  # bull|bear|neutral
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)  # 0..1 干货 vs 噪音
    themes: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    tldr: Mapped[str] = mapped_column(Text, default="")
    tldr_zh: Mapped[str] = mapped_column(Text, default="")  # 中文译文（按需）
    bull_points: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    bear_points: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    bull_points_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    bear_points_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    tickers: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)  # [{ticker,relevance}]
    model: Mapped[str] = mapped_column(String(48), default="")
    analyzed_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


# ----------------------------- 聚合 / rollup -----------------------------
class TickerRollup(Base):
    __tablename__ = "ticker_rollup"
    __table_args__ = (
        UniqueConstraint("ticker", "bucket", "bucket_ts", "market", name="uq_ticker_rollup"),
    )
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)
    bucket: Mapped[str] = mapped_column(String(8))  # hour | day
    bucket_ts: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    mention_count: Mapped[int] = mapped_column(Integer, default=0)
    weighted_mentions: Mapped[float] = mapped_column(Float, default=0.0)
    engagement_sum: Mapped[int] = mapped_column(Integer, default=0)
    unique_authors: Mapped[int] = mapped_column(Integer, default=0)
    post_count: Mapped[int] = mapped_column(Integer, default=0)
    mindshare_pct: Mapped[float] = mapped_column(Float, default=0.0)
    sentiment_avg: Mapped[float] = mapped_column(Float, default=0.0)
    bull_count: Mapped[int] = mapped_column(Integer, default=0)
    bear_count: Mapped[int] = mapped_column(Integer, default=0)
    neutral_count: Mapped[int] = mapped_column(Integer, default=0)


class MarketMood(Base):
    __tablename__ = "market_mood"
    __table_args__ = (UniqueConstraint("bucket", "bucket_ts", "market", name="uq_market_mood"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)
    bucket: Mapped[str] = mapped_column(String(8))  # hour | day
    bucket_ts: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    mood_score: Mapped[float] = mapped_column(Float, default=0.0)  # -1..1
    bull_pct: Mapped[float] = mapped_column(Float, default=0.0)
    bear_pct: Mapped[float] = mapped_column(Float, default=0.0)
    neutral_pct: Mapped[float] = mapped_column(Float, default=0.0)
    total_mentions: Mapped[int] = mapped_column(Integer, default=0)
    total_posts: Mapped[int] = mapped_column(Integer, default=0)
    label: Mapped[str] = mapped_column(String(24), default="")  # 极度恐惧..极度贪婪


class Trending(Base):
    __tablename__ = "trending"
    __table_args__ = (UniqueConstraint("ticker", "window", "as_of", "market", name="uq_trending"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)
    window: Mapped[str] = mapped_column(String(8))  # 24h
    as_of: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    mention_count: Mapped[int] = mapped_column(Integer, default=0)
    baseline_mean: Mapped[float] = mapped_column(Float, default=0.0)
    baseline_std: Mapped[float] = mapped_column(Float, default=0.0)
    zscore: Mapped[float] = mapped_column(Float, default=0.0)
    sentiment_avg: Mapped[float] = mapped_column(Float, default=0.0)
    sentiment_delta: Mapped[float] = mapped_column(Float, default=0.0)
    is_spike: Mapped[bool] = mapped_column(Boolean, default=False)
    rank: Mapped[int] = mapped_column(Integer, default=0)


# ----------------------------- 叙事 / 简报 -----------------------------
class Narrative(Base):
    __tablename__ = "narratives"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)
    slug: Mapped[str] = mapped_column(String(96), index=True)
    name: Mapped[str] = mapped_column(String(160), default="")
    summary: Mapped[str] = mapped_column(Text, default="")
    period_start: Mapped[dt.datetime] = mapped_column(DateTime)
    period_end: Mapped[dt.datetime] = mapped_column(DateTime)
    post_count: Mapped[int] = mapped_column(Integer, default=0)
    ticker_count: Mapped[int] = mapped_column(Integer, default=0)
    heat: Mapped[float] = mapped_column(Float, default=0.0)
    model: Mapped[str] = mapped_column(String(48), default="")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow, index=True)


class NarrativeTicker(Base):
    __tablename__ = "narrative_tickers"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    narrative_id: Mapped[int] = mapped_column(Integer, ForeignKey("narratives.id"), index=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    weight: Mapped[float] = mapped_column(Float, default=0.0)


class NarrativePost(Base):
    __tablename__ = "narrative_posts"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    narrative_id: Mapped[int] = mapped_column(Integer, ForeignKey("narratives.id"), index=True)
    post_id: Mapped[str] = mapped_column(String(16), index=True)


class DailyBrief(Base):
    __tablename__ = "daily_briefs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    brief_date: Mapped[str] = mapped_column(String(10), unique=True, index=True)  # YYYY-MM-DD
    title: Mapped[str] = mapped_column(String(200), default="")
    markdown: Mapped[str] = mapped_column(Text, default="")
    highlights: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    model: Mapped[str] = mapped_column(String(48), default="")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


# ----------------------------- 亚洲散户舆情实验（日本/韩国本土社区，隔离表，不污染 us/cn） -----------------------------
# 独立 market 标识 jp|kr；与 Reddit 主管线的 posts/item_analysis/聚合表完全分离，
# 实时舆情 feed / rollups / mood 一律不读这些表。只供隐藏页 /[lang]/lab/asia-pulse 使用。
class AsiaPost(Base):
    __tablename__ = "asia_posts"
    id: Mapped[str] = mapped_column(String(96), primary_key=True)  # f"{source}:{ticker}:{native_id}"
    market: Mapped[str] = mapped_column(String(8), index=True)  # jp | kr
    source: Mapped[str] = mapped_column(String(16), index=True)  # yahoo_jp | naver_kr | naver_world
    ticker: Mapped[str] = mapped_column(String(16), index=True)  # 标准内部键：NVDA | MU | HYNIX
    board_code: Mapped[str] = mapped_column(String(24), default="")  # 站点原生代码（NVDA / 000660 / NVDA.O）
    # 来源真实性：live=本土板实抓；sample=无本土板时的清晰标注样本（仅 JP-海力士等缺口/抓取失败兜底）。
    origin: Mapped[str] = mapped_column(String(8), default="live", index=True)
    author: Mapped[str] = mapped_column(String(120), default="")
    title: Mapped[str] = mapped_column(Text, default="")
    body: Mapped[str] = mapped_column(Text, default="")
    label: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)  # 原生情绪标签（強気/弱気/매수…）
    url: Mapped[str] = mapped_column(Text, default="")
    likes: Mapped[int] = mapped_column(Integer, default=0)  # そう思う(はい) / 추천(공감)
    dislikes: Mapped[int] = mapped_column(Integer, default=0)  # いいえ / 비추천
    reply_count: Mapped[int] = mapped_column(Integer, default=0)  # 兼容旧列（= comments）
    # 丰富维度（按需，缺省 0/False）：浏览量 / 评论数(讨论深度) / 附图数(图表截图) / 作者持股认证
    views: Mapped[int] = mapped_column(Integer, default=0)
    comments: Mapped[int] = mapped_column(Integer, default=0)
    images: Mapped[int] = mapped_column(Integer, default=0)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    # 全量情绪分（-1..1）：DeepSeek flash 给**每一帖**打的轻量分，供「每日情绪时间序列/变化」用。
    # 与 asia_analysis（仅 Top 帖的千问深析）互补；NULL=未打分。
    sentiment: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    created_utc: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class AsiaAnalysis(Base):
    __tablename__ = "asia_analysis"
    post_id: Mapped[str] = mapped_column(String(96), primary_key=True)  # → asia_posts.id
    lang: Mapped[str] = mapped_column(String(8), default="")  # 源文语言 ja | ko
    sentiment_label: Mapped[str] = mapped_column(String(16), default="neutral")
    sentiment_score: Mapped[float] = mapped_column(Float, default=0.0)  # -1..1
    stance: Mapped[str] = mapped_column(String(16), default="neutral")  # bull|bear|neutral
    quality_score: Mapped[float] = mapped_column(Float, default=0.0)
    themes: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    # 双语：站点是 zh/en，源文是日/韩，故 AI 直接产出中英两版摘要与论点。
    tldr_zh: Mapped[str] = mapped_column(Text, default="")
    tldr_en: Mapped[str] = mapped_column(Text, default="")
    bull_points_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    bull_points_en: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    bear_points_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    bear_points_en: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    model: Mapped[str] = mapped_column(String(48), default="")
    analyzed_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class AsiaTickerSummary(Base):
    __tablename__ = "asia_ticker_summary"
    __table_args__ = (UniqueConstraint("market", "ticker", name="uq_asia_summary"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    market: Mapped[str] = mapped_column(String(8), index=True)  # jp | kr
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    source: Mapped[str] = mapped_column(String(16), default="")
    post_count: Mapped[int] = mapped_column(Integer, default=0)
    analyzed_count: Mapped[int] = mapped_column(Integer, default=0)
    bull_pct: Mapped[float] = mapped_column(Float, default=0.0)
    bear_pct: Mapped[float] = mapped_column(Float, default=0.0)
    neutral_pct: Mapped[float] = mapped_column(Float, default=0.0)
    mood_score: Mapped[float] = mapped_column(Float, default=0.0)  # -1..1
    mood_label: Mapped[str] = mapped_column(String(24), default="")
    overview_zh: Mapped[str] = mapped_column(Text, default="")  # AI 汇总段落（DeepSeek）
    overview_en: Mapped[str] = mapped_column(Text, default="")
    top_bull_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    top_bull_en: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    top_bear_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    top_bear_en: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    top_themes: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class AsiaPrice(Base):
    """标的日 K 收盘价（来自 Naver 日K接口），供「价格 vs 情绪/声量」叠加指数图。
    SpaceX(SPCX) 为 pre-IPO 追踪价，历史稀疏。"""
    __tablename__ = "asia_price"
    __table_args__ = (UniqueConstraint("ticker", "day", name="uq_asia_price"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    day: Mapped[str] = mapped_column(String(10), index=True)  # YYYY-MM-DD
    close: Mapped[float] = mapped_column(Float, default=0.0)
    open: Mapped[float] = mapped_column(Float, default=0.0)
    volume: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(8), default="USD")
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


# --------------------- 全球散户多区看板（US Reddit 复用 + 日韩台新爬） ---------------------
# 4 个地区对同一批「精选跨区高共识美股」的情绪对比。隔离表 gr_*：
#   - 与 us/cn Reddit 主管线隔离（US 区只**读**现有 TickerRollup/ItemAnalysis，不写）；
#   - 与 asia_* 4 标的实验也隔离（这是 ticker 中心、~40 标的、含 US 的另一套）。
# 日韩台原始帖入 gr_post（US 不入库）；每 (region,ticker) 滚动入 gr_ticker_region；
# 每 ticker 跨区派生（共识/分歧）入 gr_ticker。仅供隐藏页 /[lang]/lab/global-retail。
class GrPost(Base):
    __tablename__ = "gr_post"
    id: Mapped[str] = mapped_column(String(140), primary_key=True)  # region:source:ticker:native_id
    region: Mapped[str] = mapped_column(String(8), index=True)  # jp | kr | tw（us 读现有 Reddit，不入此表）
    source: Mapped[str] = mapped_column(String(16), index=True)  # yahoo_jp | naver | ptt
    ticker: Mapped[str] = mapped_column(String(16), index=True)  # 规范化美股代码
    board_code: Mapped[str] = mapped_column(String(24), default="")
    author: Mapped[str] = mapped_column(String(120), default="")
    title: Mapped[str] = mapped_column(Text, default="")
    body: Mapped[str] = mapped_column(Text, default="")
    lang: Mapped[str] = mapped_column(String(8), default="")  # ja | ko | zh
    label: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)  # 原生标签([類別]/評価)
    url: Mapped[str] = mapped_column(Text, default="")
    likes: Mapped[int] = mapped_column(Integer, default=0)
    dislikes: Mapped[int] = mapped_column(Integer, default=0)
    views: Mapped[int] = mapped_column(Integer, default=0)
    comments: Mapped[int] = mapped_column(Integer, default=0)
    images: Mapped[int] = mapped_column(Integer, default=0)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    # DeepSeek flash 全量打标（不使用千问）：情绪分 + 多空立场。NULL=未打标。
    sentiment: Mapped[Optional[float]] = mapped_column(Float, nullable=True)  # -1..1
    stance: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)  # bull|bear|neutral
    created_utc: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class GrTickerRegion(Base):
    __tablename__ = "gr_ticker_region"
    __table_args__ = (UniqueConstraint("region", "ticker", name="uq_gr_region"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    region: Mapped[str] = mapped_column(String(8), index=True)  # us | jp | kr | tw
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    post_count: Mapped[int] = mapped_column(Integer, default=0)
    bull_count: Mapped[int] = mapped_column(Integer, default=0)
    bear_count: Mapped[int] = mapped_column(Integer, default=0)
    neutral_count: Mapped[int] = mapped_column(Integer, default=0)
    bull_pct: Mapped[float] = mapped_column(Float, default=0.0)
    bear_pct: Mapped[float] = mapped_column(Float, default=0.0)
    neutral_pct: Mapped[float] = mapped_column(Float, default=0.0)
    sentiment_avg: Mapped[float] = mapped_column(Float, default=0.0)  # -1..1
    mood_label: Mapped[str] = mapped_column(String(16), default="neutral")
    engagement: Mapped[int] = mapped_column(Integer, default=0)  # 互动代理
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class GrTicker(Base):
    __tablename__ = "gr_ticker"
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True)
    name_en: Mapped[str] = mapped_column(String(96), default="")
    name_zh: Mapped[str] = mapped_column(String(64), default="")
    regions_present: Mapped[int] = mapped_column(Integer, default=0)  # 有数据的区数(post_count>0)
    total_posts: Mapped[int] = mapped_column(Integer, default=0)
    avg_sentiment: Mapped[float] = mapped_column(Float, default=0.0)  # 跨区平均
    consensus: Mapped[str] = mapped_column(String(16), default="")  # all_bull|all_bear|mixed|divergent|sparse
    spread: Mapped[float] = mapped_column(Float, default=0.0)  # 最大区−最小区 情绪差
    divergent_region: Mapped[str] = mapped_column(String(8), default="")  # 与其他区相反的区
    overview_zh: Mapped[str] = mapped_column(Text, default="")  # DeepSeek 跨区一句话（可选）
    overview_en: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class GrQuote(Base):
    # 各 gr 标的最新行情（pipeline `gr-quote` 从 Yahoo 抓；纯静态站随构建刷新，非逐笔实时）。
    __tablename__ = "gr_quote"
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True)
    price: Mapped[float] = mapped_column(Float, default=0.0)  # 最新价
    prev_close: Mapped[float] = mapped_column(Float, default=0.0)  # 前收
    change_pct: Mapped[float] = mapped_column(Float, default=0.0)  # 涨跌幅 %
    currency: Mapped[str] = mapped_column(String(8), default="USD")
    asof: Mapped[str] = mapped_column(String(32), default="")  # 数据时间（交易所时区字符串）
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


# --------------------- YouTube 观点（标的页正式模块；Gemini 视频理解 + 全语种纳入当地分析者） ---------------------
# 每标的近 24h、浏览量 > 阈值的视频；混合分析（top N 原生看视频 + 其余字幕文本）。隔离表 yt_*。
class YtVideo(Base):
    __tablename__ = "yt_video"
    id: Mapped[str] = mapped_column(String(20), primary_key=True)  # YouTube videoId
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    market: Mapped[str] = mapped_column(String(8), default="us", index=True)
    channel: Mapped[str] = mapped_column(String(160), default="")
    channel_id: Mapped[str] = mapped_column(String(40), default="")
    title: Mapped[str] = mapped_column(Text, default="")
    description: Mapped[str] = mapped_column(Text, default="")
    lang: Mapped[str] = mapped_column(String(8), default="")  # defaultAudioLanguage / 检测
    duration_s: Mapped[int] = mapped_column(Integer, default=0)
    view_count: Mapped[int] = mapped_column(Integer, default=0)
    like_count: Mapped[int] = mapped_column(Integer, default=0)
    comment_count: Mapped[int] = mapped_column(Integer, default=0)
    thumbnail: Mapped[str] = mapped_column(Text, default="")
    url: Mapped[str] = mapped_column(Text, default="")
    published_utc: Mapped[dt.datetime] = mapped_column(DateTime, index=True)
    analyzed: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    fetched_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class YtAnalysis(Base):
    __tablename__ = "yt_analysis"
    video_id: Mapped[str] = mapped_column(String(20), primary_key=True)  # → yt_video.id
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    mode: Mapped[str] = mapped_column(String(12), default="video")  # video(原生看) | transcript(字幕)
    stance: Mapped[str] = mapped_column(String(16), default="neutral")  # bull|bear|neutral
    sentiment: Mapped[float] = mapped_column(Float, default=0.0)  # -1..1
    conviction: Mapped[float] = mapped_column(Float, default=0.0)  # 0..1 该视频观点笃定度
    summary_zh: Mapped[str] = mapped_column(Text, default="")
    summary_en: Mapped[str] = mapped_column(Text, default="")
    key_points_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    key_points_en: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    price_target: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    model: Mapped[str] = mapped_column(String(48), default="")
    analyzed_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class YtTickerSummary(Base):
    __tablename__ = "yt_ticker_summary"
    __table_args__ = (UniqueConstraint("ticker", "market", name="uq_yt_ticker"),)
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    market: Mapped[str] = mapped_column(String(8), default="us")
    window_hours: Mapped[int] = mapped_column(Integer, default=24)
    video_count: Mapped[int] = mapped_column(Integer, default=0)
    analyzed_count: Mapped[int] = mapped_column(Integer, default=0)
    bull_count: Mapped[int] = mapped_column(Integer, default=0)
    bear_count: Mapped[int] = mapped_column(Integer, default=0)
    neutral_count: Mapped[int] = mapped_column(Integer, default=0)
    net_sentiment: Mapped[float] = mapped_column(Float, default=0.0)  # 浏览量加权净情绪
    mood_label: Mapped[str] = mapped_column(String(16), default="neutral")
    total_views: Mapped[int] = mapped_column(Integer, default=0)
    overview_zh: Mapped[str] = mapped_column(Text, default="")  # 跨视频汇总一段
    overview_en: Mapped[str] = mapped_column(Text, default="")
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class YtFulltext(Base):
    """YouTube 视频「完整内容还原」：Gemini 真看视频 → 优化后的全程口播（去口水/书面化/语序优化）
    + 关键画面理解（【画面：…】标注图表/数据/幻灯），供「不看视频也能读完整观点」。
    比 yt_analysis 的 tldr 重得多（长文本、需重看视频），独立表、按需生成（如只跑高讨论标的）。
    隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    """

    __tablename__ = "yt_fulltext"
    video_id: Mapped[str] = mapped_column(String(20), primary_key=True)  # → yt_video.id
    ticker: Mapped[str] = mapped_column(String(16), index=True)
    content_zh: Mapped[str] = mapped_column(Text, default="")  # 扁平全文（口播拼接，搜索/兜底用）
    content_en: Mapped[str] = mapped_column(Text, default="")  # flat full text (en)
    # 有序段落：[{type:'speech',text} | {type:'visual',sec,caption,frame}]——前端按此渲染
    # 口播=整段、关键画面=「文左·截图右」。frame=web/public 下相对路径（去重后保留的关键帧）。
    segments: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    model: Mapped[str] = mapped_column(String(48), default="")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolRefined(Base):
    """KOL 个体观点的「AI 提炼 + 双语」结果（标的页「个体观点·KOL」模块用）。

    覆盖文本源 reddit / x / xueqiu；YouTube 复用 yt_analysis（Gemini 已产出同形 summary+key_points）。
    一次 DeepSeek(LOW) 调用同时产出 zh+en 的「为什么看多/看空/中性」+ 2-3 条要点 —— 提炼与翻译合一。
    隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    """

    __tablename__ = "kol_refined"
    # PK 含 ticker：同一帖/推可能讨论多只标的，提炼是**按标的**的（prompt 带 ticker → 不同标的不同理由），
    # 故须按 (source,item_id,ticker) 分别存；ticker 另留独立 index 供 web 按标的查。
    source: Mapped[str] = mapped_column(String(12), primary_key=True)  # reddit | x | xueqiu
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 源生 id（posts.id / tweet_id / gr_post.id）
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    stance: Mapped[str] = mapped_column(String(16), default="neutral")  # bull | bear | neutral
    reason_zh: Mapped[str] = mapped_column(Text, default="")  # 一句话「为什么」（中）
    reason_en: Mapped[str] = mapped_column(Text, default="")  # one-sentence「why」（en）
    points_zh: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)  # 2-3 条要点（催化剂/数据/目标价/风险）
    points_en: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    # ta 实际说的最代表性那句（忠实翻译，非提炼）——建立可信度、可对照原帖。
    quote_zh: Mapped[str] = mapped_column(Text, default="")
    quote_en: Mapped[str] = mapped_column(Text, default="")
    # 原帖全文的**完整忠实翻译**（逐句直译、非提炼、非一句摘录）——「按视角·原帖流」的「译」选项展示。
    # 由独立步骤 kol_translate 产出（与提炼解耦），让英文/中文原帖对另一语读者可读。
    trans_zh: Mapped[str] = mapped_column(Text, default="")
    trans_en: Mapped[str] = mapped_column(Text, default="")
    created: Mapped[str] = mapped_column(String(32), default="")  # 源帖创建时间字符串（供时间窗过滤）
    lang_src: Mapped[str] = mapped_column(String(8), default="")  # 源语言（信息用）
    model: Mapped[str] = mapped_column(String(48), default="")
    refined_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolJudgment(Base):
    """KOL 个体观点的「买入/卖出(目标)价位 + 操作周期」结构化抽取（标的页：正文提炼行 + 整体数据时间线图）。

    覆盖文本源 reddit / x / xueqiu —— 从**原帖文本**里**只抽作者明确写明**的 买入价位 / 卖出·目标价位
    （**各支持区间** lo/hi，确切价则 lo==hi；"方向性目标价"并入卖出侧）+ 操作周期（原话双语 + 档 short/mid/long）；
    没写明一律 null/空（反臆造）。YouTube 不在此抽取，复用 yt_judgment（target + horizon，作者页已产）。
    一次 LOW(qwen-flash) 调用，读 kol_refine 的同一候选池（近 ~90 天）的原文；`created` 存下达日供时间轴。
    隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    PK 与 kol_refined 同构 (source,item_id,ticker)，web 用同一 join key 挂到观点上。
    """

    __tablename__ = "kol_judgment"
    source: Mapped[str] = mapped_column(String(12), primary_key=True)  # reddit | x | xueqiu
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 源生 id（同 kol_refined）
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    # 买入价位 / 卖出·目标价位，各支持**区间**(lo/hi；确切价 lo==hi)；"目标价"并入卖出侧。均 nullable、仅作者明说。
    buy_lo: Mapped[Optional[float]] = mapped_column(Float, nullable=True)   # 买入价位 区间下界
    buy_hi: Mapped[Optional[float]] = mapped_column(Float, nullable=True)   # 买入价位 区间上界
    sell_lo: Mapped[Optional[float]] = mapped_column(Float, nullable=True)  # 卖出/目标价位 区间下界
    sell_hi: Mapped[Optional[float]] = mapped_column(Float, nullable=True)  # 卖出/目标价位 区间上界
    price_raw: Mapped[str] = mapped_column(String(96), default="")          # 价格原文短语（保留区间/货币符号），语言无关
    # 操作周期：作者原话短语（双语，忠实语义）+ 归一档位 short|mid|long。无周期 → 空。
    horizon_zh: Mapped[str] = mapped_column(String(48), default="")
    horizon_en: Mapped[str] = mapped_column(String(64), default="")
    horizon_bucket: Mapped[str] = mapped_column(String(8), default="")  # short | mid | long | ""
    created: Mapped[str] = mapped_column(String(32), default="")  # 下达日（源帖创建时间，供时间轴 x）
    model: Mapped[str] = mapped_column(String(48), default="")
    tagged_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolViewpoint(Base):
    """KOL 个体观点的「视角分类」（标的页「个体观点·KOL」模块的『按视角』视图用）。

    对已蒸馏的观点（kol_refined 的 reddit/x/xueqiu + yt_analysis 的 youtube）用 AI(DeepSeek LOW)
    打一组「视角」标签——估值/业务成长/竞争/管理层/宏观/催化剂/资金盘面（7 选 1-3，按相关度排序，
    首个为主视角）。隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    PK 与 kol_refined 同构 (source,item_id,ticker)，web 用同一 join key 挂到观点上。
    """

    __tablename__ = "kol_viewpoint"
    source: Mapped[str] = mapped_column(String(12), primary_key=True)  # reddit | x | xueqiu | youtube
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 源生 id（同 kol_refined / yt_video.id）
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    # 有序视角键列表（primary 在前），取值 ∈ valuation|growth|competition|management|macro|catalyst|flows|other
    viewpoints: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    model: Mapped[str] = mapped_column(String(48), default="")
    classified_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolArgument(Base):
    """KOL 观点的「论点综合」（标的页『按视角』视图：每条视角下聚成几个论点）。

    在 kol_refined（提炼）+ kol_viewpoint（视角分类）之上再加一层 AI 综合：把同一
    (ticker, 视角, 立场) 下的多条已提炼观点，聚类成 1-3 个**不同论点**（同义合并、覆盖人数多的排前）。
    每个论点 = 一句主张 + 一句推理 + 支持它的观点列表（回指 kol_refined / yt_analysis 的 source+item_id，
    web 据此取每个支持者的头像/原话/原帖）。隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    """

    __tablename__ = "kol_argument"
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    lens: Mapped[str] = mapped_column(String(16), primary_key=True)  # 7 视角键（不含 other）
    stance: Mapped[str] = mapped_column(String(8), primary_key=True)  # bull | bear | neutral
    window: Mapped[str] = mapped_column(String(8), primary_key=True, default="14d")  # 时间窗：24h|3d|7d|14d|1mo
    rank: Mapped[int] = mapped_column(Integer, primary_key=True)  # 同组内序号 0..N（按支持人数排）
    claim_zh: Mapped[str] = mapped_column(Text, default="")  # 一句话主张（中）
    claim_en: Mapped[str] = mapped_column(Text, default="")  # one-sentence claim（en）
    detail_zh: Mapped[str] = mapped_column(Text, default="")  # 一句支撑推理（可空）
    detail_en: Mapped[str] = mapped_column(Text, default="")
    # 支持此论点的观点：[{"source":"reddit","item_id":"..."}]（回指 kol_refined / yt_analysis）
    supporters: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)
    support_count: Mapped[int] = mapped_column(Integer, default=0)  # 去重支持人数（展示/排序用）
    model: Mapped[str] = mapped_column(String(48), default="")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolNarrative(Base):
    """KOL 论点的「叙事编织」（标的页『按视角』视图顶层，第 1 层）。

    每个 (ticker, 视角, 立场) 一段：把该立场下的论点（kol_argument）编织成连贯、周全的叙事——
    论点是论据(第 2 层)、论点的 detail+原话是子论据(第 3 层)。与 kol_argument 同一次 AI 调用产出，保证忠实。
    隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    """

    __tablename__ = "kol_narrative"
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    lens: Mapped[str] = mapped_column(String(16), primary_key=True)  # 7 视角键
    stance: Mapped[str] = mapped_column(String(8), primary_key=True)  # bull | bear | neutral
    window: Mapped[str] = mapped_column(String(8), primary_key=True, default="14d")  # 时间窗：24h|3d|7d|14d|1mo
    lead_zh: Mapped[str] = mapped_column(Text, default="")   # 一句总述（lead）
    lead_en: Mapped[str] = mapped_column(Text, default="")
    points: Mapped[Optional[list]] = mapped_column(JSONText, nullable=True)  # [{zh,en,refs:[{source,item_id}]}] 每点带来源角标
    model: Mapped[str] = mapped_column(String(48), default="")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolRelevance(Base):
    """KOL 观点的「相关性打分」（标的页『按相关性』筛选用）。

    给『某帖文/视频 与 某只标的』打 0-100 相关度：是否真的在讨论/分析这只股票，还是仅顺带提及/
    列入名单/新闻转述带到。覆盖全部源 reddit/x/xueqiu/youtube（故独立成表、PK 同构 source+item_id+ticker；
    youtube 不在 kol_refined 也能挂）。隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    """

    __tablename__ = "kol_relevance"
    source: Mapped[str] = mapped_column(String(12), primary_key=True)  # reddit | x | xueqiu | youtube
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 源生 id（kol_refined / yt_video.id）
    ticker: Mapped[str] = mapped_column(String(16), primary_key=True, index=True)
    score: Mapped[int] = mapped_column(Integer, default=0)  # 0-100：与该标的的相关度（越高越相关）
    model: Mapped[str] = mapped_column(String(48), default="")
    scored_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


class KolQuality(Base):
    """KOL 观点的「帖子质量打分」（标的页『只看高质量』开关用）。

    给『一条帖文/视频』本身作为投资分析的**含金量**打 0-100：有没有实质分析/数据/逻辑/洞见，
    还是纯口号/喊单/情绪/一句话/灌水。与「相关性」正交（相关性=与某标的多相关；质量=这条本身好不好）。
    **质量与标的无关**，故 PK 只到 (source,item_id)——同一帖被多只标的引用时只打一次分。
    覆盖 reddit/x/xueqiu/youtube。隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    """

    __tablename__ = "kol_quality"
    source: Mapped[str] = mapped_column(String(12), primary_key=True)  # reddit | x | xueqiu | youtube
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)  # 源生 id（kol_refined / yt_video.id）
    score: Mapped[int] = mapped_column(Integer, default=0)  # 0-100：内容含金量（越高越有料）
    model: Mapped[str] = mapped_column(String(48), default="")
    scored_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)


ALL_TABLES = [
    Subreddit, Author, Post, Comment, TickerMeta, Mention, ItemAnalysis,
    TickerRollup, MarketMood, Trending, Narrative, NarrativeTicker,
    NarrativePost, DailyBrief,
    # 亚洲实验隔离表：进 ALL_TABLES 让 cloud-pull 能快照；不进 sync.SOURCE_TABLES。
    AsiaPost, AsiaAnalysis, AsiaTickerSummary, AsiaPrice,
    # 全球散户多区看板隔离表（同样进快照、不进 SOURCE_TABLES）。
    GrPost, GrTickerRegion, GrTicker, GrQuote,
    # YouTube 观点隔离表（同样进快照、不进 SOURCE_TABLES）。
    YtVideo, YtAnalysis, YtTickerSummary, YtFulltext,
    # KOL 个体观点「AI 提炼+双语」隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolRefined,
    # KOL 个体观点「视角分类」隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolViewpoint,
    # KOL 观点「论点综合」隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolArgument,
    # KOL 论点「叙事编织」隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolNarrative,
    # KOL 观点「相关性打分」隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolRelevance,
    # KOL 观点「帖子质量打分」隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolQuality,
    # KOL 观点「目标价+操作周期」结构化抽取隔离表（同样进快照、不进 SOURCE_TABLES）。
    KolJudgment,
]
