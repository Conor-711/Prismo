"""第一版算法实验（v1，刻意简单）——5 平台近 30 天数据的：
  1) EDA：每平台分布 / 结构性看涨偏差 μ / 多空基率 / 声量重尾 / 周内季节性；
  2) 每平台-每标的 简单基线：声量(对数+中位数/MAD 稳健) + 情绪(均值/σ)；
  3) 异动：稳健 z / z，双门控（统计显著 ∧ 绝对量达标）；
  4) 跨平台**标准化后**对比（先在各平台内 demean+标准化，再比 → 修正"论坛天生看涨"偏差）。

读取：gr_post(region in jp/kr/tw/cn, sentiment 已由 gr-tag 打) + 美股 Reddit(posts×mentions, 本脚本内用
同款 DeepSeek flash 英文 prompt 打分，缓存到 data/exports/exp_us_tags.json)。
本脚本**只读主库、不写库**（US 打分只落 JSON 缓存与报告），属探索性实验。

运行：DATABASE_URL='sqlite:///./data/dev.db' python -m pipeline.analyze.experiment_v1
"""
from __future__ import annotations

import datetime as dt
import json
import math
import re
import statistics
from collections import defaultdict
from pathlib import Path

from sqlalchemy import and_, select

from ..common.db import session_scope
from ..common.llm import LOW, available, messages_json
from ..common.models import GrPost, Mention, Post
from ..ingest.global_retail_crawl import load_targets

WINDOW_DAYS = 30
MIN_POSTS = 30    # (论坛,标的) 参与跨平台对比/异动的最低总帖数（薄样本不出信号）
MIN_DAYS = 10     # 最低活跃天数（覆盖窗太短不可信）
MAD_FLOOR = 0.35  # 稳健 z 的 MAD 下限（防低方差序列把小变化放大成假异动）
PLATFORMS = ["us", "cn", "jp", "kr", "tw"]
PLATFORM_ZH = {"us": "美国 Reddit", "cn": "中国大陆 雪球", "jp": "日本 Yahoo", "kr": "韩国 Naver", "tw": "台湾 PTT"}
EXPORT = Path("data/exports")
US_CACHE = EXPORT / "exp_us_tags.json"

SYSTEM_US = """You are a financial sentiment scorer. Below are posts from US retail investors (Reddit: r/wallstreetbets, r/stocks, r/investing...) each discussing a specific US stock. They may contain slang, irony and memes. For EACH post output a sentiment score s from -1.0 (very bearish) to +1.0 (very bullish); 0 = neutral / off-topic / noise.
Slang: calls/long/buy the dip/diamond hands/to the moon/printer/LFG = bullish; puts/short/bagholder/rug/drilling/guh/it's over/cooked = bearish; over-the-top sarcastic hype is often = bearish (irony).
Output ONLY a JSON array, each element {"i": index, "s": score}, indices matching input order, no extra text."""


def _stance(s: float) -> str:
    return "bull" if s > 0.15 else "bear" if s < -0.15 else "neutral"


# 英文/WSB 关键词启发式：当 flash 漏返某条时兜底（对标 gr-tag 的 _cjk_score，避免整批丢弃）。
_EN_BULL = re.compile(r"\b(call|calls|long|buy|buying|bull|bullish|moon|rocket|squeeze|breakout|rip|pump|tendies|diamond|hodl|undervalued|beat|beats|upgrade|rally|green|lfg|printer)\b", re.I)
_EN_BEAR = re.compile(r"\b(put|puts|short|shorting|bear|bearish|crash|dump|drill|drilling|sell|selling|baghold|bagholder|rug|overvalued|miss|misses|downgrade|guh|cooked|tank|tanking|drop|dump|red|puts)\b", re.I)


def _en_score(text: str) -> float:
    b = len(_EN_BULL.findall(text or "")); s = len(_EN_BEAR.findall(text or ""))
    if b == s:
        return 0.0
    return max(-1.0, min(1.0, round((b - s) / max(1, b + s) * 0.6, 3)))


# ----------------------------- 纯 Python 统计helpers -----------------------------
def _mean(xs): return statistics.fmean(xs) if xs else 0.0
def _std(xs): return statistics.pstdev(xs) if len(xs) > 1 else 0.0
def _median(xs): return statistics.median(xs) if xs else 0.0


def _mad(xs):
    if not xs:
        return 0.0
    m = statistics.median(xs)
    return statistics.median([abs(x - m) for x in xs])


def _pct(xs, q):
    if not xs:
        return 0.0
    ys = sorted(xs)
    k = (len(ys) - 1) * q
    f, c = math.floor(k), math.ceil(k)
    if f == c:
        return ys[int(k)]
    return ys[f] + (ys[c] - ys[f]) * (k - f)


def _skew(xs):
    n = len(xs)
    if n < 3:
        return 0.0
    m, sd = statistics.fmean(xs), statistics.pstdev(xs)
    if sd == 0:
        return 0.0
    return sum(((x - m) / sd) ** 3 for x in xs) / n


def _kurt(xs):  # 超额峰度（正态=0）
    n = len(xs)
    if n < 4:
        return 0.0
    m, sd = statistics.fmean(xs), statistics.pstdev(xs)
    if sd == 0:
        return 0.0
    return sum(((x - m) / sd) ** 4 for x in xs) / n - 3.0


def _day(ts): return ts.strftime("%Y-%m-%d")


# ----------------------------- 取数 -----------------------------
def load_gr(cutoff):
    with session_scope() as s:
        rows = s.execute(
            select(GrPost.region, GrPost.ticker, GrPost.created_utc, GrPost.sentiment,
                   GrPost.stance, GrPost.likes, GrPost.views, GrPost.comments)
            .where(GrPost.created_utc >= cutoff, GrPost.sentiment.isnot(None))
        ).all()
    out = []
    for region, tk, ts, sent, stance, likes, views, comments in rows:
        out.append(dict(platform=region, ticker=tk, ts=ts, sentiment=float(sent),
                        stance=stance or _stance(float(sent)),
                        eng=int((likes or 0) + (views or 0) + (comments or 0))))
    return out


def tag_us(textmap: dict) -> dict:
    cache = json.loads(US_CACHE.read_text(encoding="utf-8")) if US_CACHE.exists() else {}
    todo = {pid: t for pid, t in textmap.items() if pid not in cache and t}
    if todo and available(LOW):
        items = list(todo.items())
        batches = [items[i:i + 10] for i in range(0, len(items), 10)]
        print(f"[us-tag] {len(todo)} 帖待打分 → {len(batches)} 批", flush=True)
        from concurrent.futures import ThreadPoolExecutor, as_completed

        def run(batch):
            lines = [f"{i}. {t}" for i, (pid, t) in enumerate(batch, 1)]
            try:
                data = messages_json(LOW, SYSTEM_US, "\n".join(lines), max_tokens=1500)
            except Exception:  # noqa: BLE001
                data = None
            o = {}
            if isinstance(data, list):
                for it in data:
                    try:
                        idx = int(it.get("i")); sc = float(it.get("s"))
                        if 1 <= idx <= len(batch):
                            o[batch[idx - 1][0]] = max(-1.0, min(1.0, round(sc, 3)))
                    except (TypeError, ValueError, AttributeError):
                        continue
            for pid, t in batch:  # flash 漏返的用英文启发式兜底（不丢样本，对标 gr-tag）
                o.setdefault(pid, _en_score(t))
            return o

        with ThreadPoolExecutor(max_workers=8) as ex:
            futs = [ex.submit(run, b) for b in batches]
            for i, f in enumerate(as_completed(futs), 1):
                cache.update(f.result())
                if i % 10 == 0 or i == len(batches):
                    print(f"[us-tag] {i}/{len(batches)} 批", flush=True)
        EXPORT.mkdir(parents=True, exist_ok=True)
        US_CACHE.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    return cache


def load_us(cutoff, universe):
    with session_scope() as s:
        rows = s.execute(
            select(Post.id, Mention.ticker, Post.created_utc, Post.title, Post.selftext,
                   Post.score, Post.num_comments)
            .join(Mention, and_(Mention.item_id == Post.id, Mention.item_type == "post"))
            .where(Post.market == "us", Post.source == "scan",
                   Post.created_utc >= cutoff, Mention.ticker.in_(list(universe)))
        ).all()
    pairs, textmap = [], {}
    for pid, tk, ts, title, body, score, nc in rows:
        pairs.append((pid, tk, ts, int((score or 0) + (nc or 0))))
        if pid not in textmap:
            textmap[pid] = f"{title or ''} {body or ''}".strip()[:280]
    tags = tag_us(textmap)
    out = []
    for pid, tk, ts, eng in pairs:
        sc = tags.get(pid)
        if sc is None:
            continue
        out.append(dict(platform="us", ticker=tk, ts=ts, sentiment=float(sc),
                        stance=_stance(float(sc)), eng=eng))
    return out


# ----------------------------- 分析 -----------------------------
def eda(rows):
    byp = defaultdict(list)
    for r in rows:
        byp[r["platform"]].append(r)
    out = {}
    for p in PLATFORMS:
        rs = byp.get(p, [])
        if not rs:
            continue
        sents = [r["sentiment"] for r in rs]
        days = sorted({_day(r["ts"]) for r in rs})
        volday = defaultdict(int)
        for r in rs:
            volday[_day(r["ts"])] += 1
        vols = list(volday.values())
        nb = sum(1 for r in rs if r["stance"] == "bull")
        nbe = sum(1 for r in rs if r["stance"] == "bear")
        nn = len(rs) - nb - nbe
        dow_vol = defaultdict(int)
        dow_sent = defaultdict(list)
        for r in rs:
            dow_vol[r["ts"].weekday()] += 1
            dow_sent[r["ts"].weekday()].append(r["sentiment"])
        out[p] = dict(
            posts=len(rs), tickers=len({r["ticker"] for r in rs}),
            days=len(days), span=f"{days[0]}→{days[-1]}",
            mu_sent=round(_mean(sents), 3), med_sent=round(_median(sents), 3), sd_sent=round(_std(sents), 3),
            bull_pct=round(100 * nb / len(rs), 1), bear_pct=round(100 * nbe / len(rs), 1),
            neutral_pct=round(100 * nn / len(rs), 1),
            bull_bear_ratio=round(nb / nbe, 2) if nbe else None,
            vol_mean=round(_mean(vols), 1), vol_med=round(_median(vols), 1),
            vol_skew=round(_skew(vols), 2), vol_kurt=round(_kurt(vols), 2),
            dow_vol={d: dow_vol.get(d, 0) for d in range(7)},
            dow_sent={d: round(_mean(dow_sent.get(d, [0])), 3) for d in range(7)},
        )
    return out


def anomalies(rows):
    grp = defaultdict(lambda: defaultdict(list))  # (platform,ticker)->day->[sent]
    for r in rows:
        grp[(r["platform"], r["ticker"])][_day(r["ts"])].append(r["sentiment"])
    out = []
    for (p, tk), days in grp.items():
        ad = sorted(days.keys())
        total = sum(len(v) for v in days.values())
        if len(ad) < MIN_DAYS or total < MIN_POSTS:  # 覆盖窗太短/样本太薄 → 不判
            continue
        vol = {d: len(days[d]) for d in ad}
        sent = {d: _mean(days[d]) for d in ad}
        logv = {d: math.log1p(v) for d, v in vol.items()}
        med, mad = _median(list(logv.values())), max(_mad(list(logv.values())), MAD_FLOOR)
        smean, ssd = _mean(list(sent.values())), max(_std(list(sent.values())), 0.08)
        for d in ad:
            rz = 0.6745 * (logv[d] - med) / mad          # 稳健 z（对数声量）
            zs = (sent[d] - smean) / ssd                  # z（日均情绪，已是该标的自身基线）
            # 声量只报**正向 spike**（放量）：掉量多为周末/季节性，暂不报（待 v2 去季节后再纳入）
            if rz >= 2.5 and vol[d] >= 5:
                out.append(dict(platform=p, ticker=tk, day=d, kind="放量", z=round(rz, 2),
                                vol=vol[d], sent=round(sent[d], 2)))
            if abs(zs) >= 2.5 and vol[d] >= 5:
                out.append(dict(platform=p, ticker=tk, day=d, kind="情绪", z=round(zs, 2),
                                vol=vol[d], sent=round(sent[d], 2)))
    out.sort(key=lambda x: -abs(x["z"]))
    return out


def cross_platform(rows):
    """先在各平台内 demean + 标准化（消除"论坛天生看涨"），再跨平台比。
    **可靠性门槛**：(论坛,标的) 需 ≥MIN_POSTS 帖 且 ≥MIN_DAYS 天才参与，薄样本不出信号。"""
    cell = defaultdict(lambda: defaultdict(lambda: {"s": [], "d": set()}))  # platform->ticker->{s,d}
    for r in rows:
        c = cell[r["platform"]][r["ticker"]]
        c["s"].append(r["sentiment"]); c["d"].add(_day(r["ts"]))
    pmean, pstd, tmean, tn = {}, {}, defaultdict(dict), defaultdict(dict)
    for p, tks in cell.items():
        means = {tk: _mean(c["s"]) for tk, c in tks.items()
                 if len(c["s"]) >= MIN_POSTS and len(c["d"]) >= MIN_DAYS}
        tmean[p] = means
        for tk in means:
            tn[p][tk] = len(tks[tk]["s"])
        vals = list(means.values())
        pmean[p] = _mean(vals)
        pstd[p] = _std(vals) or 0.1
    z = defaultdict(dict); zn = defaultdict(dict)  # ticker->platform->z / n
    for p, means in tmean.items():
        for tk, m in means.items():
            z[tk][p] = (m - pmean[p]) / pstd[p]; zn[tk][p] = tn[p][tk]
    rows_out = []
    for tk, zz in z.items():
        if len(zz) < 3:  # 至少 3 个可靠平台才比
            continue
        pos = sum(1 for v in zz.values() if v > 0.4)
        neg = sum(1 for v in zz.values() if v < -0.4)
        if pos >= 2 and neg == 0:
            label = "共识看多"
        elif neg >= 2 and pos == 0:
            label = "共识看空"
        elif pos >= 1 and neg >= 1:
            label = "地区分歧"
        else:
            label = "中性/混合"
        rows_out.append(dict(ticker=tk, label=label,
                             spread=round(max(zz.values()) - min(zz.values()), 2),
                             z={k: round(v, 2) for k, v in sorted(zz.items())},
                             n={k: zn[tk][k] for k in sorted(zz)}))
    rows_out.sort(key=lambda x: -x["spread"])
    return rows_out, {p: round(v, 3) for p, v in pmean.items()}


# ----------------------------- 报告 -----------------------------
def build_report(now, rows, ed, anos, cross, cross_pmean):
    L = []
    L.append("# 第一版算法实验报告（v1）\n")
    L.append(f"> 数据锚点 now={now:%Y-%m-%d}，窗口近 {WINDOW_DAYS} 天；总样本 {len(rows)} 帖（5 平台）。")
    L.append("> 方法刻意简单：每平台独立基线 + 稳健 z 异动 + 平台内标准化后跨平台比。仅供方法论验证，非投资建议。\n")

    L.append("## 1. 每平台画像（EDA）\n")
    L.append("| 平台 | 帖数 | 标的 | 天数 | 覆盖窗 | 结构情绪μ | 中位 | σ | 看多% | 看空% | 中性% | 多/空比 | 日均声量 | 声量偏度 | 声量峰度 |")
    L.append("|---|--:|--:|--:|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|")
    for p in PLATFORMS:
        e = ed.get(p)
        if not e:
            continue
        L.append(f"| {PLATFORM_ZH[p]} | {e['posts']} | {e['tickers']} | {e['days']} | {e['span']} | "
                 f"**{e['mu_sent']:+.3f}** | {e['med_sent']:+.3f} | {e['sd_sent']:.3f} | {e['bull_pct']} | "
                 f"{e['bear_pct']} | {e['neutral_pct']} | {e['bull_bear_ratio']} | {e['vol_mean']} | "
                 f"{e['vol_skew']} | {e['vol_kurt']} |")
    L.append("\n**读法**：`结构情绪μ` = 该平台所有帖的平均情绪 = 它的「天生偏多」基线（§2.7），跨平台比情绪必须先减掉它；"
             "`多/空比`>1 即结构性看多（Miller 1977）；声量`偏度/峰度`远大于 0 = 重尾，**不能用高斯 z**，故声量异动用对数+中位数/MAD 稳健 z。\n")

    L.append("## 2. 周内季节性（验证「要不要去季节」）\n")
    L.append("| 平台 | 周一 | 周二 | 周三 | 周四 | 周五 | 周六 | 周日 |")
    L.append("|---|--:|--:|--:|--:|--:|--:|--:|")
    for p in PLATFORMS:
        e = ed.get(p)
        if not e:
            continue
        v = e["dow_vol"]
        L.append(f"| {PLATFORM_ZH[p]} 声量 | " + " | ".join(str(v.get(d, 0)) for d in range(7)) + " |")
    L.append("\n> 若周末显著低于工作日 → 声量基线需去周内效应，否则会把「周一正常上量」误报成异动。\n")

    L.append(f"## 3. 异动榜（近 {WINDOW_DAYS} 天；放量正向 z≥2.5 或情绪 |z|≥2.5，当日≥5 帖；标的需 ≥{MIN_POSTS}帖&≥{MIN_DAYS}天）\n")
    L.append("| 平台 | 标的 | 日期 | 类型 | z | 当日帖 | 当日情绪 |")
    L.append("|---|---|---|---|--:|--:|--:|")
    for a in anos[:25]:
        L.append(f"| {PLATFORM_ZH[a['platform']]} | {a['ticker']} | {a['day']} | {a['kind']} | "
                 f"**{a['z']:+.2f}** | {a['vol']} | {a['sent']:+.2f} |")
    L.append(f"\n> 共 {len(anos)} 条异动。声量异动=讨论度突然脱离常态；情绪异动=情绪相对该标的自身近 30 天均值大幅偏离。\n")

    L.append(f"## 4. 跨平台标准化对比（已消除各平台「天生看涨」偏差；**门槛 ≥{MIN_POSTS}帖 & ≥{MIN_DAYS}天，薄样本剔除**）\n")
    L.append("各平台 demean 基线：" + "，".join(f"{PLATFORM_ZH[p]} {cross_pmean.get(p, 0):+.3f}" for p in PLATFORMS if p in cross_pmean) + "\n")
    L.append("| 标的 | 结论 | 分歧spread | 各平台标准化情绪 z（n=可靠帖数）|")
    L.append("|---|---|--:|---|")
    for c in cross[:25]:
        zstr = "，".join(f"{PLATFORM_ZH[k].split()[0]}{v:+.2f}(n{c['n'][k]})" for k, v in c["z"].items())
        L.append(f"| {c['ticker']} | {c['label']} | {c['spread']} | {zstr} |")
    L.append("\n> 这里的「看多/看空」是**相对各平台自身常态**的标准化结果，而非原始情绪值——"
             "所以一个平台即便绝对情绪仍为正，只要显著低于它平时的乐观度，也会被判为相对看空。这正是修正结构性偏差后的真信号。\n")
    return "\n".join(L)


def main():
    now = None
    universe = {t["ticker"] for t in load_targets()}
    # 数据锚定的 now = 全样本最大时间
    with session_scope() as s:
        gmax = s.execute(select(GrPost.created_utc).order_by(GrPost.created_utc.desc()).limit(1)).scalar()
        pmax = s.execute(select(Post.created_utc).where(Post.market == "us", Post.source == "scan")
                         .order_by(Post.created_utc.desc()).limit(1)).scalar()
    now = max([t for t in [gmax, pmax] if t] or [dt.datetime.utcnow()])
    cutoff = now - dt.timedelta(days=WINDOW_DAYS)
    print(f"[exp] now={now:%Y-%m-%d %H:%M} cutoff={cutoff:%Y-%m-%d}", flush=True)

    rows = load_gr(cutoff) + load_us(cutoff, universe)
    print(f"[exp] 载入 {len(rows)} 帖", flush=True)
    ed = eda(rows)
    anos = anomalies(rows)
    cross, cross_pmean = cross_platform(rows)

    report = build_report(now, rows, ed, anos, cross, cross_pmean)
    EXPORT.mkdir(parents=True, exist_ok=True)
    (EXPORT / "experiment_v1_report.md").write_text(report, encoding="utf-8")
    json.dump({"now": now.isoformat(), "eda": ed, "anomalies": anos, "cross": cross, "cross_pmean": cross_pmean},
              open(EXPORT / "experiment_v1_data.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("[exp] 报告 → data/exports/experiment_v1_report.md", flush=True)
    print(report)


if __name__ == "__main__":
    main()
