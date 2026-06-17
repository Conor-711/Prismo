"""让 AI「读懂帖子完整内容」后，把正文重排版为结构清晰、易读的 Markdown，
写入 `posts.selftext_fmt`（增量、幂等）。前端优先渲染 `selftext_fmt`，回退原文。

用法（需 .env 里有 ANTHROPIC_API_KEY）：
    python -m pipeline.analyze.format_posts            # 处理所有缺 selftext_fmt 的帖
    python -m pipeline.analyze.format_posts --limit 100 --min-len 400
"""
from __future__ import annotations

import argparse
import os
import sqlite3

from ..common.config import settings
from ..common.llm import MID, chat


def _db_path() -> str:
    url = getattr(settings, "database_url", "") or ""
    if url.startswith("sqlite:///"):
        return url[len("sqlite:///"):]
    return os.environ.get("SQLITE_PATH", "data/dev.db")


SYSTEM = (
    "你是资深金融内容编辑。先完整读懂这篇 Reddit 帖子，再把它重排版成结构清晰、便于快速阅读的 Markdown。规则："
    "① 用 `## 小标题` 把内容切成几个逻辑段落（标题要概括该段要点）；"
    "② 用 `**加粗**` 突出关键结论、数字、催化剂；用 `> 引用` 高亮一两句金句；用 `- 列表` 罗列并列要点；"
    "③ 用 `---` 分隔正文与结尾(TL;DR / 持仓 / 免责声明)；"
    "④ **保留全部原意、事实与语气**，不要新增或删改观点，不要杜撰数据；"
    "⑤ 保留 $TICKER、URL、人名、Markdown 链接原样；语言保持与原文一致（英文帖输出英文 Markdown）。"
    "只输出重排后的 Markdown 正文，不要任何解释或代码围栏。"
)


def run(limit: int | None, min_len: int):
    c = sqlite3.connect(_db_path())
    rows = c.execute(
        "SELECT id, selftext FROM posts "
        "WHERE selftext IS NOT NULL AND length(selftext) >= ? AND (selftext_fmt IS NULL OR selftext_fmt='') "
        + (f"LIMIT {int(limit)}" if limit else ""),
        (min_len,),
    ).fetchall()
    for pid, selftext in rows:
        out = chat(MID, SYSTEM, selftext, max_tokens=4000)
        out = (out or "").strip()
        if out.startswith("```"):
            out = out.strip("`")
            out = out.split("\n", 1)[1] if "\n" in out else out
        if out:
            c.execute("UPDATE posts SET selftext_fmt=? WHERE id=?", (out, pid))
            c.commit()
    print(f"format: {len(rows)} 篇正文已重排版。")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--min-len", type=int, default=400, help="只处理正文长度≥该值的帖（短帖无需排版）")
    args = ap.parse_args()
    run(args.limit, args.min_len)


if __name__ == "__main__":
    main()
