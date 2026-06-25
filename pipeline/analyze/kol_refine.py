"""KOL 个体观点 · AI 提炼 + 双语（标的页「个体观点·KOL」模块）。

把各社区**照搬过来的原文**提炼成「ta 为什么看多/看空/中性 + 2-3 条要点」，并同时产出
zh/en 双语（提炼与翻译合一，一次 DeepSeek(LOW/flash) 调用）。覆盖文本源 reddit / x / xueqiu；
YouTube 复用 `yt_analysis`（Gemini 已产出同形 summary+key_points，不在此重复花配额）。

设计要点：
- **只提炼会被展示的 top-N**：每标的每源按互动热度排序取前 N（镜像 web 取数层的 LIMIT），成本可控。
- **增量**：已在 kol_refined 的条目默认跳过（--force 重跑）。
- **并发只在网络调用层**：线程池跑 LLM，结果回主线程顺序落库（避开 sqlite 单写锁）。
- 翻译语言只 zh/en（ja/ko 在前端回退到 en）——按产品决策。

输出 → kol_refined（隔离表，主键 source+item_id）。web/lib/kolQueries.ts LEFT JOIN 之，
有提炼则展示 reason+points，无则回退原文。
"""
from __future__ import annotations

import datetime as dt
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import bindparam, text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolRefined

DEFAULT_PER_SOURCE = 40  # = web 取数层各源 LIMIT（reddit/x/雪球 都 40）→ 展示项全覆盖
DEFAULT_SINCE_DAYS = 20  # 只提炼近 N 天（≥ 前端价格窗口 ~11 交易日），预算不浪费在不展示的旧帖
TEXT_SOURCES = ("reddit", "x", "xueqiu")
_SRC_LABEL = {"reddit": "Reddit 帖子", "x": "X(Twitter) 推文", "xueqiu": "雪球帖子"}

SYSTEM = (
    "你是金融观点提炼器。给定某社区用户/博主关于一只美股的发言（语言可能为中/英/日/韩），"
    "提炼 ta 对该股的核心立场与理由，并给出双语结果。务必『提炼』而非照抄或直译原文。"
    "仅输出 JSON，不要多余文字：\n"
    '{"stance":"bull|bear|neutral",'
    '"reason_zh":"说明 ta 为什么看多/看空/中性（第三人称，1-2句、把核心逻辑讲清，≤80字）",'
    '"reason_en":"why, third-person, 1-2 sentences capturing the core logic (≤55 words)",'
    '"points_zh":["要点1","要点2"],'
    '"points_en":["point1","point2"],'
    '"quote_zh":"ta 原话里最能代表其观点的一句，忠实翻译成中文（≤50字，保留原语气，不要改写或提炼）",'
    '"quote_en":"the single most representative sentence ta actually wrote, faithful English (not paraphrased, ≤40 words)"}\n'
    "points 填 ta 给出的具体信息（催化剂/财务数据/价格目标/风险/逻辑链），2-4 条、保留关键细节（数字/事件别丢），没有就空数组 []。"
    "quote 与 reason 不同：reason 是你的提炼，quote 是 ta 本人说的原话（忠实翻译、用于建立可信度）；原文若已是中/英则照引该句。"
    "若信息太少无法判断理由，reason 写「未给出明确理由」/\"no clear thesis given\"、stance 取 neutral、quote 留空。"
)


def _ensure_table() -> None:
    """只为本表建表（checkfirst），不触发全库 DDL。"""
    KolRefined.__table__.create(engine, checkfirst=True)


def _user(source: str, ticker: str, txt: str, hint: str | None) -> str:
    h = f"（系统初判立场：{hint}，仅供参考，可推翻）" if hint else ""
    return f"标的 {ticker}。来源：{_SRC_LABEL.get(source, source)}{h}。原文：\n{txt[:2000]}"


def _norm(d: dict | None, fallback_stance: str = "neutral") -> dict | None:
    if not isinstance(d, dict):
        return None
    st = str(d.get("stance") or fallback_stance).lower()
    if st not in ("bull", "bear", "neutral"):
        st = fallback_stance if fallback_stance in ("bull", "bear", "neutral") else "neutral"
    rz = str(d.get("reason_zh") or "").strip()[:400]
    re_ = str(d.get("reason_en") or "").strip()[:400]
    if not rz and not re_:
        return None
    pz = d.get("points_zh") or []
    pe = d.get("points_en") or []
    pz = [str(x).strip()[:240] for x in pz if str(x).strip()][:4] if isinstance(pz, list) else []
    pe = [str(x).strip()[:240] for x in pe if str(x).strip()][:4] if isinstance(pe, list) else []
    qz = str(d.get("quote_zh") or "").strip()[:200]
    qe = str(d.get("quote_en") or "").strip()[:200]
    return dict(stance=st, reason_zh=rz or re_, reason_en=re_ or rz, points_zh=pz, points_en=pe,
                quote_zh=qz, quote_en=qe)


# ----------------------------- 候选取数（镜像 web 排序，按标的取 top-N） -----------------------------

def _bucket(rows: list[dict], per_source: int) -> list[dict]:
    """rows 已按 (ticker, metric DESC) 排序 → 每标的取前 per_source 条。"""
    out: list[dict] = []
    seen: dict[str, int] = {}
    for r in rows:
        tk = r["ticker"]
        if seen.get(tk, 0) >= per_source:
            continue
        seen[tk] = seen.get(tk, 0) + 1
        out.append(r)
    return out


def _load(source: str, per_source: int, only: set[str] | None, since_days: int) -> list[dict]:
    if source == "reddit":
        sql = """
            SELECT p.id AS item_id, m.ticker AS ticker,
                   COALESCE(p.title,'') AS title, COALESCE(p.selftext,'') AS body,
                   a.stance AS hint, p.created_utc AS created,
                   COALESCE(p.score,0)+COALESCE(p.num_comments,0) AS metric
              FROM mentions m
              JOIN posts p ON p.id = m.item_id AND m.item_type = 'post'
              LEFT JOIN item_analysis a ON a.item_id = p.id AND a.item_type = 'post'
             WHERE m.item_type = 'post'
             ORDER BY m.ticker, metric DESC
        """
    elif source == "xueqiu":
        sql = """
            SELECT id AS item_id, ticker,
                   COALESCE(title,'') AS title, COALESCE(body,'') AS body,
                   stance AS hint, created_utc AS created,
                   COALESCE(likes,0)+COALESCE(comments,0) AS metric
              FROM gr_post
             WHERE source = 'xueqiu'
             ORDER BY ticker, metric DESC
        """
    elif source == "x":
        sql = """
            SELECT tweet_id AS item_id, ticker,
                   '' AS title, COALESCE(text,'') AS body,
                   NULL AS hint, created AS created,
                   COALESCE(likes,0)+COALESCE(retweets,0)+COALESCE(replies,0) AS metric
              FROM x_opinion
             ORDER BY ticker, metric DESC
        """
    else:
        return []
    with session_scope() as s:
        rows = [dict(r._mapping) for r in s.execute(text(sql))]
    if only:
        rows = [r for r in rows if (r["ticker"] or "").upper() in only]
    if since_days > 0:  # 只留近 N 天（匹配前端展示窗口）→ top-N 在窗口内取，预算不浪费在旧帖
        cutoff = (dt.date.today() - dt.timedelta(days=since_days)).isoformat()
        rows = [r for r in rows if str(r.get("created") or "")[:10] >= cutoff]
    rows = _bucket(rows, per_source)
    for r in rows:
        r["source"] = source
        txt = (str(r.get("title") or "") + "\n" + str(r.get("body") or "")).strip()
        r["txt"] = txt
    # 文本太空的丢弃（没东西可提炼）
    return [r for r in rows if len(r["txt"]) >= 8]


def _existing_keys(sources: list[str]) -> set[tuple[str, str, str]]:
    stmt = text("SELECT source, item_id, ticker FROM kol_refined WHERE source IN :ss").bindparams(
        bindparam("ss", expanding=True)
    )
    with session_scope() as s:
        rows = s.execute(stmt, {"ss": sources}).all()
    return {(r[0], str(r[1]), str(r[2])) for r in rows}


# ----------------------------- 主流程 -----------------------------

def refine(sources: list[str] | None = None, per_source: int = DEFAULT_PER_SOURCE,
           only: list[str] | None = None, force: bool = False, workers: int = 6,
           since_days: int = DEFAULT_SINCE_DAYS) -> int:
    _ensure_table()
    if not llm.available(llm.LOW):
        print("[kol-refine] 无 DeepSeek key（DEEPSEEK_API_KEY），跳过。", flush=True)
        return 0
    srcs = [s for s in (sources or list(TEXT_SOURCES)) if s in TEXT_SOURCES]
    only_set = {t.strip().upper() for t in only} if only else None

    plan: list[dict] = []
    for src in srcs:
        plan += _load(src, per_source, only_set, since_days)
    if not force:
        have = _existing_keys(srcs)
        plan = [r for r in plan
                if (r["source"], str(r["item_id"]), (r["ticker"] or "").upper()) not in have]

    total = len(plan)
    print(f"[kol-refine] 计划 {total} 条（源 {','.join(srcs)}, per_source={per_source}, "
          f"近 {since_days} 天, model={llm.model_label(llm.LOW)}, force={force}）", flush=True)
    if not total:
        return 0

    done = fail = skip = 0
    now = dt.datetime.utcnow()
    label = llm.model_label(llm.LOW)
    buf: list[tuple[dict, dict]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:  # 主线程单写者 → 无 sqlite 锁竞争
            for r, norm in buf:
                s.merge(KolRefined(
                    source=r["source"], item_id=str(r["item_id"]), ticker=(r["ticker"] or "").upper(),
                    stance=norm["stance"], reason_zh=norm["reason_zh"], reason_en=norm["reason_en"],
                    points_zh=norm["points_zh"], points_en=norm["points_en"],
                    quote_zh=norm["quote_zh"], quote_en=norm["quote_en"],
                    created=str(r.get("created") or "")[:32],
                    lang_src="", model=label, refined_at=now))
        done += len(buf)
        buf.clear()

    def _work(r: dict) -> tuple[dict, dict | None]:
        data = llm.messages_json(llm.LOW, SYSTEM, _user(r["source"], r["ticker"], r["txt"], r.get("hint")),
                                 max_tokens=800)
        return r, _norm(data, fallback_stance=str(r.get("hint") or "neutral"))

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, r) for r in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                r, norm = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [kol-refine] ✗ {str(e)[:90]}", flush=True)
                continue
            if norm is None:
                skip += 1
                continue
            buf.append((r, norm))
            if len(buf) >= 40:  # 增量落库：中途被杀也不丢已完成的
                _flush()
            if i % 50 == 0:
                print(f"  [kol-refine] …{i}/{total}（done={done}+buf{len(buf)} skip={skip} fail={fail}）", flush=True)
    _flush()

    print(f"[kol-refine] 完成 {done}（跳过 {skip}，失败 {fail}）", flush=True)
    return done


if __name__ == "__main__":
    refine(only=["HOOD"], per_source=8)
