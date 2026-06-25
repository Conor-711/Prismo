"""KOL 观点 · 帖子质量打分（标的页『只看高质量』开关用）。

给『一条帖文/视频』本身作为投资分析的**含金量**打 0-100：实质分析/数据/逻辑/洞见 vs 纯口号/喊单/情绪/灌水。
与「相关性」正交（相关性=与某标的多相关；质量=这条本身好不好），**与标的无关** → 隔离表 `kol_quality`(PK source+item_id，
同一帖只打一次)。覆盖 reddit/x/xueqiu(展示全部) + youtube。便宜档 LOW(千问 qwen-flash)、输出极短。

增量(已打分跳过，--force 重打)。⚠ 本地 `DATABASE_URL=sqlite:///./data/dev.db` 直写 dev.db；上云需建表迁移 + cloud-pull。
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolQuality
from .kol_refine import DEFAULT_PER_SOURCE, DEFAULT_SINCE_DAYS, TEXT_SOURCES, _load
from .kol_relevance import _load_youtube

QUALITY_SYSTEM = (
    "你给『一条美股社区帖文/视频』本身作为投资分析的**含金量(质量)**打 0-100 分。"
    "**只看这条内容好不好，不看它与哪只股票多相关、也不看多空立场。**\n"
    "看：有没有实质分析、具体数据/数字/估值、逻辑链/因果论证、证据(财报/产品/事件)、非共识的洞见、对风险的权衡；"
    "还是只有口号/喊单/情绪/表情/一句话/转述/灌水。\n"
    "档位(**务必用满区间、按程度细分、别扎堆**)：\n"
    "85-100：罕见。深度分析，有数据+逻辑+证据，提出非共识洞见，甚至权衡风险；\n"
    "65-84：言之有物，有明确观点 + 具体理由/数据，但不算深度长文；\n"
    "45-64：有观点 + 简单理由，中规中矩；\n"
    "25-44：基本只有结论/情绪，理由很薄；\n"
    "1-24：纯口号/喊单/表情/一句话/灌水，几乎无信息量；\n"
    "0：无意义/广告/spam。\n"
    "仅输出 JSON，不要多余文字：{\"quality\": 整数}"
)


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
        for r in _load_youtube(only_set, since_days):
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
        data = llm.messages_json(llm.LOW, QUALITY_SYSTEM, f"内容：\n{r['txt'][:1500]}", max_tokens=60)
        return r, _norm(data)

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
