"""KOL 观点 · 相关性打分（标的页『按相关性』筛选/排序用）。

给『一条帖文/视频 与 指定标的』打 0-100 相关度：是否真的在讨论/分析这只股票，还是仅顺带提及/
列入一串名单/新闻转述带到。**分数越高越相关**。覆盖 reddit/x/xueqiu（kol_refined 已展示项）
+ youtube（yt_analysis）→ 隔离表 `kol_relevance`(PK source+item_id+ticker)。

便宜档 LOW(千问 qwen-flash)，输出极短(一个数)。与提炼/翻译解耦、可独立重跑；增量(已打分跳过，--force 重打)。
⚠ 本地测试 `DATABASE_URL=sqlite:///./data/dev.db` 直写 dev.db(sqlite 自动建表)；上云需建表迁移 + cloud-pull。
"""
from __future__ import annotations

import datetime as dt
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import bindparam, text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolRelevance
from .kol_refine import DEFAULT_PER_SOURCE, DEFAULT_SINCE_DAYS, TEXT_SOURCES, _load

RELEVANCE_SYSTEM = (
    "你给『一条帖文/视频 与 一只指定美股』打**相关度**分(0-100 整数)。相关度**只衡量一件事：这只票在这条内容里的"
    "「中心程度」**——它是不是主角、占了多大篇幅。\n"
    "判断方法：把内容拆成几部分，**有多大比例真正在讲这只标的**？据此打分。\n"
    "档位：\n"
    "90-100：整条几乎都在讲这只票，它就是主角；\n"
    "70-89：这只票是主要话题(和另 1-2 只并列、但明显是重点之一)；\n"
    "40-69：只有一段在讲它，全文重点在别处(别的票 / 某网站 / 某方法 / 某赛道)；\n"
    "15-39：只在结尾或某一句里顺带提到、举例带过、或在一串名单里出现一次；\n"
    "1-14：只是冒出个名字/cashtag、几乎没真讲；0：完全无关。\n"
    "⚠ **关键：又长又有料 ≠ 相关。** 一篇深度长文，若主要在讲别的、只把这只标的当例子提一句，对这只标的的相关度仍然要打低。"
    "**完全不看帖子质量/深度/数据/立场**(那是别的维度)。\n"
    "示例(区分『中心』vs『举例』)：\n"
    "· 一条主要在介绍某数据网站怎么用、结尾说『具体例子看看 $PLTR 的走势』的帖 → 对 $PLTR 打 ~20(整篇在讲那网站/方法，PLTR 只是结尾举例)；\n"
    "· 一条『$PLTR 130 是未来几年最好买点，公司极盈利、AIP 是最大增长引擎，我在加仓』的帖 → 对 $PLTR 打 ~95(整条都在讲它)。\n"
    "**步骤：先用一句话写出『这条主要在讲什么』(about)，判断指定标的是不是这个主题的主角，再打分。**"
    "若 about 的主题不是这只标的本身(而是某网站/方法/赛道/别的票)，relevance 必须 ≤40。\n"
    "输出 JSON，不要多余文字：{\"about\":\"这条主要在讲什么，一句话\",\"relevance\":整数}"
)


def _ensure_table() -> None:
    KolRelevance.__table__.create(engine, checkfirst=True)


def _norm(d: dict | None) -> int | None:
    if not isinstance(d, dict):
        return None
    v = d.get("relevance")
    if v is None:
        return None
    try:
        n = int(round(float(v)))
    except (TypeError, ValueError):
        return None
    return max(0, min(100, n))


def _load_youtube(only: set[str] | None, since_days: int) -> list[dict]:
    """youtube 候选：yt_video⋈yt_analysis（title + summary 作为内容）。"""
    sql = """
        SELECT v.id AS item_id, v.ticker AS ticker, COALESCE(v.title,'') AS title,
               COALESCE(a.summary_zh,'') AS sz, COALESCE(a.summary_en,'') AS se, v.published_utc AS created
          FROM yt_video v JOIN yt_analysis a ON a.video_id = v.id
         ORDER BY v.ticker, v.published_utc DESC
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
        txt = (str(r.get("title") or "") + "\n" + (str(r.get("sz") or "") or str(r.get("se") or ""))).strip()
        if len(txt) >= 8:
            out.append({"source": "youtube", "item_id": str(r["item_id"]), "ticker": tk, "txt": txt})
    return out


def _refined_keys(sources: list[str], only: set[str] | None) -> set[tuple[str, str, str]]:
    stmt = text("SELECT source, item_id, ticker FROM kol_refined WHERE source IN :ss").bindparams(
        bindparam("ss", expanding=True))
    with session_scope() as s:
        rows = s.execute(stmt, {"ss": sources}).all()
    out = set()
    for r in rows:
        tk = str(r[2]).upper()
        if not only or tk in only:
            out.add((r[0], str(r[1]), tk))
    return out


def _existing(only: set[str] | None) -> set[tuple[str, str, str]]:
    with session_scope() as s:
        rows = s.execute(text("SELECT source, item_id, ticker FROM kol_relevance")).all()
    out = set()
    for r in rows:
        tk = str(r[2]).upper()
        if not only or tk in only:
            out.add((r[0], str(r[1]), tk))
    return out


def score(sources: list[str] | None = None, per_source: int = DEFAULT_PER_SOURCE, only: list[str] | None = None,
          force: bool = False, workers: int = 8, since_days: int = DEFAULT_SINCE_DAYS,
          include_youtube: bool = True) -> int:
    _ensure_table()
    if not llm.available(llm.LOW):
        print("[kol-relevance] 无 LOW 档 key(QWEN_API_KEY)，跳过。", flush=True)
        return 0
    srcs = [s for s in (sources or list(TEXT_SOURCES)) if s in TEXT_SOURCES]
    only_set = {t.strip().upper() for t in only} if only else None

    # 打**全部展示**的帖文（镜像 web getKolOpinions 的取数范围），不再只限已提炼项——
    # 否则 top-N 之外、被展示但未提炼的帖子会没有相关分。
    plan: list[dict] = []
    for src in srcs:
        for r in _load(src, per_source, only_set, since_days):
            plan.append({"source": r["source"], "item_id": str(r["item_id"]),
                         "ticker": (r["ticker"] or "").upper(), "txt": r["txt"]})
    if include_youtube:
        plan += _load_youtube(only_set, since_days)

    if not force:
        have = _existing(only_set)
        plan = [r for r in plan if (r["source"], r["item_id"], r["ticker"]) not in have]

    total = len(plan)
    label = llm.model_label(llm.LOW)
    print(f"[kol-relevance] 计划 {total} 条(源 {','.join(srcs)}"
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
        with session_scope() as s:  # 主线程单写者
            for r, sc in buf:
                s.merge(KolRelevance(source=r["source"], item_id=r["item_id"], ticker=r["ticker"],
                                     score=sc, model=label))
        done += len(buf)
        buf.clear()

    def _work(r: dict) -> tuple[dict, int | None]:
        data = llm.messages_json(llm.LOW, RELEVANCE_SYSTEM,
                                 f"标的：{r['ticker']}\n内容：\n{r['txt'][:1500]}", max_tokens=200)
        return r, _norm(data)

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, r) for r in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                r, sc = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [kol-relevance] ✗ {str(e)[:90]}", flush=True)
                continue
            if sc is None:
                skip += 1
                continue
            buf.append((r, sc))
            if len(buf) >= 50:
                _flush()
            if i % 100 == 0:
                print(f"  [kol-relevance] …{i}/{total}(done={done}+buf{len(buf)} skip={skip} fail={fail})", flush=True)
    _flush()

    print(f"[kol-relevance] 完成 {done}(跳过 {skip}，失败 {fail})", flush=True)
    return done


if __name__ == "__main__":
    score(only=["NVDA"], per_source=10)
