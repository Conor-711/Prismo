"""KOL 买入/卖出(目标)价位 + 操作周期 结构化抽取（标的页：正文提炼行 + 整体数据时间线图）。

从各社区**原帖文本**里**只抽作者明确写明**的两侧价位（**各支持区间** lo/hi，确切价 lo==hi）：
  - 买入价位 buy_lo/buy_hi（入场/加仓）
  - 卖出·目标价位 sell_lo/sell_hi（止盈/卖出，**方向性目标价并入此侧**）
+ 操作周期（原话双语 horizon_zh/en + 归一档 short/mid/long）+ price_raw（原话）+ created（下达日）。
**反臆造**：没明说一律 null；绝不从涨跌幅/情绪/看多看空推断；prompt 喂当前价锚点剔数量级离谱者。

覆盖 reddit / x / xueqiu —— 复用 kol_refine 的候选池（近 ~90 天，覆盖时间线窗口）。YouTube 复用
yt_judgment(target+horizon)。一次 LOW(qwen-flash) 调用。增量：已在 kol_judgment 的 (source,item_id,
ticker) 默认跳过（--force 重抽）。并发只在网络层（线程池跑 LLM，回主线程顺序落库）。

用法：DATABASE_URL='sqlite:///./data/dev.db' \\
      pipeline/.venv/bin/python -m pipeline.analyze.kol_judgment --only NFLX
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import bindparam, text

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolJudgment
from .kol_refine import TEXT_SOURCES, _SRC_LABEL, _load

DEFAULT_PER_SOURCE = 40
DEFAULT_SINCE_DAYS = 90  # 时间线默认 3 个月 → 候选池也取近 90 天

SYSTEM = (
    "你是金融交易参数抽取器。给定某社区用户/博主关于一只美股的发言（语言可能为中/英/日/韩），"
    "抽取 ta **明确写明**的『买入价位』与『卖出/目标价位』，**支持区间**。**只输出 JSON、不要多余文字**：\n"
    '{"buy_lo":null,"buy_hi":null,"sell_lo":null,"sell_hi":null,"price_raw":null,'
    '"horizon_zh":null,"horizon_en":null,"horizon_bucket":null}\n'
    "字段说明（全部默认 null，只有作者**清楚写出**才填；价格只填**绝对数字**）：\n"
    "1) buy_lo / buy_hi：买入/加仓价位。区间→填上下界（『$70-75 买入』→ buy_lo=70, buy_hi=75）；"
    "确切价→两者相同（『$77 买』→ buy_lo=buy_hi=77）。没有 → 两者 null。\n"
    "2) sell_lo / sell_hi：卖出/止盈价位，**或方向性目标价/合理估值**（『到 30 卖』『目标 $115-120』"
    "『看到 1000』『值 $50』都归这一侧）。区间填上下界、确切价两者相同。没有 → 两者 null。\n"
    "3) price_raw：上面价格在原文里最有代表性的**原话短语**（保留货币符号与区间，如『$115–120』『目标 800 美金』）。\n"
    "4) horizon_zh / horizon_en：操作/持有周期的作者原话短语（中≤14字 / 英≤8词，如『到年底』『持有3个月』"
    "『swing 几周』）。没提周期 → 两者皆 null。\n"
    "5) horizon_bucket：归一成 short|mid|long —— short=日内~2周/swing；mid=2周~3个月；long=>3个月/长期持有/年度。没提 → null。\n"
    "**铁律(反臆造)**：价格只填绝对数字；『翻倍』『涨50%』等相对幅度不是价位（→null）；绝不从涨跌预期/情绪/看多看空推断数字或周期。\n"
    "**当前价锚点**：用户会告知该股当前价；与之数量级严重不符的数字（如当前价 $77 却出现 $0.88、$1225）"
    "几乎一定不是真实价位 → 该数字 null。\n"
    "**剔噪**：penny-pump 喊单（『$NFLX 0.88 to 16 🚀』）、假设性演算（『若按 SpaceX 市销率…$1225』）、"
    "筛选器批量输出里的数字都不是真实价位 → null；但作者对本标的明确给出、与现价数量级相符的价位（哪怕在多标的清单里）仍要抽。"
)

_NULLISH = {"", "null", "none", "n/a", "na", "-", "无", "暂无", "未提及", "未提到", "没有", "不适用", "nan"}


def _ensure_table() -> None:
    KolJudgment.__table__.create(engine, checkfirst=True)


def _clean(s, cap: int) -> str:
    if s is None:
        return ""
    t = str(s).strip()
    return "" if t.lower() in _NULLISH else t[:cap]


def _num(v) -> float | None:
    """单个价格值 → 正 float；含 % 的相对幅度 → None。"""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        f = float(v)
        return round(f, 4) if 0 < f < 1e7 else None
    s = str(v).strip().lower()
    if s in _NULLISH or "%" in s:
        return None
    s = s.replace(",", "").replace("$", "").replace("usd", "").replace("美元", "").replace("美金", "")
    nums = [float(n) for n in re.findall(r"\d+(?:\.\d+)?", s)]
    vals = [n for n in nums if 0 < n < 1e7]
    return round(vals[0], 4) if vals else None


def _rng(lo, hi) -> tuple[float | None, float | None]:
    """(lo,hi) → 规整：取两数排序；只给一个则两者相同；都无 → (None,None)。"""
    vals = [v for v in (_num(lo), _num(hi)) if v is not None]
    if not vals:
        return None, None
    return min(vals), max(vals)


def _norm(d: dict | None) -> dict:
    if not isinstance(d, dict):
        return {}
    blo, bhi = _rng(d.get("buy_lo"), d.get("buy_hi"))
    slo, shi = _rng(d.get("sell_lo"), d.get("sell_hi"))
    bucket = str(d.get("horizon_bucket") or "").strip().lower()
    if bucket not in ("short", "mid", "long"):
        bucket = ""
    return dict(
        buy_lo=blo, buy_hi=bhi, sell_lo=slo, sell_hi=shi,
        price_raw=_clean(d.get("price_raw"), 96),
        horizon_zh=_clean(d.get("horizon_zh"), 48),
        horizon_en=_clean(d.get("horizon_en"), 64),
        horizon_bucket=bucket,
    )


def _has_value(n: dict) -> bool:
    return n.get("buy_lo") is not None or n.get("sell_lo") is not None or bool(
        n.get("horizon_bucket") or n.get("horizon_zh") or n.get("horizon_en")
    )


def _user(r: dict, px: float | None = None) -> str:
    hint = r.get("hint")
    h = f"（系统初判立场：{hint}，仅供参考，不可据此编造数字）" if hint else ""
    label = _SRC_LABEL.get(r["source"], r["source"])
    anchor = f"该股当前价约 ${px:.2f}（与此数量级严重不符的数字几乎一定不是价位）。" if px else ""
    return f"标的 {r['ticker']}。来源：{label}{h}。{anchor}原文：\n{r['txt'][:2000]}"


def _price_map(tickers: set[str]) -> dict[str, float]:
    """每标的最新收盘价（price_daily 优先、gr_quote 兜底），供抽取时的当前价锚点。"""
    ts = [t for t in tickers if t]
    if not ts:
        return {}
    out: dict[str, float] = {}
    with session_scope() as s:
        rows = s.execute(text(
            "SELECT ticker, close FROM price_daily WHERE ticker IN :ts "
            "AND day = (SELECT MAX(day) FROM price_daily p2 WHERE p2.ticker = price_daily.ticker)"
        ).bindparams(bindparam("ts", expanding=True)), {"ts": ts}).all()
        for t, close in rows:
            if close and close > 0:
                out[str(t).upper()] = float(close)
        try:
            gr = s.execute(text("SELECT ticker, price FROM gr_quote WHERE ticker IN :ts").bindparams(
                bindparam("ts", expanding=True)), {"ts": ts}).all()
            for t, p in gr:
                if str(t).upper() not in out and p and p > 0:
                    out[str(t).upper()] = float(p)
        except Exception:  # noqa: BLE001
            pass
    return out


def _existing_keys(sources: list[str]) -> set[tuple[str, str, str]]:
    stmt = text("SELECT source, item_id, ticker FROM kol_judgment WHERE source IN :ss").bindparams(
        bindparam("ss", expanding=True)
    )
    with session_scope() as s:
        rows = s.execute(stmt, {"ss": sources}).all()
    return {(r[0], str(r[1]), str(r[2])) for r in rows}


def run(sources: list[str] | None = None, per_source: int = DEFAULT_PER_SOURCE,
        only: list[str] | None = None, force: bool = False, workers: int = 6,
        since_days: int = DEFAULT_SINCE_DAYS) -> int:
    _ensure_table()
    if not llm.available(llm.LOW):
        print("[kol-judgment] 无 LOW 档 key（QWEN_API_KEY），跳过。", flush=True)
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
    print(f"[kol-judgment] 计划 {total} 条（源 {','.join(srcs)}, per_source={per_source}, "
          f"近 {since_days} 天, model={llm.model_label(llm.LOW)}, force={force}）", flush=True)
    if not total:
        return 0

    pxmap = _price_map({(r["ticker"] or "").upper() for r in plan})  # 当前价锚点（抗噪）
    now = dt.datetime.utcnow()
    label = llm.model_label(llm.LOW)
    done = fail = withval = 0
    buf: list[tuple[dict, dict]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:  # 主线程单写者 → 无 sqlite 锁竞争
            for r, n in buf:
                s.merge(KolJudgment(
                    source=r["source"], item_id=str(r["item_id"]), ticker=(r["ticker"] or "").upper(),
                    buy_lo=n.get("buy_lo"), buy_hi=n.get("buy_hi"),
                    sell_lo=n.get("sell_lo"), sell_hi=n.get("sell_hi"),
                    price_raw=n.get("price_raw") or "",
                    horizon_zh=n.get("horizon_zh") or "", horizon_en=n.get("horizon_en") or "",
                    horizon_bucket=n.get("horizon_bucket") or "",
                    created=str(r.get("created") or "")[:32],
                    model=label, tagged_at=now))
        done += len(buf)
        buf.clear()

    def _work(r: dict) -> tuple[dict, dict]:
        data = None
        for _ in range(3):  # LOW 偶发 JSON None/截断 → 重试
            data = llm.messages_json(llm.LOW, SYSTEM, _user(r, pxmap.get((r["ticker"] or "").upper())), max_tokens=400)
            if isinstance(data, dict):
                break
        return r, _norm(data)

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, r) for r in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                r, n = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [kol-judgment] ✗ {str(e)[:90]}", flush=True)
                continue
            buf.append((r, n))
            if _has_value(n):
                withval += 1
            if len(buf) >= 40:
                _flush()
            if i % 50 == 0:
                print(f"  [kol-judgment] …{i}/{total}（done={done}+buf{len(buf)} 有值={withval} fail={fail}）", flush=True)
    _flush()
    print(f"[kol-judgment] 完成 {done}（其中 {withval} 抽到至少一项；失败 {fail}）→ kol_judgment", flush=True)
    return done


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=str, default=None, help="逗号分隔，子集 of reddit,x,xueqiu；省略=全部")
    ap.add_argument("--per-source", type=int, default=DEFAULT_PER_SOURCE, help="每标的每源前 N 条")
    ap.add_argument("--since-days", type=int, default=DEFAULT_SINCE_DAYS, help="只抽近 N 天（默认 90=时间线窗口）")
    ap.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些")
    ap.add_argument("--workers", type=int, default=6, help="LLM 并发数")
    ap.add_argument("--force", action="store_true", help="重抽全部（默认只补未抽的）")
    a = ap.parse_args()
    run(sources=[s.strip() for s in a.source.split(",")] if a.source else None,
        per_source=a.per_source, since_days=a.since_days,
        only=[t.strip() for t in a.only.split(",")] if a.only else None,
        workers=a.workers, force=a.force)
