"""每日 AI 简报：「Reddit 在说什么」。聚合当日事实，输出带原帖链接的 markdown。

  - --mock：用库内事实确定性拼装。
  - 真实：把事实喂给 Claude（Sonnet/Opus）润色成简报。
"""
from __future__ import annotations

import datetime as dt

from sqlalchemy import and_, select

from ..common.config import settings
from ..common.db import session_scope
from ..common.models import (
    DailyBrief, ItemAnalysis, MarketMood, Narrative, NarrativeTicker, Post, TickerRollup, Trending,
)

REDDIT = "https://www.reddit.com"


def _gather(s) -> dict:
    mood = s.execute(select(MarketMood).where(MarketMood.bucket == "window")).scalars().first()
    top_ms = s.execute(
        select(TickerRollup).where(TickerRollup.bucket == "window")
        .order_by(TickerRollup.mindshare_pct.desc()).limit(8)
    ).scalars().all()
    spikes = s.execute(
        select(Trending).where(Trending.window == "24h", Trending.is_spike == True)  # noqa: E712
        .order_by(Trending.rank).limit(6)
    ).scalars().all()
    narrs = s.execute(select(Narrative).order_by(Narrative.heat.desc()).limit(5)).scalars().all()
    nar_tk = {}
    for n in narrs:
        nar_tk[n.id] = [t for (t,) in s.execute(
            select(NarrativeTicker.ticker).where(NarrativeTicker.narrative_id == n.id)
            .order_by(NarrativeTicker.weight.desc()).limit(5)).all()]
    posts = s.execute(
        select(Post.title, Post.permalink, Post.subreddit_id, ItemAnalysis.stance, ItemAnalysis.tldr)
        .join(ItemAnalysis, and_(ItemAnalysis.item_id == Post.id, ItemAnalysis.item_type == "post"))
        .order_by(ItemAnalysis.quality_score.desc(), Post.score.desc()).limit(6)
    ).all()
    return {"mood": mood, "top_ms": top_ms, "spikes": spikes, "narrs": narrs, "nar_tk": nar_tk, "posts": posts}


def _stance_cn(s: str) -> str:
    return {"bull": "看多", "bear": "看空"}.get(s, "中性")


def _markdown(date: str, g: dict) -> tuple[str, list]:
    m = g["mood"]
    lines = [f"# Reddit 美股舆情日报 · {date}", ""]
    highlights = []
    if m:
        lines += [f"**市场情绪：{m.label}（{m.mood_score:+.2f}）** — 多 {m.bull_pct:.0f}% / 空 {m.bear_pct:.0f}% / 中 {m.neutral_pct:.0f}%，"
                  f"窗口内 {m.total_posts} 帖、{m.total_mentions} 次提及。", ""]
        highlights.append(f"市场情绪 {m.label}（{m.mood_score:+.2f}）")

    lines.append("## 🔥 最受关注")
    for t in g["top_ms"]:
        lines.append(f"- **{t.ticker}** · mindshare {t.mindshare_pct:.1f}% · 情绪 {t.sentiment_avg:+.2f} · {t.mention_count} 次提及")
    if g["top_ms"]:
        highlights.append(f"声量第一：{g['top_ms'][0].ticker}（{g['top_ms'][0].mindshare_pct:.1f}%）")
    lines.append("")

    if g["spikes"]:
        lines.append("## 📈 异动飙升")
        for t in g["spikes"]:
            lines.append(f"- **{t.ticker}** · z={t.zscore:+.2f} · 24h {t.mention_count} 次提及 · 情绪 {t.sentiment_avg:+.2f}")
        highlights.append(f"异动：{g['spikes'][0].ticker}（z={g['spikes'][0].zscore:+.2f}）")
        lines.append("")

    if g["narrs"]:
        lines.append("## 🧩 主导叙事")
        for n in g["narrs"]:
            tks = "、".join(g["nar_tk"].get(n.id, [])) or "—"
            lines += [f"### {n.name}", f"{n.summary}", f"_代表标的：{tks}_", ""]
        highlights.append(f"主导叙事：{g['narrs'][0].name}")

    lines.append("## 📝 高信号帖子")
    for (title, perm, sub, stance, tldr) in g["posts"]:
        lines.append(f"- [{title}]({REDDIT}{perm}) · r/{sub} · {_stance_cn(stance)}")
    lines.append("")
    lines.append("> 本简报由 Reddit 公开帖子聚合生成，仅供研究，不构成投资建议。")
    return "\n".join(lines), highlights


def run_brief(mock: bool = False) -> str:
    date = dt.date.today().isoformat()
    with session_scope() as s:
        g = _gather(s)
        md, highlights = _markdown(date, g)
        model = "mock-brief-0.1"

        if not mock:
            # 中档任务：日报润色 → DeepSeek deepseek-v4-pro（经统一档位路由层）。
            from ..common.llm import MID, chat, model_label
            system = ("你是专业美股舆情编辑。根据给定事实，写一篇简洁、专业、中立的中文《Reddit 美股舆情日报》"
                      "（markdown，含：市场情绪一句话、最受关注、异动、主导叙事、值得一读的帖子）。"
                      "保留所有原帖链接，不杜撰数据，不构成投资建议。")
            md = chat(MID, system, md, max_tokens=1800)
            model = model_label(MID)

        title = f"Reddit 美股舆情日报 · {date}"
        existing = s.execute(select(DailyBrief).where(DailyBrief.brief_date == date)).scalars().first()
        if existing:
            existing.title, existing.markdown, existing.highlights, existing.model = title, md, highlights, model
            existing.created_at = dt.datetime.utcnow()
        else:
            s.add(DailyBrief(brief_date=date, title=title, markdown=md, highlights=highlights, model=model))
    print(f"[brief] 生成简报 {date}（mock={mock}），{len(md)} 字。")
    return md


if __name__ == "__main__":
    import sys
    run_brief(mock="--mock" in sys.argv)
