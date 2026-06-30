"""作者×标的「判断综合」：把**同一位 YouTube 博主**对**同一只标的**的多条视频观点，
综合成「整体立场 + 3-5 条关键判断」→ 本地 yt_creator_view 表。

供作者页「① 标的判断」**每只标的只显示一段综合**（而非把每条视频判断都铺开——太繁杂）。
**不重看视频、不重花 Gemini**：只读**已蒸馏**的 yt_analysis（summary + key_points + stance），
跑 **LOW 档（qwen-flash，便宜）** 做一次跨视频综合：**忠实合并去重、不臆造**。单视频的 pair 也综合
（等于把那一条压成几点关键判断），保证全站口径一致。

落自建侧表 `yt_creator_view`（裸 sqlite3、CREATE TABLE IF NOT EXISTS、不入 models.py——同 yt_digest/
yt_judgment 范式，免改 yt_analysis）。PK=(channel_id,ticker)；增量（pair 已在则跳过，`--force` 重跑）。

用法：pipeline/.venv/bin/python -m pipeline.analyze.youtube_creator_view [--force] [--only TICKER,...] [--workers N]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

from ..common import llm

DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))

SYSTEM = (
    "你是金融分析编辑。给你**同一位 YouTube 博主**对**同一只美股**的若干条视频观点"
    "（每条已蒸馏成 立场+摘要+要点，可能多空不一、时间不同）。请综合成这位博主对该标的的**整体判断**：\n"
    "1) stance：综合后的整体倾向 bull / bear / neutral（多条不一致时，按其主基调 + 较近视频的权重判断）。\n"
    "2) points：**3-5 条关键判断**，中英各一份（points_zh / points_en，一一对应）。每条一句话、具体、"
    "**合并去重**多条视频里重复的点，覆盖（有才写）：核心多空逻辑、关键催化剂/里程碑、目标价或价位看法、"
    "主要风险。按重要性排序。**忠实综合、只用给定材料，绝不臆造**。\n"
    '严格只输出 JSON：{"stance":"bull|bear|neutral","points_zh":["…"],"points_en":["…"]}'
)

_STANCE = {"bull", "bear", "neutral"}
_STANCE_ZH = {"bull": "看多", "bear": "看空", "neutral": "中性"}


def _points(raw) -> list[str]:
    try:
        a = json.loads(raw or "[]")
    except (json.JSONDecodeError, TypeError):
        return []
    return [str(x).strip() for x in a if str(x).strip()] if isinstance(a, list) else []


def _vid_block(i: int, day: str, stance: str, s_zh: str, s_en: str, kp_zh, kp_en) -> str:
    summary = (s_zh or "").strip() or (s_en or "").strip()
    pts = _points(kp_zh) or _points(kp_en)
    lines = [f"【视频{i + 1}｜{day}｜立场 {_STANCE_ZH.get(stance, stance)}】"]
    if summary:
        lines.append(f"摘要：{summary[:500]}")
    if pts:
        lines.append("要点：" + "；".join(p[:120] for p in pts[:5]))
    return "\n".join(lines)


def _ensure(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_creator_view (
             channel_id TEXT, ticker TEXT,
             stance TEXT, points_zh TEXT, points_en TEXT,
             n_videos INTEGER, model TEXT, tagged_at TEXT,
             PRIMARY KEY (channel_id, ticker))"""
    )


def _synthesize(key, vids) -> tuple[tuple, dict] | None:
    """单 (channel,ticker) 综合（线程内只做网络）。vids=已按时间倒序、最多取前 N 条。"""
    channel_id, ticker = key
    body = "\n\n".join(_vid_block(i, *v) for i, v in enumerate(vids))
    user = f"标的：{ticker}（同一博主 {len(vids)} 条视频，按时间倒序）：\n\n{body}"
    data = None
    for _ in range(3):  # LOW 偶发 JSON 截断/None → 重试
        data = llm.messages_json(llm.LOW, SYSTEM, user, max_tokens=900)
        if isinstance(data, dict) and (data.get("points_zh") or data.get("points_en")):
            break
    if not isinstance(data, dict):
        return None
    st = str(data.get("stance") or "").strip().lower()
    p_zh = [str(x).strip() for x in (data.get("points_zh") or []) if str(x).strip()][:5]
    p_en = [str(x).strip() for x in (data.get("points_en") or []) if str(x).strip()][:5]
    return key, {
        "stance": st if st in _STANCE else "neutral",
        "points_zh": p_zh,
        "points_en": p_en,
        "n_videos": len(vids),
    }


def run(force: bool = False, only: set[str] | None = None, workers: int = 8, per_pair: int = 8) -> int:
    if not llm.available(llm.LOW):
        print("[yt-view] ⚠ 缺 QWEN_API_KEY（LOW 档）→ 跳过")
        return 0
    con = sqlite3.connect(os.path.abspath(DB))
    _ensure(con)
    done = (
        {(r[0], r[1]) for r in con.execute("SELECT channel_id, ticker FROM yt_creator_view").fetchall()}
        if not force
        else set()
    )
    rows = con.execute(
        "SELECT v.channel_id, v.ticker, substr(v.published_utc,1,10) AS day, a.stance, "
        "       a.summary_zh, a.summary_en, a.key_points_zh, a.key_points_en "
        "  FROM yt_video v JOIN yt_analysis a ON a.video_id = v.id "
        " WHERE v.channel_id <> '' AND v.ticker <> '' "
        " ORDER BY v.channel_id, v.ticker, v.published_utc DESC"
    ).fetchall()
    groups: dict[tuple, list] = defaultdict(list)
    for ch, tk, day, stance, s_zh, s_en, kp_zh, kp_en in rows:
        groups[(ch, tk)].append((day, stance, s_zh, s_en, kp_zh, kp_en))
    todo = [
        (key, vids[:per_pair])
        for key, vids in groups.items()
        if key not in done and (not only or (key[1] or "").upper() in only)
    ]
    print(f"[yt-view] 计划 {len(todo)} 个(作者×标的)（已有 {len(done)} / 共 {len(groups)}；model={llm.model_label(llm.LOW)}）", flush=True)
    if not todo:
        con.close()
        return 0

    now = dt.datetime.now(dt.timezone.utc).isoformat()
    label = llm.model_label(llm.LOW)
    ok = fail = 0
    buf: list[tuple] = []

    def _flush() -> None:
        if not buf:
            return
        con.executemany(
            "INSERT OR REPLACE INTO yt_creator_view "
            "(channel_id,ticker,stance,points_zh,points_en,n_videos,model,tagged_at) "
            "VALUES (?,?,?,?,?,?,?,?)",
            buf,
        )
        con.commit()
        buf.clear()

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_synthesize, key, vids) for key, vids in todo]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                out = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [yt-view] ✗ {str(e)[:90]}", flush=True)
                continue
            if out is None:
                fail += 1
                continue
            (ch, tk), f = out
            buf.append((ch, tk, f["stance"], json.dumps(f["points_zh"], ensure_ascii=False),
                        json.dumps(f["points_en"], ensure_ascii=False), f["n_videos"], label, now))
            ok += 1
            if len(buf) >= 40:
                _flush()
            if i % 100 == 0:
                print(f"  [yt-view] …{i}/{len(todo)}（ok={ok} fail={fail}）", flush=True)
    _flush()
    print(f"[yt-view] 完成：{ok} 成功 / {fail} 失败 → yt_creator_view", flush=True)
    con.close()
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="重综合全部（默认只补未做的）")
    ap.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些")
    ap.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    a = ap.parse_args()
    run(force=a.force, only={x.strip().upper() for x in a.only.split(",")} if a.only else None, workers=a.workers)
