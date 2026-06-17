"""叙事聚类：把窗口内帖子聚成具名主题，关联代表标的与成员帖。

  - --mock：按 item_analysis 里已标注的中文主题分组（确定性，无需 API）。
  - 真实：用 Claude Sonnet 对高分帖做语义聚类。
"""
from __future__ import annotations

import datetime as dt
import re

from sqlalchemy import and_, delete, select

from ..common.config import settings
from ..common.db import session_scope, data_now
from ..common.models import (
    ItemAnalysis, Mention, Narrative, NarrativePost, NarrativeTicker, Post,
)


def _slug(name: str, i: int) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or f"theme-{i}"


def _load_window_posts(s, cutoff, market):
    rows = s.execute(
        select(Post.id, Post.title, Post.score, Post.permalink, Post.subreddit_id,
               ItemAnalysis.sentiment_score, ItemAnalysis.stance, ItemAnalysis.themes,
               ItemAnalysis.tickers, ItemAnalysis.quality_score)
        .join(ItemAnalysis, and_(ItemAnalysis.item_id == Post.id, ItemAnalysis.item_type == "post"))
        .where(Post.created_utc >= cutoff, Post.market == market, Post.source == "scan")
    ).all()
    return rows


def run_narratives(mock: bool = False, min_posts: int = 2, market: str = "us") -> int:
    now = data_now(market)  # 按 market 各自锚定，避免另一市场更新时本市场落在窗口外
    cutoff = now - dt.timedelta(hours=settings.mindshare_window_hours)

    with session_scope() as s:
        rows = _load_window_posts(s, cutoff, market)

        if mock:
            groups = _cluster_by_theme(rows)
        else:
            groups = _cluster_by_llm(rows)
            if not groups:
                # deepseek-v4 推理型对该任务偶发返回空 content（思维链占满预算却不产出答案）→
                # 回退确定性主题分组，保证叙事区永不为空（仍是今日真实数据，只是按已标注主题分组）。
                print(f"[narratives] LLM 聚类为空，回退主题分组（market={market}）。")
                groups = _cluster_by_theme(rows)

        # 只清空本 market 的旧叙事（保留另一 market）
        old_ids = [r[0] for r in s.execute(
            select(Narrative.id).where(Narrative.market == market)).all()]
        if old_ids:
            s.execute(delete(NarrativeTicker).where(NarrativeTicker.narrative_id.in_(old_ids)))
            s.execute(delete(NarrativePost).where(NarrativePost.narrative_id.in_(old_ids)))
            s.execute(delete(Narrative).where(Narrative.market == market))
        s.flush()

        kept = 0
        groups.sort(key=lambda g: -g["heat"])
        # cn 看板：叙事的代表标的也只保留中概/港股/A 股宇宙，剔除主题里顺带提到的美股(NVDA/MSFT...)。
        if market == "cn":
            from ..common.models import TickerMeta
            cn_uni = {r[0] for r in s.execute(
                select(TickerMeta.ticker).where(TickerMeta.market == "cn")).all()}
            for g in groups:
                g["tickers"] = [(t, w) for (t, w) in g["tickers"] if t in cn_uni]
        for i, g in enumerate(groups):
            if len(g["post_ids"]) < min_posts:
                continue
            nar = Narrative(
                market=market,
                slug=_slug(g["name"], i), name=g["name"], summary=g["summary"],
                period_start=cutoff, period_end=now, post_count=len(g["post_ids"]),
                ticker_count=len(g["tickers"]), heat=round(g["heat"], 2),
                model=g["model"], created_at=now,
            )
            s.add(nar)
            s.flush()  # 拿到 id
            for tk, w in g["tickers"][:8]:
                s.add(NarrativeTicker(narrative_id=nar.id, ticker=tk, weight=round(w, 3)))
            for pid in g["post_ids"][:12]:
                s.add(NarrativePost(narrative_id=nar.id, post_id=pid))
            kept += 1

    print(f"[narratives] 生成 {kept} 个叙事（mock={mock}）。")
    return kept


def _cluster_by_theme(rows) -> list[dict]:
    """按已标注主题分组。"""
    buckets: dict[str, dict] = {}
    for (pid, title, score, perm, sub, sent, stance, themes, tickers, q) in rows:
        for theme in (themes or []):
            b = buckets.setdefault(theme, dict(name=theme, post_ids=[], heat=0.0,
                                               tw={}, sents=[], model="mock-theme-0.1"))
            b["post_ids"].append(pid)
            b["heat"] += float(score or 0)
            b["sents"].append(sent or 0.0)
            for t in (tickers or []):
                b["tw"][t["ticker"]] = b["tw"].get(t["ticker"], 0.0) + float(t.get("relevance", 0.5))
    out = []
    for theme, b in buckets.items():
        tickers = sorted(b["tw"].items(), key=lambda x: -x[1])
        avg = sum(b["sents"]) / len(b["sents"]) if b["sents"] else 0.0
        tone = "偏多" if avg > 0.15 else "偏空" if avg < -0.15 else "中性"
        top = "、".join(t for t, _ in tickers[:5]) or "—"
        b["summary"] = f"近 {settings.mindshare_window_hours}h 有 {len(b['post_ids'])} 篇讨论聚焦「{theme}」，整体{tone}（情绪 {avg:+.2f}）。代表标的：{top}。"
        b["tickers"] = tickers
        out.append(b)
    return out


def _clean_title(t: str) -> str:
    """压平标题：去换行、压空白、截断。原始标题里的换行/超长文本会让 deepseek 推理型
    偶发返回空 content（思维链占满 max_tokens 却不产出答案）。"""
    return re.sub(r"\s+", " ", (t or "")).strip()[:140]


def _cluster_by_llm(rows, retries: int = 3) -> list[dict]:
    """中档任务：对高分帖语义聚类（DeepSeek deepseek-v4-pro），返回与 mock 相同结构。

    deepseek-v4 推理型对该任务偶发返回空 content（思维链占满 max_tokens），故做三重防护：
    ① 只取 top-24 + 压平标题，降低推理负担；② clean prompt（示例本身是合法 JSON、要求不带代码块）；
    ③ 空结果重试。仍空则返回 []，由 run_narratives 回退主题分组，保证叙事区永不为空。
    """
    from ..common.llm import MID, messages_json, model_label

    items = sorted(rows, key=lambda r: -(float(r[2] or 0) * float(r[9] or 0.5)))[:24]
    lines = []
    for r in items:
        tks = ",".join(t["ticker"] for t in (r[8] or [])[:5])
        lines.append(f"- id={r[0]} | {_clean_title(r[1])}" + (f" | {tks}" if tks else ""))
    listing = "\n".join(lines)
    system = (
        "你是美股舆情分析师。把下列 Reddit 帖子聚成 4~8 个有意义的具名主题(叙事)，"
        "每个主题给：中文名称、一句话中文摘要、成员帖 id 列表、相关股票代码。"
        '只输出 JSON（不要解释、不要代码块）：{"narratives":[{"name":"主题名",'
        '"summary":"一句话摘要","post_ids":["id1","id2"],"tickers":["NVDA"]}]}。'
        "post_ids 只能用上面给出的 id。"
    )
    data = None
    for _ in range(max(1, retries)):
        data = messages_json(MID, system, listing, max_tokens=3000)
        if data and data.get("narratives"):
            break
    label = model_label(MID)
    score_map = {r[0]: float(r[2] or 0) for r in rows}
    out = []
    for n in (data or {}).get("narratives", []):
        pids = [p for p in n.get("post_ids", []) if p in score_map]
        if not pids:
            continue
        out.append(dict(
            name=n.get("name", "未命名"), summary=n.get("summary", ""), post_ids=pids,
            heat=sum(score_map[p] for p in pids),
            tickers=[(t, 1.0) for t in n.get("tickers", [])],
            model=label,
        ))
    return out


if __name__ == "__main__":
    import sys
    run_narratives(mock="--mock" in sys.argv)
