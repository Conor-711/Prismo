"""YouTube 完整口播 → 「投资者摘要」+「内容目录(章节)」AI 提炼 → 本地 yt_digest 表。

供标的页 YouTube 正文(OpinionExplorer 阅读面板)的两个新模块：
  ① **投资者摘要**：把整段口播的精华与话题，提成 4-7 条分点摘要（zh/en），放在正文上方。
  ② **内容目录**：把口播按话题切成有序章节，每章一个短标题 + 起始**口播段落下标**(seg)，
     放在正文右侧；点标题→正文滚到该段（前端按 seg 在 YtFullContent 里埋锚点）。

输入 = `yt_fulltext.segments` 里的 **speech 段**（YtFullContent 实际渲染的那些，按出现顺序 0..n-1 编号）。
seg 必须指这个 speech 序号，前端锚点才对得上。模型：LOW 档（qwen-flash，便宜，读文本即可，无需重看视频）。
增量：已在 yt_digest 的视频跳过（`--force` 重跑）。直接读写**本地 dev.db**（同 author_avatars 范式）。

用法：pipeline/.venv/bin/python -m pipeline.analyze.youtube_digest [--force] [--only VIDEO_ID,...]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3

from ..common import llm

DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))

SYSTEM = (
    "你是投顾分析师，帮散户快速读懂一段财经 YouTube 视频的完整口播转录。"
    "给你按顺序编号的口播段落（speech），你产出两样东西：\n"
    "1) summary：把整段视频的**投资精华与关键话题**提成分点摘要——每点一句、具体（含数字/标的/观点/风险），"
    "4-7 点，按重要性排序；中英各一份（summary_zh / summary_en，一一对应）。\n"
    "2) chapters：把口播按话题切成 3-8 个**有序章节**，每章一个**短标题**（≤12 字 / ≤8 words，名词短语，概括该段话题），"
    "并给出该章**起始段落的编号 seg**（指上面 speech 的编号）。chapters 必须：第一章 seg=0、seg 严格递增、覆盖主要话题。\n"
    '严格只输出 JSON：{"summary_zh":["…"],"summary_en":["…"],'
    '"chapters":[{"t_zh":"标题","t_en":"Title","seg":0}]}'
)


def _speech(segments) -> list[str]:
    out = []
    for s in segments if isinstance(segments, list) else []:
        if isinstance(s, dict) and s.get("type") == "speech" and (s.get("text") or "").strip():
            out.append(str(s["text"]).strip())
    return out


def _numbered(speech: list[str], cap: int = 9000) -> str:
    lines, n = [], 0
    for i, t in enumerate(speech):
        block = t if len(t) <= 600 else t[:600] + "…"
        line = f"[{i}] {block}"
        n += len(line)
        if n > cap:
            break
        lines.append(line)
    return "\n".join(lines)


def _clean_chapters(raw, n_speech: int) -> list[dict]:
    """校验/夹紧章节：seg 落在 [0,n)、严格递增、首章补 0。"""
    out: list[dict] = []
    last = -1
    for c in raw if isinstance(raw, list) else []:
        if not isinstance(c, dict):
            continue
        try:
            seg = int(c.get("seg", 0))
        except (TypeError, ValueError):
            continue
        seg = max(0, min(seg, n_speech - 1))
        if seg <= last:
            seg = last + 1
        if seg >= n_speech:
            break
        t_zh = str(c.get("t_zh") or c.get("t_en") or "").strip()[:40]
        t_en = str(c.get("t_en") or c.get("t_zh") or "").strip()[:60]
        if not t_zh and not t_en:
            continue
        out.append({"t_zh": t_zh, "t_en": t_en, "seg": seg})
        last = seg
    if out and out[0]["seg"] != 0:
        out[0]["seg"] = 0
    return out


def _ensure(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_digest (
             video_id TEXT PRIMARY KEY, ticker TEXT,
             summary_zh TEXT, summary_en TEXT, chapters TEXT,
             model TEXT, tagged_at TEXT)"""
    )


def run(force: bool = False, only: set[str] | None = None) -> int:
    if not llm.available(llm.LOW):
        print("[yt-digest] ⚠ 缺 QWEN_API_KEY（LOW 档）→ 跳过")
        return 0
    con = sqlite3.connect(os.path.abspath(DB))
    _ensure(con)
    done = {r[0] for r in con.execute("SELECT video_id FROM yt_digest").fetchall()} if not force else set()
    rows = con.execute("SELECT video_id, ticker, segments FROM yt_fulltext WHERE segments IS NOT NULL AND segments <> ''").fetchall()
    todo = [r for r in rows if (not only or r[0] in only) and r[0] not in done]
    print(f"[yt-digest] 计划 {len(todo)} 视频（已有 {len(done)} / 共 {len(rows)}；model={llm.model_label(llm.LOW)}）", flush=True)

    now = dt.datetime.now(dt.timezone.utc).isoformat()
    ok = fail = 0
    for vid, ticker, seg_json in todo:
        try:
            speech = _speech(json.loads(seg_json or "[]"))
        except json.JSONDecodeError:
            speech = []
        if len(speech) < 2:
            continue
        data = None
        for _ in range(3):  # LOW 偶发 JSON 截断/None → 重试，绝不静默落空
            data = llm.messages_json(llm.LOW, SYSTEM, _numbered(speech), max_tokens=1100)
            if isinstance(data, dict) and (data.get("summary_zh") or data.get("chapters")):
                break
        if not isinstance(data, dict):
            fail += 1
            print(f"  [yt-digest] {vid} 失败（LLM 无有效 JSON）", flush=True)
            continue
        s_zh = [str(x).strip() for x in (data.get("summary_zh") or []) if str(x).strip()][:7]
        s_en = [str(x).strip() for x in (data.get("summary_en") or []) if str(x).strip()][:7]
        chapters = _clean_chapters(data.get("chapters"), len(speech))
        con.execute(
            "INSERT OR REPLACE INTO yt_digest (video_id,ticker,summary_zh,summary_en,chapters,model,tagged_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (vid, ticker, json.dumps(s_zh, ensure_ascii=False), json.dumps(s_en, ensure_ascii=False),
             json.dumps(chapters, ensure_ascii=False), llm.model_label(llm.LOW), now),
        )
        con.commit()
        ok += 1
        print(f"  [yt-digest] {vid}: {len(s_zh)} 摘要 · {len(chapters)} 章节 ✓", flush=True)

    print(f"[yt-digest] 完成：{ok} 成功 / {fail} 失败 → yt_digest", flush=True)
    con.close()
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", type=str, default=None, help="逗号分隔 video_id")
    a = ap.parse_args()
    run(force=a.force, only={x.strip() for x in a.only.split(",")} if a.only else None)
