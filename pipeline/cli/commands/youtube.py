from __future__ import annotations

from ._utils import csv_values
from ...jobs.youtube import (
    analyze_text,
    analyze_videos,
    build_creator_view,
    build_digest,
    crawl_videos,
    extract_judgment,
    generate_fulltext,
    refresh_channels,
)


def cmd_youtube_crawl(args):
    # YouTube 观点：按标的搜近 24h、浏览量>阈值的视频 → yt_video（全语种）。缺 key/--mock 出样本。
    crawl_videos(
        only=csv_values(getattr(args, "only", None)),
        since_hours=args.since_hours,
        min_views=args.min_views,
        per_ticker_results=args.per_ticker_results,
        max_pages=args.max_pages,
        mock=args.mock,
    )


def cmd_yt_channels(args):
    # YouTube 频道作者基础信息（粉丝/视频/简介）→ 本地 yt_channel。Data API channels.list；需 YOUTUBE_API_KEY。
    refresh_channels()


def cmd_youtube_tag(args):
    # 混合分析（top N 原生看视频 + 其余字幕）→ yt_analysis + 聚合 yt_ticker_summary。缺 key/--mock 出样本。
    analyze_videos(
        top_native=args.top_native,
        only_new=not args.force,
        mock=args.mock,
        per_ticker_cap=args.per_ticker,
        workers=args.workers,
        only=csv_values(getattr(args, "only", None)),
    )


def cmd_youtube_tag_text(args):
    # 无 Gemini 配额兜底：标题+简介 → DeepSeek flash 出双语观点 → yt_analysis(mode=text)。
    analyze_text(per_ticker=args.per_ticker, workers=args.workers)


def cmd_youtube_fulltext(args):
    # Gemini 真看视频 → 完整内容还原（优化字幕+关键画面）→ yt_fulltext。
    generate_fulltext(
        only=csv_values(getattr(args, "only", None), as_set=True),
        per_ticker=args.per_ticker,
        workers=args.workers,
        force=args.force,
        low_res=args.low_res,
        frames=not getattr(args, "no_frames", False),
        limit=getattr(args, "limit", None),
        max_native_min=getattr(args, "max_native_min", 150),
        fail_after=getattr(args, "fail_after", 3),
        max_rate_waits=getattr(args, "max_rate_waits", 4),
    )


def cmd_youtube_digest(args):
    # YouTube 完整口播 → 投资者摘要 + 内容目录(章节) → 本地 yt_digest（LOW 档读文本，不重看视频）。
    build_digest(
        force=args.force,
        only=csv_values(getattr(args, "only", None), as_set=True),
        workers=getattr(args, "workers", 1),
    )


def cmd_youtube_judgment(args):
    # 从已有 yt_analysis 观点/论据抽「时间周期/目标价/关键位置」→ 本地 yt_judgment（LOW 档纯文本，不重看视频）。
    extract_judgment(
        force=args.force,
        workers=args.workers,
        only=csv_values(getattr(args, "only", None), upper=True, as_set=True),
    )


def cmd_youtube_creator_view(args):
    # 把同一博主对同一标的的多条视频判断综合成「整体立场+几点关键判断」→ 本地 yt_creator_view（LOW 档，不重看视频）。
    build_creator_view(
        force=args.force,
        workers=args.workers,
        only=csv_values(getattr(args, "only", None), upper=True, as_set=True),
    )


def register_commands(sub, root) -> None:
    sp = sub.add_parser("youtube-crawl")
    sp.add_argument("--since-hours", type=int, default=24)
    sp.add_argument("--min-views", type=int, default=None, help="浏览量门槛，省略=用 YT_MIN_VIEWS(默认1000)")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--per-ticker-results", type=int, default=50, help="每个搜索页返回条数，YouTube 上限 50")
    sp.add_argument("--max-pages", type=int, default=2, help="每标的搜索分页数")
    sp.add_argument("--mock", action="store_true", help="无 key 时生成多语种样本")
    sp.set_defaults(func=cmd_youtube_crawl)

    sub.add_parser("yt-channels").set_defaults(func=cmd_yt_channels)

    sp = sub.add_parser("youtube-tag")
    sp.add_argument("--top-native", type=int, default=2, help="每标的用 Gemini 原生看视频的前 N 条（其余走字幕）")
    sp.add_argument("--per-ticker", type=int, default=None, help="每标的最多分析前 N 条(按播放量)；省略=全部。配合 8h/天预算用，按档位跨标的铺开")
    sp.add_argument("--force", action="store_true", help="重分析全部（默认只分析未分析的）")
    sp.add_argument("--workers", type=int, default=1, help="并发线程数(>1 走并发真看视频，billing 解锁 8h 后用)")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些（如前十讨论度）")
    sp.add_argument("--mock", action="store_true")
    sp.set_defaults(func=cmd_youtube_tag)

    sp = sub.add_parser("youtube-tag-text")
    sp.add_argument("--per-ticker", type=int, default=20, help="每标的按播放量取前 N（默认 20=前端 LIMIT）")
    sp.add_argument("--workers", type=int, default=6, help="LLM 并发数")
    sp.set_defaults(func=cmd_youtube_tag_text)

    sp = sub.add_parser("youtube-fulltext")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些（如 PLTR）")
    sp.add_argument("--per-ticker", type=int, default=10, help="每标的按播放量取前 N")
    sp.add_argument("--workers", type=int, default=4)
    sp.add_argument("--limit", type=int, default=None, help="本轮最多处理 N 条（用于长任务分批）")
    sp.add_argument("--max-native-min", type=int, default=150, help="允许 Gemini 原生视频处理的最长分钟数")
    sp.add_argument("--fail-after", type=int, default=3, help="同一视频失败/无段落达到 N 次后本轮跳过；0=不跳过")
    sp.add_argument("--max-rate-waits", type=int, default=4, help="Gemini 429 限流时最多等待次数")
    sp.add_argument("--low-res", action="store_true", help="低清看视频(省 token，图表细节略差)")
    sp.add_argument("--no-frames", action="store_true", help="只出优化口播、不抽关键画面帧(快、免下载)")
    sp.add_argument("--force", action="store_true", help="重生成已有的")
    sp.set_defaults(func=cmd_youtube_fulltext)

    sp = sub.add_parser("youtube-digest")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 video_id")
    sp.add_argument("--force", action="store_true", help="重跑已有的")
    sp.add_argument("--workers", type=int, default=1, help="LLM 并发数")
    sp.set_defaults(func=cmd_youtube_digest)

    sp = sub.add_parser("youtube-judgment")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重抽已有的")
    sp.set_defaults(func=cmd_youtube_judgment)

    sp = sub.add_parser("youtube-creator-view")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重综合已有的")
    sp.set_defaults(func=cmd_youtube_creator_view)
