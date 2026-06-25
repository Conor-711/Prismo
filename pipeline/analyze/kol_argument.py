"""KOL 个体观点 · 论点综合 + 叙事编织（标的页『按视角』视图）。

在 kol_refined（提炼）+ kol_viewpoint（视角分类）之上再加一层 AI 综合：
把同一 (ticker, 视角, 立场) 下的多条已提炼观点，用 DeepSeek(LOW/flash) **一次调用**产出两样东西——
  · 论点(arguments)：2-3 个不同论点（同义合并、抽象成论点本身、无实质论据者丢弃），每个带 detail（周全的依据）+ supporters；
  · 叙事(narrative)：把这些论点编织成一段连贯、周全的「该立场叙事」（叙事体、覆盖所有论点）。
三层结构：叙事(第1层) ← 论点/claim(第2层=论据) ← detail+原话/原帖(第3层=子论据)。

输出 → kol_argument（论点）+ kol_narrative（叙事）。设计：增量（已有该组则跳过，--force 重做并先清范围内旧数据）；
并发只在 LLM 网络层；视角 other 不综合；立场含 neutral。
"""
from __future__ import annotations

import datetime as dt
import json
import re
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolArgument, KolNarrative

VALID_LENS = ("valuation", "growth", "competition", "management", "macro", "catalyst", "flows")
STANCES = ("bull", "bear", "neutral")
LENS_ZH = {
    "valuation": "估值", "growth": "业务与成长", "competition": "竞争格局",
    "management": "管理层", "macro": "宏观与政策", "catalyst": "催化剂", "flows": "资金与盘面",
}
STANCE_ZH = {"bull": "看多", "bear": "看空", "neutral": "中性"}
WINDOWS = (("24h", 1), ("3d", 3), ("7d", 7), ("14d", 14), ("1mo", 30))  # 时间窗 key, 天数（方案 B：各窗独立重合成）
MAX_ARGS = 3   # 每 (标的×视角×立场) 最多论点数
MAX_FEED = 40  # 喂给 LLM 的最多观点数（已是 refine 的 top-N，足够）

# 与 kol_viewpoint 同款：无明确观点的（新闻转述/被 mentions 过度匹配）不进论点综合。
NO_THESIS_RE = re.compile(
    r"未给出明确|未表达|未明确表态|没有明确(观点|立场)|尚?未形成.{0,6}(立场|观点|看法)|"
    r"无明显.{0,4}(多空|倾向|立场)|仅(转发|转述|转载|分享|引用|提及|提到)|"
    r"no clear (thesis|stance|view|opinion|position)|no (personal )?(opinion|stance|view|thesis)",
    re.I,
)


# 把模型偶尔保留的「用户认为/ta/作者…」开头剥掉，使 claim 是论点本身、而非"某人的观点"。
def _clean_claim(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r"^(该|这位)?(用户|作者|博主|网友|发帖人|楼主|他|她|ta)(们)?(认为|觉得|表示|指出|提到|强调|担心|看好|看多|看空|主张|预计|预期)?[，,：:、\s]*", "", s, flags=re.I)
    s = re.sub(r"^(认为|觉得|表示|指出|提到|强调|主张|预计|预期)[，,：:、\s]*", "", s)
    s = re.sub(r"^(the user|users|the author|the poster|the op|op|he|she|they)\s+(believes?|thinks?|argues?|notes?|says?|feels?|claims?|points? out|is|are)?\s*[,:]?\s*", "", s, flags=re.I)
    return s.strip()


SYSTEM = (
    "你是金融论点【主编】。下面是同一只美股、同一视角、同一立场下的多条观点（每条带编号、理由、要点、原话）。"
    "做两件事：① 提炼出最关键的 2-3 个论点；② 把它们编织成一段连贯的叙事。\n"
    "【论点 arguments】\n"
    "- 合并：说同一件事的合并成一个，supporters 收齐相关编号。\n"
    "- 抽象：claim 写成**论点本身**、客观陈述，禁止「用户认为/ta/作者表示」。"
    "例：「用户认为赠股是廉价营销」→「赠股营销噱头大于实质价值」。\n"
    "- 取舍：纯情绪、个人交易流水、看热闹、说不出理由的丢弃；没有成立论点则 arguments 给 []。\n"
    "- detail：把该论点的**具体依据/逻辑/数据/事件讲周全**——原帖信息多就多写（1-3 句），"
    "别为了精简而丢掉关键细节（数字、事件、因果都尽量留）。\n"
    "【叙事 narrative】把上面的论点编织成**分点、可读、有逻辑**的叙事（不要一坨长段落）：\n"
    "- lead：一句话总述该立场核心（≤40字）。\n"
    "- points：3-6 个分点，每点是一个完整、带证据的小段（含数字/事件/因果，1-2句），逻辑递进或并列；"
    "覆盖所有论点、把细节/原话写进点里。客观第三人称，不要「用户认为」。"
    "**每个 point 用 supporters 标注它依据的观点编号**（显示来源角标用）。\n"
    "arguments 为 [] 时 lead 给 \"\"、points 给 []。lead/points/claim 均中英双语。仅输出 JSON：\n"
    '{"lead_zh":"","lead_en":"","points":[{"zh":"","en":"","supporters":[1]}],"arguments":[{"claim_zh":"","claim_en":"","detail_zh":"","detail_en":"","supporters":[1,2]}]}'
)


def _ensure_tables() -> None:
    KolArgument.__table__.create(engine, checkfirst=True)
    KolNarrative.__table__.create(engine, checkfirst=True)


def _as_list(v) -> list:
    if isinstance(v, list):
        return v
    if isinstance(v, str) and v:
        try:
            x = json.loads(v)
            return x if isinstance(x, list) else []
        except Exception:
            return []
    return []


def _load_opinions(only: set[str] | None) -> list[dict]:
    """已分类观点 + 内容：kol_viewpoint ⋈ (kol_refined | yt_analysis)。"""
    with session_scope() as s:
        content: dict[tuple, dict] = {}
        for r in s.execute(text(
            "SELECT source, item_id, ticker, stance, reason_zh, reason_en, "
            "points_zh, points_en, quote_zh, quote_en, created FROM kol_refined")):
            d = dict(r._mapping)
            content[(d["source"], str(d["item_id"]), str(d["ticker"]))] = d
        try:  # YouTube：复用 yt_analysis（summary→reason、key_points→points；无原话）；日期取 yt_video
            for r in s.execute(text(
                "SELECT 'youtube' AS source, a.video_id AS item_id, a.ticker AS ticker, a.stance AS stance, "
                "a.summary_zh AS reason_zh, a.summary_en AS reason_en, "
                "a.key_points_zh AS points_zh, a.key_points_en AS points_en, "
                "'' AS quote_zh, '' AS quote_en, v.published_utc AS created "
                "FROM yt_analysis a LEFT JOIN yt_video v ON v.id = a.video_id")):
                d = dict(r._mapping)
                content[(d["source"], str(d["item_id"]), str(d["ticker"]))] = d
        except Exception:
            pass
        vp_rows = [dict(r._mapping) for r in s.execute(text(
            "SELECT source, item_id, ticker, viewpoints FROM kol_viewpoint"))]

    out: list[dict] = []
    for v in vp_rows:
        c = content.get((v["source"], str(v["item_id"]), str(v["ticker"])))
        if not c:
            continue
        if only and str(c["ticker"]).upper() not in only:
            continue
        lenses = [x for x in _as_list(v["viewpoints"]) if x in VALID_LENS]
        if not lenses:
            continue
        blob = f"{c.get('reason_zh') or ''} {c.get('reason_en') or ''}".strip()
        if not blob or NO_THESIS_RE.search(blob):  # 无明确观点 → 不综合
            continue
        c = dict(c)
        c["lenses"] = lenses
        out.append(c)
    return out


def _group(opinions: list[dict]) -> dict[tuple, list[dict]]:
    g: dict[tuple, list[dict]] = defaultdict(list)
    for c in opinions:
        st = str(c.get("stance") or "neutral")
        if st not in STANCES:
            st = "neutral"
        lens = c["lenses"][0]  # 只按主视角归组，避免同一观点在多视角里重复成多个零散论点
        g[(str(c["ticker"]).upper(), lens, st)].append(c)
    return g


def _existing_groups() -> set[tuple]:
    with session_scope() as s:
        rows = s.execute(text("SELECT DISTINCT ticker, lens, stance, window FROM kol_argument")).all()
    return {(str(r[0]), str(r[1]), str(r[2]), str(r[3])) for r in rows}


def _user(ticker: str, lens: str, stance: str, items: list[dict]) -> str:
    lines = []
    for i, c in enumerate(items, 1):
        reason = str(c.get("reason_zh") or c.get("reason_en") or "")
        pts = _as_list(c.get("points_zh")) or _as_list(c.get("points_en"))
        pstr = "；".join(str(x) for x in pts[:4])
        quote = str(c.get("quote_zh") or c.get("quote_en") or "")
        line = f"[{i}] 理由：{reason[:400]}"
        if pstr:
            line += f"。要点：{pstr[:400]}"
        if quote:
            line += f"。原话：{quote[:200]}"
        lines.append(line)
    return (f"标的 {ticker}。视角：{LENS_ZH.get(lens, lens)}。立场：{STANCE_ZH.get(stance, stance)}。"
            f"共 {len(items)} 条观点：\n" + "\n".join(lines))


def _supporters(items: list[dict], idxs) -> list[dict]:
    out, seen = [], set()
    for i in idxs if isinstance(idxs, list) else []:
        try:
            c = items[int(i) - 1]
        except (ValueError, TypeError, IndexError):
            continue
        k = (c["source"], str(c["item_id"]))
        if k in seen:
            continue
        seen.add(k)
        out.append({"source": c["source"], "item_id": str(c["item_id"])})
    return out


def _trivial(items: list[dict]) -> list[dict]:
    """解析失败兜底：每条观点各成一个论点（清洗口吻 + 滤掉无观点；最多 MAX_ARGS 条）。"""
    args = []
    for c in items[:MAX_ARGS]:
        cz = _clean_claim(str(c.get("reason_zh") or c.get("reason_en") or ""))[:300]
        ce = _clean_claim(str(c.get("reason_en") or c.get("reason_zh") or ""))[:300]
        if (not cz and not ce) or NO_THESIS_RE.search(f"{cz} {ce}"):
            continue
        args.append(dict(
            claim_zh=cz or ce, claim_en=ce or cz,
            detail_zh=str(c.get("reason_zh") or "")[:600] if cz else "",
            detail_en=str(c.get("reason_en") or "")[:600] if ce else "",
            supporters=[{"source": c["source"], "item_id": str(c["item_id"])}], support_count=1))
    return args


def _parse(data, items: list[dict]):
    """None=解析失败（兜底/重试）；否则返回 (narrative, args)，args 可能为 []（模型主动丢弃整组）。"""
    if not isinstance(data, dict):
        return None
    arr = data.get("arguments")
    if not isinstance(arr, list):
        return None
    out = []
    for a in arr[:MAX_ARGS]:
        if not isinstance(a, dict):
            continue
        sup = _supporters(items, a.get("supporters"))
        if not sup:
            continue
        cz = _clean_claim(str(a.get("claim_zh") or a.get("claim_en") or ""))[:300]
        ce = _clean_claim(str(a.get("claim_en") or a.get("claim_zh") or ""))[:300]
        if not cz and not ce:
            continue
        if NO_THESIS_RE.search(f"{cz} {ce}"):  # 模型偶尔把「无明确观点」当成 claim → 丢弃
            continue
        out.append(dict(
            claim_zh=cz or ce, claim_en=ce or cz,
            detail_zh=str(a.get("detail_zh") or "").strip()[:600],
            detail_en=str(a.get("detail_en") or "").strip()[:600],
            supporters=sup, support_count=len(sup)))
    lz = str(data.get("lead_zh") or "").strip()[:200]
    le = str(data.get("lead_en") or "").strip()[:200]
    pts = []
    for p in (data.get("points") if isinstance(data.get("points"), list) else []):
        if not isinstance(p, dict):
            continue
        z = str(p.get("zh") or p.get("en") or "").strip()[:400]
        e = str(p.get("en") or p.get("zh") or "").strip()[:400]
        if not z and not e:
            continue
        pts.append({"zh": z or e, "en": e or z, "refs": _supporters(items, p.get("supporters"))})
        if len(pts) >= 6:
            break
    narrative = ({"lead_zh": lz or le, "lead_en": le or lz, "points": pts}
                 if (out and (lz or le or pts)) else None)
    return narrative, out


def synthesize(only: list[str] | None = None, force: bool = False, workers: int = 8) -> int:
    _ensure_tables()
    if not llm.available(llm.LOW):
        print("[kol-argument] 无 DeepSeek key（DEEPSEEK_API_KEY），跳过。", flush=True)
        return 0
    only_set = {t.strip().upper() for t in only} if only else None

    opinions = _load_opinions(only_set)
    if force:
        # 先清掉范围内标的的全部旧数据（所有时间窗）：避免陈旧组残留。
        with session_scope() as s:
            for tbl in ("kol_argument", "kol_narrative"):
                if only_set:
                    for tk in only_set:
                        s.execute(text(f"DELETE FROM {tbl} WHERE ticker=:t"), {"t": tk})
                else:
                    s.execute(text(f"DELETE FROM {tbl}"))
    # 方案 B：按 5 个时间窗分别分组、各窗独立重合成（侧重点不同，非包含关系）
    today = dt.date.today()
    groups: dict[tuple, list[dict]] = {}
    for wkey, wdays in WINDOWS:
        cutoff = (today - dt.timedelta(days=wdays)).isoformat()
        wop = [c for c in opinions if str(c.get("created") or "")[:10] >= cutoff]
        for (tk, lens, stance), items in _group(wop).items():
            groups[(tk, lens, stance, wkey)] = items
    if not force:
        have = _existing_groups()
        groups = {k: v for k, v in groups.items() if k not in have}

    total = len(groups)
    print(f"[kol-argument] 组 {total}（5 时间窗 × 论点+叙事，model={llm.model_label(llm.LOW)}, force={force}）", flush=True)
    if not total:
        return 0

    now = dt.datetime.utcnow()
    label = llm.model_label(llm.LOW)
    done = fail = dropped = 0
    buf: list = []  # (k, narrative|None, args)

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:  # 主线程单写者；先删该组旧数据再插
            for (ticker, lens, stance, window), narrative, args in buf:
                s.execute(text("DELETE FROM kol_argument WHERE ticker=:t AND lens=:l AND stance=:s AND window=:w"),
                          {"t": ticker, "l": lens, "s": stance, "w": window})
                s.execute(text("DELETE FROM kol_narrative WHERE ticker=:t AND lens=:l AND stance=:s AND window=:w"),
                          {"t": ticker, "l": lens, "s": stance, "w": window})
                for rank, a in enumerate(args):
                    s.add(KolArgument(
                        ticker=ticker, lens=lens, stance=stance, window=window, rank=rank,
                        claim_zh=a["claim_zh"], claim_en=a["claim_en"],
                        detail_zh=a["detail_zh"], detail_en=a["detail_en"],
                        supporters=a["supporters"], support_count=a["support_count"],
                        model=label, created_at=now))
                if args and narrative and (narrative["lead_zh"] or narrative["lead_en"] or narrative["points"]):
                    s.add(KolNarrative(
                        ticker=ticker, lens=lens, stance=stance, window=window,
                        lead_zh=narrative["lead_zh"], lead_en=narrative["lead_en"],
                        points=narrative["points"],
                        model=label, created_at=now))
        done += len(buf)
        buf.clear()

    # 全部组都走 LLM 主编（含单条：让模型有机会丢弃零散/无实质的）
    def _work(item):
        k, items = item
        feed = items[:MAX_FEED]
        data = None
        for _ in range(3):
            data = llm.messages_json(llm.LOW, SYSTEM, _user(k[0], k[1], k[2], feed), max_tokens=2000)
            if data is not None:
                break
        parsed = _parse(data, feed)
        if parsed is None:                  # 解析失败 → 兜底保内容（无叙事）
            return k, None, _trivial(feed)
        narrative, args = parsed
        return k, narrative, args

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, it) for it in groups.items()]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                k, narrative, args = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [kol-argument] ✗ {str(e)[:90]}", flush=True)
                continue
            if not args:
                dropped += 1
            buf.append((k, narrative, args))
            if len(buf) >= 40:
                _flush()
            if i % 50 == 0:
                print(f"  [kol-argument] …{i}/{total}（done={done}+buf{len(buf)} drop={dropped} fail={fail}）", flush=True)
    _flush()

    print(f"[kol-argument] 完成 {done}（丢弃空组 {dropped}，失败 {fail}）", flush=True)
    return done


if __name__ == "__main__":
    synthesize(only=["HOOD"], force=True)
