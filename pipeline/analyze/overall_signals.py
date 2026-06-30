"""整体数据 · 「异动归因」+「讨论方面」生成器（标的页『整体数据』模块的派生信号）。

两个产出，都只用 **KOL** 数据，写进构建期 JSON `web/lib/data/overallData.json`（与
`topInvestors.json` 同范式：离线算好、web 端按 ticker 直接读，不碰 dev.db）：

  ① anomalies —— 情绪/讨论度的异常日 + AI 一句话归因（标在当天的折线/条状物上，hover 出原因）。
     · 情绪异常跑在**交易日序列**上（与 SentimentPanel 的 x 轴一致；06-19 Juneteenth、周末不在轴上）。
     · 讨论度异常跑在**日历日序列**上（与 VolumePanel 的 x 轴一致，含周末）。
     · 判定 = 滚动 14 日基线的 |z|≥2（情绪双向 / 讨论度只取放量）；各取 |z| 最大的前 3 个，避免刷屏。
     · 归因 = 把当天按互动排序的 top KOL 推文喂给 qwen-flash，要它点出当天**主导催化/话题**（具体可证伪）。

  ② aspects —— 近 14 天 KOL 被讨论最密集的 3 个『方面』，各含 标签(zh/en) + 多空倾向 + 一条代表性原推（论据）。
     代表引文用模型回选的**真实推文编号**映射回原文/作者/链接（不让模型自由生成，杜绝杜撰）。

KOL 文本源：当前用 `/tmp/<ticker>_x6m.jsonl`（朋友的 6 个月 X 大V 推文抽取，f5000=粉丝≥5000=KOL；
字段 id/h/aid/cu/text/eng）。云端 tw_tweet 已空，故暂走此抽取；X 正式入 x_opinion 后改读 DB 即可。

运行（务必 venv，需 .env 里的 QWEN_API_KEY）：
    pipeline/.venv/bin/python -m pipeline.analyze.overall_signals --ticker PLTR
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import sqlite3
import statistics as st
from bisect import bisect_left
from collections import defaultdict
from datetime import datetime, timedelta

from ..common.config import ROOT
from ..common.llm import LOW, available, messages_json

DB = ROOT / "data" / "dev.db"
OUT = ROOT / "web" / "lib" / "data" / "overallData.json"


# ----------------------------- 数据读取 -----------------------------
def _series(con: sqlite3.Connection, table: str, col: str, ticker: str):
    return [(d, float(v or 0)) for d, v in con.execute(
        f"SELECT day, {col} FROM {table} WHERE ticker=? ORDER BY day", (ticker,))]


def _trading_days(con: sqlite3.Connection, ticker: str):
    return [d for (d,) in con.execute(
        "SELECT day FROM price_daily WHERE ticker=? ORDER BY day", (ticker,))]


def _load_tweets(path: str):
    """读 KOL 推文抽取 → (按日分组, 全量列表)；过滤 RT 与空文。"""
    byday: dict[str, list] = defaultdict(list)
    allrows: list[dict] = []
    try:
        fh = open(path, encoding="utf-8")
    except FileNotFoundError:
        return byday, allrows
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            text = (r.get("text") or "").strip()
            if not text or text.startswith("RT @"):
                continue
            d = (r.get("cu") or r.get("created_at") or r.get("created") or "")[:10]
            if not d:
                continue
            try:
                eng = int(r.get("eng") or 0)
            except Exception:
                eng = 0
            rec = {"id": str(r.get("id") or ""), "h": (r.get("h") or r.get("handle") or "").lstrip("@"),
                   "cu": d, "text": text, "eng": eng}
            byday[d].append(rec)
            allrows.append(rec)
    return byday, allrows


def _url(rec: dict) -> str:
    return f"https://x.com/{rec['h']}/status/{rec['id']}" if rec["h"] and rec["id"] else "#"


# ----------------------------- 异动判定 -----------------------------
def _roll(series, winset, updown, look, thr, floor, cap):
    """滚动基线 z 检测：对窗口内每日，用其前 look 天的均值/标准差算 z，|z|≥thr 命中；取 |z| 最大的前 cap 个。"""
    vals = [v for _, v in series]
    out = []
    for i, (d, x) in enumerate(series):
        if d not in winset:
            continue
        prior = vals[max(0, i - look):i]
        if len(prior) < 5:
            continue
        m = st.mean(prior)
        s = max(st.pstdev(prior), floor)
        z = (x - m) / s
        if updown == "up" and z < thr:
            continue
        if updown == "both" and abs(z) < thr:
            continue
        out.append({"day": d, "value": round(x, 2), "z": round(z, 2),
                    "direction": "up" if z >= 0 else "down"})
    out.sort(key=lambda r: -abs(r["z"]))
    return out[:cap]


# ----------------------------- AI 归因 / 方面 -----------------------------
def _reason(ticker: str, day: str, ctx: str, tweets: list[dict]):
    sample = sorted(tweets, key=lambda r: -r["eng"])[:28]
    if not sample:
        return None
    lines = [f'- @{t["h"]} ({t["eng"]}): {t["text"][:200]}' for t in sample]
    sysmsg = (
        "你是资深美股舆情分析师。给你某标的某一天的 KOL（X 大V）推文。该日舆情出现异常：" + ctx + "。"
        "用一句话说明**为何**：只点出当天最主要的催化事件或主导话题，要具体、可证伪"
        "（提到具体事件/数据/人物/技术位/财报等），不要空话套话，不要复述指标本身。"
        '严格输出 JSON：{"zh":"中文一句话(≤45字)","en":"one English sentence(≤28 words)"}。'
    )
    usr = f"标的:{ticker}  日期:{day}\n当天 KOL 推文（按互动排序）:\n" + "\n".join(lines)
    try:
        data = messages_json(LOW, sysmsg, usr, max_tokens=240)
    except Exception:
        data = None
    if isinstance(data, dict) and (data.get("zh") or data.get("en")):
        return {"zh": (data.get("zh") or data.get("en") or "").strip(),
                "en": (data.get("en") or data.get("zh") or "").strip()}
    return None


# 注：「近期最密集讨论方面 / 新叙事」两功能已于 2026-06-28 下线（前端组件删除）；本脚本只产出 异动归因 + 聪明钱↔散户分歧。


# ----------------------------- 聪明钱 ↔ 散户 分歧（feature 1）-----------------------------
def _skill_map(skill_dir: str, hz: int = 5) -> dict[str, float]:
    """复刻 gen_topinvestors 的【跨标的 base-rate 校正 z】→ {handle: z}（仅 ≥30 个已结算 call 的作者）。
    这是『聪明钱』的权重源：z 越高=选股越不像运气（已过样本外持续性检验，见 KOL_SKILL_REPORT.md）。"""
    px = json.load(open(f"{skill_dir}/mt_prices.json", encoding="utf-8"))
    SER = {t: ([dt.date.fromisoformat(d) for d, _ in s], [c for _, c in s]) for t, s in px.items()}

    def fwd(t, d, td):
        if t not in SER:
            return None
        ds, cs = SER[t]
        i = bisect_left(ds, d)
        return None if i >= len(ds) or i + td >= len(cs) else cs[i + td] / cs[i] - 1.0

    def exc(t, d):  # 相对 SPY 的 hz 日超额（剥离 beta）
        a, b = fwd(t, d, hz), fwd("SPY", d, hz)
        return None if a is None or b is None else a - b

    def base(t):  # 该票盲多 hz 日跑赢 SPY 的概率（base rate）
        if t not in SER:
            return None
        ds, _ = SER[t]
        es = [e for d in ds if dt.date(2025, 12, 1) <= d < dt.date(2026, 7, 1)
              for e in [exc(t, d)] if e is not None]
        return (sum(1 for e in es if e > 0) / len(es)) if len(es) >= 15 else None

    mt = [json.loads(l) for l in open(f"{skill_dir}/mt_scoped.jsonl", encoding="utf-8")]
    mts = json.load(open(f"{skill_dir}/mt_stance.json", encoding="utf-8"))
    mcalls: dict[str, list] = defaultdict(list)
    seen = set()
    for r in mt:
        sst = mts.get(r["id"])
        if not sst or not sst.get("is_call") or sst.get("stance") not in ("bull", "bear"):
            continue
        d = dt.date.fromisoformat(r["cu"])
        for t in r.get("cash", []):
            if t not in SER:
                continue
            k = (r["h"], t, r["cu"], sst["stance"])
            if k in seen:
                continue
            seen.add(k)
            mcalls[r["h"]].append((d, t, sst["stance"]))
    TKS = {t for v in mcalls.values() for _, t, _ in v}
    BASE = {t: base(t) for t in TKS}

    def zscore(cl):  # base-rate 校正后的命中 z（剥离每票漂移）
        it = [(t, s, e) for d, t, s in cl if BASE.get(t) is not None for e in [exc(t, d)] if e is not None]
        if not it:
            return None, 0
        hits = sum(1 for t, s, e in it if (e > 0 if s == "bull" else e < 0))
        ps = [(BASE[t] if s == "bull" else 1 - BASE[t]) for t, s, e in it]
        var = sum(p * (1 - p) for p in ps)
        return ((hits - sum(ps)) / math.sqrt(var) if var > 0 else 0.0), len(it)

    out = {}
    for h, cl in mcalls.items():
        z, n = zscore(cl)
        if n >= 30 and z is not None:
            out[h] = z
    return out


def _sign(stance: str) -> float:
    return 1.0 if stance == "bull" else (-1.0 if stance == "bear" else 0.0)


def compute_divergence(ticker: str, con: sqlite3.Connection, skill_dir: str, win: list[str], allrows: list[dict]):
    """两条净情绪线：smart=技能加权 KOL（仅 z>0 已验证作者，按 z×ln(1+互动) 加权），retail=retail_sentiment_daily。
    两线各按自身窗口峰值归一到 [-1,1]（比的是方向/分歧、不是绝对量级）；附『当前读数』(谁多谁空 + 是否背离)。"""
    try:
        overall = _skill_map(skill_dir)
        pls = json.load(open(f"{skill_dir}/{ticker.lower()}_x6m_stance.json", encoding="utf-8"))
    except FileNotFoundError:
        return None
    smart: dict[str, float] = defaultdict(float)
    n_skilled = 0
    for r in allrows:  # allrows 已过滤 RT、含 id/h/cu/eng
        sst = pls.get(r["id"])
        if not sst:
            continue
        s = sst.get("stance")
        if s not in ("bull", "bear"):
            continue
        z = overall.get(r["h"])
        if z is None or z <= 0:  # 只让『已验证的正技能』声音进 smart 线 = 聪明钱
            continue
        n_skilled += 1
        smart[r["cu"]] += _sign(s) * z * (1.0 + math.log1p(max(0, r["eng"])))
    retail = {d: float(v or 0) for d, v in con.execute(
        "SELECT day, net FROM retail_sentiment_daily WHERE ticker=? ORDER BY day", (ticker,))}
    sm = [smart.get(d, 0.0) for d in win]
    rt = [retail.get(d, 0.0) for d in win]

    def norm(a):
        mx = max((abs(x) for x in a), default=0) or 1.0
        return [round(x / mx, 3) for x in a]

    smN, rtN = norm(sm), norm(rt)
    series = [{"day": d, "smart": smN[i], "retail": rtN[i]} for i, d in enumerate(win)]

    def stance_of(vals):
        recent = [v for v in vals if abs(v) > 1e-9][-3:]
        if not recent:
            return "neutral"
        m = sum(recent) / len(recent)
        return "bull" if m > 0.05 else ("bear" if m < -0.05 else "neutral")

    sS, rS = stance_of(smN), stance_of(rtN)
    diverging = sS != "neutral" and rS != "neutral" and sS != rS
    return {"series": series, "read": {"smart": sS, "retail": rS, "diverging": diverging}, "smartAuthors": n_skilled}


# ----------------------------- 主流程 -----------------------------
def run(ticker: str, kol_file: str, window: int, look: int, aspect_days: int, cap: int,
        skill_dir: str = "/tmp", recent_days: int = 7, prior_days: int = 21):
    if not available(LOW):
        raise SystemExit("[overall] QWEN key 未就绪 → 无法生成 AI 归因/方面")

    con = sqlite3.connect(str(DB))
    tdays = _trading_days(con, ticker)
    if len(tdays) < 6:
        raise SystemExit(f"[overall] {ticker} 价格交易日不足（{len(tdays)}）")
    win = tdays[-window:]
    winset, tradeset = set(win), set(tdays)

    # 情绪跑交易日序列（与折线轴一致）；讨论度跑日历日序列（与条状轴一致）
    sent = [(d, v) for d, v in _series(con, "kol_sentiment_daily", "net", ticker) if d in tradeset]
    vol = _series(con, "kol_volume_daily", "n_total", ticker)
    sA = _roll(sent, winset, "both", look, 2.0, 0.5, cap)
    vA = _roll(vol, winset, "up", look, 2.0, 3.0, cap)
    for a in sA:
        a["metric"] = "sentiment"
    for a in vA:
        a["metric"] = "volume"
    print(f"[overall] {ticker} sentiment={[a['day'] for a in sA]}  volume={[a['day'] for a in vA]}", flush=True)

    byday, allrows = _load_tweets(kol_file)
    if not allrows:
        print(f"[overall] ⚠ KOL 文本源为空：{kol_file} → 异动归因将缺失", flush=True)

    # 每个异常「日」一条归因（同日多指标共用；reason 为「当天发生了什么」，与指标无关）
    by_anom_day: dict[str, list] = defaultdict(list)
    for a in sA + vA:
        by_anom_day[a["day"]].append(a)
    reason_cache: dict[str, dict | None] = {}
    for d in sorted(by_anom_day):
        parts = []
        for a in by_anom_day[d]:
            if a["metric"] == "sentiment":
                parts.append("净情绪异常" + ("走高(偏多)" if a["direction"] == "up" else "走低(偏空)"))
            else:
                parts.append("讨论度异常放量")
        ctx = " + ".join(dict.fromkeys(parts))
        reason_cache[d] = _reason(ticker, d, ctx, byday.get(d, []))
        print(f"  · {d} [{ctx}] → {(reason_cache[d] or {}).get('zh', '(无归因)')}", flush=True)

    anomalies = []
    for a in sorted(sA + vA, key=lambda r: (r["day"], r["metric"])):
        anomalies.append({"day": a["day"], "metric": a["metric"], "direction": a["direction"],
                          "z": a["z"], "reason": reason_cache.get(a["day"]) or {"zh": "", "en": ""}})

    # 聪明钱 ↔ 散户 分歧（技能加权 KOL vs retail_sentiment_daily），对齐展示窗口 win
    divergence = compute_divergence(ticker, con, skill_dir, win, allrows)
    if divergence:
        rd = divergence["read"]
        print(f"[overall] divergence: smart={rd['smart']} retail={rd['retail']} 背离={rd['diverging']} "
              f"(skilled tweets={divergence['smartAuthors']})", flush=True)
    else:
        print("[overall] ⚠ 分歧线缺技能/立场数据 → 跳过", flush=True)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    blob = {}
    if OUT.exists():
        try:
            blob = json.loads(OUT.read_text(encoding="utf-8"))
        except Exception:
            blob = {}
    blob[ticker] = {
        "anomalies": anomalies,
        "divergence": divergence,
        "window": {"start": win[0], "end": win[-1]},
        "updated_at": datetime.utcnow().isoformat(),
    }
    OUT.write_text(json.dumps(blob, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[overall] 写入 {OUT}（{ticker}: {len(anomalies)} 异动）", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ticker", default="PLTR")
    ap.add_argument("--kol-file", default=None, help="KOL 推文抽取 jsonl；默认 /tmp/<ticker>_x6m.jsonl")
    ap.add_argument("--window", type=int, default=11, help="展示窗口=最近 N 个交易日")
    ap.add_argument("--look", type=int, default=14, help="异动滚动基线天数")
    ap.add_argument("--aspect-days", type=int, default=14, help="『近期方面』回看天数")
    ap.add_argument("--cap", type=int, default=3, help="每个指标最多取几个异动")
    ap.add_argument("--skill-dir", default="/tmp", help="技能 z 与 stance 缓存目录（mt_*/<ticker>_x6m_stance.json）")
    ap.add_argument("--recent-days", type=int, default=7, help="新叙事 RECENT 窗口")
    ap.add_argument("--prior-days", type=int, default=21, help="新叙事 PRIOR 基线窗口")
    args = ap.parse_args()
    ticker = args.ticker.upper()
    kol_file = args.kol_file or f"/tmp/{ticker.lower()}_x6m.jsonl"
    run(ticker, kol_file, args.window, args.look, args.aspect_days, args.cap,
        args.skill_dir, args.recent_days, args.prior_days)


if __name__ == "__main__":
    main()
