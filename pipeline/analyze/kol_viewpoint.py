"""KOL 个体观点 · 视角分类（标的页「个体观点·KOL」模块的『按视角』视图）。

把已蒸馏的 KOL 观点（kol_refined 的 reddit/x/xueqiu 理由+要点 + yt_analysis 的 youtube 摘要+要点）
用 AI(DeepSeek LOW/flash) 打一组「视角」标签——7 选 1-3，按相关度排序，首个为主视角。输出 → kol_viewpoint。

7 视角（与前端 dict.viewpoints 同键）：
  valuation 估值 · growth 业务与成长 · competition 竞争格局 · management 管理层 ·
  macro 宏观与政策 · catalyst 催化剂 · flows 资金与盘面（+ other 兜底）。

设计同 kol_refine：增量(已分类跳过,--force 重跑)；并发只在 LLM 网络层(线程池)，结果回主线程顺序落库
(避开 sqlite 单写锁)；无明确观点的(新闻转述/被 mentions 过度匹配)直接记 other，省一次调用。
"""
from __future__ import annotations

import datetime as dt
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import bindparam, text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolViewpoint

VALID = ("valuation", "growth", "competition", "management", "macro", "catalyst", "flows")
OTHER = "other"

# 与 web/lib/kolQueries.ts 的 NO_THESIS_RE 取交集（高频标记）：这类已蒸馏结果其实没观点，
# 前端本就 skip，故这里直接记 other、不花 LLM。
NO_THESIS_RE = re.compile(
    r"未给出明确|未表达|未明确表态|没有明确(观点|立场)|仅(转发|转述|转载|分享|引用|提及|提到)|"
    r"no clear (thesis|stance|view|opinion|position)|no (personal )?(opinion|stance|view|thesis)",
    re.I,
)

SYSTEM = (
    "你是金融观点分类器。给定一条关于某只美股的【已提炼观点】（立场+理由+要点），把它归入下面 7 个"
    "投资分析视角中**最贴切的 1-3 个**（按相关度排序，主视角在前）。\n"
    "**核心原则：几乎每一条有具体内容的观点都至少属于一个视角。** 只要它谈到了公司的"
    "【基本面 / 管理层 / 竞争 / 宏观环境 / 近期事件 / 价格或资金】中的任何一项，就必须归入对应视角——"
    "**绝不要因为『涉及多个方面』或『不够纯粹』就丢进 other**。只有当通篇是纯情绪喊单"
    "（🚀『冲』『到月球』『钻石手』）、与该股无关、或完全没有任何信息时，才返回 [\"other\"]。\n"
    "逐条对照线索，命中哪个就选哪个（可多选）：\n"
    "- valuation 估值：估值贵/便宜、市盈率市销率PEG、目标价、对比同业或历史、是否高估低估\n"
    "- growth 业务与成长：收入/用户/付费/参与度增长、产品与模型、新业务扩展、毛利/成本结构、现金流、TAM、战略价值、AI 投入产出\n"
    "- competition 竞争格局：对手与对标（如『落后 Gemini』『被 OpenAI 超越』）、市占、替代品、护城河、开放权重 vs 闭源、供应/生态安全\n"
    "- management 管理层：高管/董事的能力与决策、**高管被解雇/任命、内部人增减持**、资本配置、成本管控、裁员/调岗/员工士气、诚信、并购操盘\n"
    "- macro 宏观与政策：利率、市场流动性、供需（如『IPO 抽干流动性』『融资潮』『顶部信号』）、经济周期、行业政策/监管/立法、关税、汇率、商品价\n"
    "- catalyst 催化剂：财报、**新品/新模型发布或推迟**、并购、解禁、指数纳入、诉讼、IPO、监管落地等近期事件\n"
    "- flows 资金与盘面：价格走势/突破/支撑阻力、买卖点与加减仓时机、做多做空、空头比例、期权、资金流向、迷因/叙事/人气\n"
    "仅输出 JSON：{\"viewpoints\":[\"key\",...]}\n"
    "示例：\n"
    "『高管因过度花费被解雇、AI 支出管理混乱』→[\"management\",\"growth\"]\n"
    "『IPO 与融资潮抽干市场流动性、预示顶部』→[\"macro\",\"flows\"]\n"
    "『内部 AI 成本失控、员工士气崩溃、管理层踩刹车』→[\"management\",\"growth\"]\n"
    "『旗舰模型推迟、基准落后 Gemini 3.0』→[\"catalyst\",\"competition\"]\n"
    "『主权 AI 趋势提升开放权重模型战略价值』→[\"growth\",\"competition\",\"macro\"]\n"
    "『图表极强、等突破加仓』→[\"flows\"]；『15 倍 PE 低于同业、已便宜』→[\"valuation\"]；『🚀🚀冲』→[\"other\"]"
)


# 容忍模型偶尔回中文名/变体 → 规范化到英文键
ALIAS = {
    "估值": "valuation", "业务与成长": "growth", "成长": "growth", "业务": "growth",
    "竞争格局": "competition", "竞争": "competition", "管理层": "management", "管理": "management",
    "宏观与政策": "macro", "宏观": "macro", "政策": "macro", "催化剂": "catalyst",
    "资金与盘面": "flows", "资金": "flows", "盘面": "flows", "flow": "flows",
}


def _norm(d: dict | None) -> list[str]:
    if not isinstance(d, dict):
        return [OTHER]
    vs = d.get("viewpoints") or d.get("viewpoint") or []
    if isinstance(vs, str):
        vs = [vs]
    out: list[str] = []
    for v in vs if isinstance(vs, list) else []:
        k0 = str(v).strip().lower()
        k = ALIAS.get(k0, k0)
        if k in VALID and k not in out:
            out.append(k)
    out = out[:3]
    return out or [OTHER]


def _ensure_table() -> None:
    KolViewpoint.__table__.create(engine, checkfirst=True)


def _candidates() -> list[dict]:
    """已蒸馏观点候选：kol_refined（reddit/x/xueqiu）+ yt_analysis（youtube）。"""
    rows: list[dict] = []
    with session_scope() as s:
        for r in s.execute(text(
            "SELECT source, item_id, ticker, stance, reason_zh, reason_en, points_zh, points_en "
            "FROM kol_refined")):
            rows.append(dict(r._mapping))
        # YouTube：复用 yt_analysis（summary→reason、key_points→points）
        try:
            for r in s.execute(text(
                "SELECT 'youtube' AS source, video_id AS item_id, ticker, stance, "
                "summary_zh AS reason_zh, summary_en AS reason_en, "
                "key_points_zh AS points_zh, key_points_en AS points_en FROM yt_analysis")):
                rows.append(dict(r._mapping))
        except Exception:
            pass
    return rows


def _existing_keys() -> set[tuple[str, str, str]]:
    with session_scope() as s:
        rows = s.execute(text("SELECT source, item_id, ticker FROM kol_viewpoint")).all()
    return {(r[0], str(r[1]), str(r[2])) for r in rows}


def _other_keys() -> set[tuple[str, str, str]]:
    """当前被判成 ['other'] 的行——供 --reclassify-other 用新 prompt 重判（no-thesis 的会再次落 other）。"""
    with session_scope() as s:
        rows = s.execute(text(
            "SELECT source, item_id, ticker FROM kol_viewpoint WHERE viewpoints = '[\"other\"]'")).all()
    return {(r[0], str(r[1]), str(r[2])) for r in rows}


def _user(r: dict) -> str:
    reason = str(r.get("reason_zh") or r.get("reason_en") or "")
    pts = r.get("points_zh") or r.get("points_en") or []
    if isinstance(pts, str):
        pts = [pts]
    pts_s = "；".join(str(x) for x in (pts or [])[:3]) if isinstance(pts, list) else ""
    return (f"标的 {r.get('ticker')}。立场：{r.get('stance') or 'neutral'}。"
            f"理由：{reason[:300]}。要点：{pts_s[:300]}")


def classify(only: list[str] | None = None, force: bool = False, workers: int = 8,
             reclassify_other: bool = False) -> int:
    _ensure_table()
    if not llm.available(llm.LOW):
        print("[kol-viewpoint] 无 DeepSeek key（DEEPSEEK_API_KEY），跳过。", flush=True)
        return 0
    only_set = {t.strip().upper() for t in only} if only else None

    cand = _candidates()
    if only_set:
        cand = [r for r in cand if str(r.get("ticker") or "").upper() in only_set]
    if reclassify_other:
        # 只重判当前为 ['other'] 的行（用新 prompt）：实质观点会进对应视角，no-thesis 仍落 other。
        keys = _other_keys()
        cand = [r for r in cand
                if (r["source"], str(r["item_id"]), str(r["ticker"] or "")) in keys]
        print(f"[kol-viewpoint] reclassify-other：命中 {len(cand)} 条 other 行重判", flush=True)
    elif not force:
        have = _existing_keys()
        cand = [r for r in cand
                if (r["source"], str(r["item_id"]), str(r["ticker"] or "")) not in have]

    # 预筛「无明确观点」→ 直接记 other，不花 LLM
    pre_other: list[dict] = []
    todo: list[dict] = []
    for r in cand:
        blob = f"{r.get('reason_zh') or ''} {r.get('reason_en') or ''}".strip()
        if not blob or NO_THESIS_RE.search(blob):
            pre_other.append(r)
        else:
            todo.append(r)

    total = len(todo)
    print(f"[kol-viewpoint] 候选 {len(cand)}：LLM 分类 {total}，预判 other {len(pre_other)}"
          f"（model={llm.model_label(llm.LOW)}, force={force}）", flush=True)

    now = dt.datetime.utcnow()
    label = llm.model_label(llm.LOW)
    done = fail = 0
    buf: list[tuple[dict, list[str]]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:
            for r, vps in buf:
                s.merge(KolViewpoint(
                    source=r["source"], item_id=str(r["item_id"]), ticker=str(r["ticker"] or "").upper(),
                    viewpoints=vps, model=label, classified_at=now))
        done += len(buf)
        buf.clear()

    # 1) 预判 other 直接落库
    for r in pre_other:
        buf.append((r, [OTHER]))
        if len(buf) >= 200:
            _flush()
    _flush()

    # 2) LLM 分类
    def _work(r: dict) -> tuple[dict, list[str]]:
        # max_tokens 给足（120 会截断 JSON → 解析失败返回 None → 被误当 other！）。
        # 解析失败重试几次；仍 None 则抛错 → 主循环计 fail、**不落库为 other**（留待下次重跑）。
        data = None
        for _ in range(3):
            data = llm.messages_json(llm.LOW, SYSTEM, _user(r), max_tokens=500)
            if data is not None:
                break
        if data is None:
            raise RuntimeError("messages_json 返回 None（JSON 解析失败）")
        return r, _norm(data)

    if total:
        with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
            futs = [ex.submit(_work, r) for r in todo]
            for i, fut in enumerate(as_completed(futs), 1):
                try:
                    r, vps = fut.result()
                except Exception as e:  # noqa: BLE001
                    fail += 1
                    if fail <= 8:
                        print(f"  [kol-viewpoint] ✗ {str(e)[:90]}", flush=True)
                    continue
                buf.append((r, vps))
                if len(buf) >= 40:
                    _flush()
                if i % 100 == 0:
                    print(f"  [kol-viewpoint] …{i}/{total}（done={done}+buf{len(buf)} fail={fail}）", flush=True)
        _flush()

    print(f"[kol-viewpoint] 完成 {done}（含预判 other {len(pre_other)}，失败 {fail}）", flush=True)
    return done


if __name__ == "__main__":
    classify(only=["HOOD"])
