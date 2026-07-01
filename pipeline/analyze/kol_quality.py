"""KOL 观点 · 帖子质量打分（标的页『只看高质量』开关用）。

给『一条帖文/视频』本身作为投资分析的**含金量**打 0-100：实质分析/数据/逻辑/洞见 vs 纯口号/喊单/情绪/灌水。
与「相关性」正交（相关性=与某标的多相关；质量=这条本身好不好），**与标的无关** → 隔离表 `kol_quality`(PK source+item_id，
同一帖只打一次)。覆盖 reddit/x/xueqiu(展示全部) + youtube。便宜档 LOW(千问 qwen-flash)、输出极短。

增量(已打分跳过，--force 重打)。⚠ 本地 `DATABASE_URL=sqlite:///./data/dev.db` 直写 dev.db；上云需建表迁移 + cloud-pull。
"""
from __future__ import annotations

import json
import re
import datetime as dt
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolQuality
from .kol_refine import DEFAULT_PER_SOURCE, DEFAULT_SINCE_DAYS, TEXT_SOURCES, _load

QUALITY_SYSTEM = (
    "你给『一条美股社区帖文/视频』本身作为投资分析的**含金量(质量)**打 0-100 分。"
    "**只看内容质量，不看它与哪只股票多相关、也不看多空立场是否正确。**\n"
    "高质量必须是可审计的投资分析：有明确 thesis，并至少具备两类实质内容："
    "具体数据/估值/财报指标、因果逻辑链、可验证证据或来源、情景/反方风险、同业或历史比较。\n"
    "反之，以下内容即使有数字也不是高质量：短句喊单、标题党、新闻转述、只列目标价、只说涨跌、"
    "模板化『大师/框架/量化工具打分』但没有来源与假设、作者自推工具/订阅/群组、纯情绪或广告。\n"
    "YouTube 要根据摘要、目录和完整口播节选判断；有完整论证的视频可给高分，"
    "但 shorts/新闻快讯/只在标题或简介提到标的的视频要低分。\n"
    "档位务必用满区间：\n"
    "85-100：深度研究，有数据+逻辑+证据+风险权衡，信息密度高；\n"
    "65-84：有明确观点和多条具体理由/数据，能支撑投资判断；\n"
    "45-64：有观点和少量理由，但论证浅、证据不足或主要是复述；\n"
    "25-44：基本只有结论/事件/目标价，理由很薄；\n"
    "1-24：纯喊单、标题党、广告、灌水、几乎无投资信息；0：无意义/spam。\n"
    "仅输出 JSON，不要多余文字：{\"quality\": 整数}"
)

_FRAMEWORK_RE = re.compile(r"\b(buffett|graham|lynch|greenblatt|munger|fisher|value investing frameworks?)\b", re.I)
_PROMO_RE = re.compile(
    r"\b(my tool|built a tool|discord|patreon|newsletter|subscribe|free trial|course|join my|dm me|link in bio|premium)\b",
    re.I,
)
_HYPE_RE = re.compile(r"\b(skyrocket|moon|explode|100x|next stop|must buy|load up|can't miss|only \d+ hours?)\b", re.I)


def _json_list(raw) -> list[str]:
    try:
        data = json.loads(raw or "[]")
    except (TypeError, json.JSONDecodeError):
        return []
    if not isinstance(data, list):
        return []
    out: list[str] = []
    for x in data:
        if isinstance(x, dict):
            s = " / ".join(str(x.get(k) or "").strip() for k in ("t_zh", "t_en", "seg") if x.get(k) is not None)
        else:
            s = str(x or "").strip()
        if s:
            out.append(s)
    return out


def _heuristic_cap(source: str, txt: str) -> int:
    """Deterministic ceiling for patterns the LLM tends to over-credit."""
    t = (txt or "").strip()
    low = t.lower()
    words = re.findall(r"[\w$%.-]+", t)
    cap = 100
    if source != "youtube":
        if len(words) < 18:
            cap = min(cap, 35)
        elif len(words) < 45:
            cap = min(cap, 50)
        if _PROMO_RE.search(t):
            cap = min(cap, 45)
        if _FRAMEWORK_RE.search(t) and ("disclosure" in low or "tool" in low or "6 out of 7" in low):
            cap = min(cap, 55)
        if _HYPE_RE.search(t) and len(words) < 90:
            cap = min(cap, 45)
    else:
        has_transcript = "完整口播节选：" in t and len(t.split("完整口播节选：", 1)[1].strip()) >= 240
        has_digest = "投资者摘要：" in t and len(t.split("投资者摘要：", 1)[1].strip()) >= 80
        if not has_transcript and not has_digest:
            cap = min(cap, 45)
        if "仅据标题/简介推断" in t or "inferred from title only" in low:
            cap = min(cap, 45)
        if _HYPE_RE.search(t) and not has_transcript:
            cap = min(cap, 35)
    return cap


def _heuristic_floor(source: str, txt: str) -> int:
    """Minimum score for content with enough visible evidence, especially long-form YouTube analysis."""
    if source != "youtube":
        return 0
    t = txt or ""
    low = t.lower()
    digest_part = t.split("投资者摘要：", 1)[1] if "投资者摘要：" in t else ""
    transcript_part = t.split("完整口播节选：", 1)[1] if "完整口播节选：" in t else ""
    has_digest = len(digest_part.strip()) >= 240
    has_transcript = len(transcript_part.strip()) >= 900
    numbers = len(re.findall(r"(?:\$?\d+(?:\.\d+)?%?|\d+\s*(?:亿|万|billion|million|倍|x))", t, re.I))
    risk_terms = bool(re.search(r"风险|下跌|波动|指引|预期|估值|市盈率|margin|valuation|risk|guidance|earnings|target", low))
    if has_digest and has_transcript and numbers >= 6 and risk_terms:
        return 72
    if has_digest and has_transcript and numbers >= 3:
        return 68
    return 0


def _load_youtube_quality(only: set[str] | None, since_days: int) -> list[dict]:
    sql = """
        SELECT v.id AS item_id, v.ticker AS ticker, COALESCE(v.title,'') AS title,
               COALESCE(v.description,'') AS description, COALESCE(v.channel,'') AS channel,
               v.duration_s AS duration_s, v.view_count AS view_count, v.published_utc AS created,
               COALESCE(a.summary_zh,'') AS a_sz, COALESCE(a.summary_en,'') AS a_se,
               a.key_points_zh AS kp_zh, a.key_points_en AS kp_en,
               COALESCE(d.summary_zh,'') AS d_sz, COALESCE(d.summary_en,'') AS d_se,
               d.chapters AS chapters, COALESCE(f.content_zh,'') AS full_zh
          FROM yt_video v
          LEFT JOIN yt_analysis a ON a.video_id = v.id
          LEFT JOIN yt_digest d ON d.video_id = v.id
          LEFT JOIN yt_fulltext f ON f.video_id = v.id
         ORDER BY v.ticker, v.view_count DESC
    """
    with session_scope() as s:
        rows = [dict(r._mapping) for r in s.execute(text(sql))]
    cutoff = (dt.date.today() - dt.timedelta(days=since_days)).isoformat() if since_days > 0 else ""
    out: list[dict] = []
    for r in rows:
        tk = (r["ticker"] or "").upper()
        if only and tk not in only:
            continue
        if cutoff and str(r.get("created") or "")[:10] < cutoff:
            continue
        digest = _json_list(r.get("d_sz")) or _json_list(r.get("d_se"))
        points = _json_list(r.get("kp_zh")) or _json_list(r.get("kp_en"))
        chapters = _json_list(r.get("chapters"))
        parts = [
            "来源：youtube",
            f"标题：{r.get('title') or ''}",
            f"频道：{r.get('channel') or ''}；时长：{int(r.get('duration_s') or 0)} 秒；播放：{int(r.get('view_count') or 0)}",
        ]
        if r.get("a_sz") or r.get("a_se"):
            parts.append(f"AI观点摘要：{r.get('a_sz') or r.get('a_se')}")
        if points:
            parts.append("观点要点：" + "；".join(points[:6]))
        if digest:
            parts.append("投资者摘要：" + "；".join(digest[:7]))
        if chapters:
            parts.append("内容目录：" + "；".join(chapters[:8]))
        if r.get("full_zh"):
            parts.append("完整口播节选：" + str(r["full_zh"])[:2600])
        elif r.get("description"):
            parts.append("简介：" + str(r["description"])[:1000])
        txt = "\n".join(p for p in parts if p.strip())
        if len(txt) >= 12:
            out.append({"source": "youtube", "item_id": str(r["item_id"]), "ticker": tk, "txt": txt})
    return out


def _ensure_table() -> None:
    KolQuality.__table__.create(engine, checkfirst=True)


def _norm(d: dict | None) -> int | None:
    if not isinstance(d, dict):
        return None
    v = d.get("quality")
    if v is None:
        return None
    try:
        n = int(round(float(v)))
    except (TypeError, ValueError):
        return None
    return max(0, min(100, n))


def _existing() -> set[tuple[str, str]]:
    with session_scope() as s:
        rows = s.execute(text("SELECT source, item_id FROM kol_quality")).all()
    return {(r[0], str(r[1])) for r in rows}


def score(sources: list[str] | None = None, per_source: int = DEFAULT_PER_SOURCE, only: list[str] | None = None,
          force: bool = False, workers: int = 8, since_days: int = DEFAULT_SINCE_DAYS,
          include_youtube: bool = True) -> int:
    _ensure_table()
    if not llm.available(llm.LOW):
        print("[kol-quality] 无 LOW 档 key(QWEN_API_KEY)，跳过。", flush=True)
        return 0
    srcs = [s for s in (sources or list(TEXT_SOURCES)) if s in TEXT_SOURCES]
    only_set = {t.strip().upper() for t in only} if only else None

    # 质量与标的无关 → 按 (source,item_id) 去重，同一帖只打一次（哪怕被多只标的引用）。
    seen: set[tuple[str, str]] = set()
    plan: list[dict] = []

    def _add(src: str, item_id: str, txt: str) -> None:
        key = (src, str(item_id))
        if key in seen:
            return
        seen.add(key)
        plan.append({"source": src, "item_id": str(item_id), "txt": txt})

    for src in srcs:
        for r in _load(src, per_source, only_set, since_days):
            _add(r["source"], r["item_id"], r["txt"])
    if include_youtube:
        for r in _load_youtube_quality(only_set, since_days):
            _add(r["source"], r["item_id"], r["txt"])

    if not force:
        have = _existing()
        plan = [r for r in plan if (r["source"], r["item_id"]) not in have]

    total = len(plan)
    label = llm.model_label(llm.LOW)
    print(f"[kol-quality] 计划 {total} 条(源 {','.join(srcs)}"
          f"{'+youtube' if include_youtube else ''}, per_source={per_source}, 近 {since_days} 天, "
          f"model={label}, force={force})", flush=True)
    if not total:
        return 0

    done = fail = skip = 0
    buf: list[tuple[dict, int]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:
            for r, sc in buf:
                s.merge(KolQuality(source=r["source"], item_id=r["item_id"], score=sc, model=label))
        done += len(buf)
        buf.clear()

    def _work(r: dict) -> tuple[dict, int | None]:
        cap = _heuristic_cap(r["source"], r["txt"])
        max_chars = 3600 if r["source"] == "youtube" else 1800
        data = llm.messages_json(
            llm.LOW,
            QUALITY_SYSTEM,
            f"来源：{r['source']}\n内容：\n{r['txt'][:max_chars]}",
            max_tokens=80,
        )
        floor = _heuristic_floor(r["source"], r["txt"])
        sc = _norm(data)
        return r, min(max(sc, floor), cap) if sc is not None else None

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, r) for r in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                r, sc = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [kol-quality] ✗ {str(e)[:90]}", flush=True)
                continue
            if sc is None:
                skip += 1
                continue
            buf.append((r, sc))
            if len(buf) >= 50:
                _flush()
            if i % 100 == 0:
                print(f"  [kol-quality] …{i}/{total}(done={done}+buf{len(buf)} skip={skip} fail={fail})", flush=True)
    _flush()

    print(f"[kol-quality] 完成 {done}(跳过 {skip}，失败 {fail})", flush=True)
    return done


if __name__ == "__main__":
    score(only=["NVDA"], per_source=10)
