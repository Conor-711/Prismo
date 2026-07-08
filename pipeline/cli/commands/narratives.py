from __future__ import annotations

from ...jobs.narrative_rotation import build_narrative_rotation


def cmd_narrative_rotation(args):
    # 跨社区固定叙事轮动 → web/lib/data/narrativeRotation.json。读 gr_post/Reddit/X/YouTube，不用旧 narratives 表。
    build_narrative_rotation(
        db_path=args.db,
        out_path=args.out,
        window_days=args.window_days,
        recent_days=args.recent_days,
    )


def register_commands(sub, root) -> None:
    sp = sub.add_parser("narrative-rotation")
    sp.add_argument("--db", default=str(root / "data" / "dev.db"))
    sp.add_argument("--out", default=str(root / "web" / "lib" / "data" / "narrativeRotation.json"))
    sp.add_argument("--window-days", type=int, default=21)
    sp.add_argument("--recent-days", type=int, default=7)
    sp.set_defaults(func=cmd_narrative_rotation)
