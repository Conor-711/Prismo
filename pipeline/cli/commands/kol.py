from __future__ import annotations

from ._utils import csv_values
from ...jobs.kol import (
    classify_viewpoints,
    extract_judgments,
    refine_opinions,
    score_quality,
    score_relevance,
    synthesize_arguments,
    translate_opinions,
)


def cmd_kol_refine(args):
    # KOL 个体观点 AI 提炼+双语（reddit/x/xueqiu/toss/yahoojp 文本源）→ kol_refined。YouTube 复用 yt_analysis。
    refine_opinions(
        sources=csv_values(getattr(args, "source", None)),
        per_source=args.per_source,
        only=csv_values(getattr(args, "only", None)),
        force=args.force,
        workers=args.workers,
        since_days=args.since_days,
    )


def cmd_kol_viewpoint(args):
    # KOL 个体观点 视角分类（7 选 1-3）→ kol_viewpoint。读已蒸馏的 kol_refined + yt_analysis。
    classify_viewpoints(
        only=csv_values(getattr(args, "only", None)),
        sources=csv_values(getattr(args, "source", None)),
        since_days=args.since_days,
        force=args.force,
        workers=args.workers,
        reclassify_other=getattr(args, "reclassify_other", False),
    )


def cmd_kol_judgment(args):
    # KOL 目标价+操作周期 抽取（reddit/x/xueqiu/toss/yahoojp 原帖文本，只抽明说）→ kol_judgment。YouTube 复用 yt_judgment。
    extract_judgments(
        sources=csv_values(getattr(args, "source", None)),
        per_source=args.per_source,
        only=csv_values(getattr(args, "only", None)),
        force=args.force,
        workers=args.workers,
        since_days=args.since_days,
    )


def cmd_kol_argument(args):
    # KOL 论点综合（每 标的×视角×立场 聚成 1-3 个论点）→ kol_argument。读 kol_refined+kol_viewpoint+yt_analysis。
    synthesize_arguments(only=csv_values(getattr(args, "only", None)), force=args.force, workers=args.workers)


def cmd_kol_translate(args):
    # KOL 原帖完整忠实翻译（逐句直译、不压缩）→ kol_refined.trans_zh/en。供「按视角·原帖流」的「译」选项。
    translate_opinions(
        sources=csv_values(getattr(args, "source", None)),
        per_source=args.per_source,
        only=csv_values(getattr(args, "only", None)),
        force=args.force,
        workers=args.workers,
        since_days=args.since_days,
    )


def cmd_kol_relevance(args):
    # KOL 相关性打分（每条帖文/视频 与标的的相关度 0-100）→ kol_relevance。供『按相关性』排序。
    score_relevance(
        sources=csv_values(getattr(args, "source", None)),
        per_source=args.per_source,
        only=csv_values(getattr(args, "only", None)),
        force=args.force,
        workers=args.workers,
        since_days=args.since_days,
        include_youtube=not args.no_youtube,
    )


def cmd_kol_quality(args):
    # KOL 帖子质量打分（每条帖文/视频本身的含金量 0-100，与标的无关）→ kol_quality。供『只看高质量』开关。
    score_quality(
        sources=csv_values(getattr(args, "source", None)),
        per_source=args.per_source,
        only=csv_values(getattr(args, "only", None)),
        force=args.force,
        workers=args.workers,
        since_days=args.since_days,
        include_youtube=not args.no_youtube,
    )


def register_commands(sub, root) -> None:
    sp = sub.add_parser("kol-refine")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu,toss,yahoojp；省略=全部")
    sp.add_argument("--per-source", type=int, default=40, help="每标的每源提炼前 N 条(按互动)，默认 40=前端各源 LIMIT")
    sp.add_argument("--since-days", type=int, default=20, help="只提炼近 N 天(匹配前端价格窗口)；0=不限")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=6, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重提炼全部（默认只补未提炼的）")
    sp.set_defaults(func=cmd_kol_refine)

    sp = sub.add_parser("kol-viewpoint")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔来源；省略=全部")
    sp.add_argument("--since-days", type=int, default=None, help="只分类近 N 天；省略=不限")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重分类全部（默认只补未分类的）")
    sp.add_argument("--reclassify-other", action="store_true", help="只重判当前 other 行（用新 prompt 把实质观点归到正确视角）")
    sp.set_defaults(func=cmd_kol_viewpoint)

    sp = sub.add_parser("kol-judgment")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu,toss,yahoojp；省略=全部")
    sp.add_argument("--per-source", type=int, default=40, help="每标的每源前 N 条(镜像提炼/展示范围)")
    sp.add_argument("--since-days", type=int, default=90, help="只抽近 N 天（默认 90=时间线窗口）；0=不限")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=6, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重抽全部（默认只补未抽的）")
    sp.set_defaults(func=cmd_kol_judgment)

    sp = sub.add_parser("kol-argument")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重综合全部（默认只补未综合的 标的×视角×立场 组）")
    sp.set_defaults(func=cmd_kol_argument)

    sp = sub.add_parser("kol-translate")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu,toss,yahoojp；省略=全部")
    sp.add_argument("--per-source", type=int, default=40, help="每标的每源前 N 条(镜像提炼/展示范围)")
    sp.add_argument("--since-days", type=int, default=20, help="只译近 N 天；0=不限")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=6, help="LLM 并发数")
    sp.add_argument("--force", action="store_true", help="重译全部（默认只补未译的）")
    sp.set_defaults(func=cmd_kol_translate)

    sp = sub.add_parser("kol-relevance")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu,toss,yahoojp；省略=全部(+youtube)")
    sp.add_argument("--per-source", type=int, default=200, help="每标的每源前 N 条(镜像展示范围)")
    sp.add_argument("--since-days", type=int, default=30, help="只打近 N 天；0=不限")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--no-youtube", action="store_true", help="跳过 youtube 源")
    sp.add_argument("--force", action="store_true", help="重打全部（默认只补未打分的）")
    sp.set_defaults(func=cmd_kol_relevance)

    sp = sub.add_parser("kol-quality")
    sp.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu,toss,yahoojp；省略=全部(+youtube)")
    sp.add_argument("--per-source", type=int, default=800, help="每标的每源前 N 条(镜像展示范围；质量按 source+item 去重)")
    sp.add_argument("--since-days", type=int, default=35, help="只打近 N 天；0=不限")
    sp.add_argument("--only", type=str, default=None, help="逗号分隔 ticker")
    sp.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    sp.add_argument("--no-youtube", action="store_true", help="跳过 youtube 源")
    sp.add_argument("--force", action="store_true", help="重打全部（默认只补未打分的）")
    sp.set_defaults(func=cmd_kol_quality)
