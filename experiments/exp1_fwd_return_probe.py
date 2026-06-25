"""实验 1 —— 论坛信号对前向收益的预测力探针（go/no-go，非回测、非已验证 alpha）。

来自多角色调研 + 互评的共识方案（DECISION_equity1000_port.md §3）。
把 equity1000 的【验证方法学】移植到 Prismo 论坛数据：横截面 (ticker,day) 面板，
6 个论坛信号 vs 前向 SPY 相对收益，1000× shuffle null 作对抗性零假设。

只读：读 data/prismo_snapshot.db（本地快照）+ yfinance 价格（带本地缓存）。不写库。

预注册判定（N=3, SPY 相对）：
  GO  当 {attention_share, raw_dir, qw_dir, mean_sentiment} 中 ≥1 个：
       |r| 超过其 shuffle null 的 95 分位  AND  在 ≥3/5 标的上方向一致  AND  中位分桶单调。
  否则 = NO-GO / 不确定（大概率，且可接受）→ "现在别建滚动 regime 引擎"。
"""
from __future__ import annotations

import json
import math
import os
import sqlite3
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "prismo_snapshot.db"
SUBREDDITS_YML = ROOT / "pipeline" / "data" / "subreddits.yml"
PRICE_CACHE = ROOT / "experiments" / "prices_cache.json"

CORE = ["NVDA", "GOOGL", "TSLA", "AMZN", "MSFT"]  # 密集 US 单名（SPCX pre-IPO 已排除）
BENCH = "SPY"
HORIZONS = [3, 5]
MIN_N = 5            # 入选 (ticker,day) 的最小 stance 帖数
ENTROPY_MIN_N = 8    # consensus_entropy 的门槛
N_SHUFFLE = 1000
RNG = np.random.default_rng(20260619)

STANCE_FIX = {"bullish": "bull", "bearish": "bear"}  # COALESCE 错标
SIGN = {"bull": 1.0, "bear": -1.0, "neutral": 0.0}
SQUEEZE_KEYS = ("逼空", "squeeze", "meme", "Meme", "迷因")


# ---------------- 1. 子版块权重 ----------------
def load_weights() -> dict:
    y = yaml.safe_load(open(SUBREDDITS_YML, encoding="utf-8"))
    return {s["name"].lower(): float(s.get("weight", 1.0)) for s in y["subreddits"]}


# ---------------- 2. 逐 (ticker, day) 信号（从原始表重算）----------------
def build_signals() -> pd.DataFrame:
    con = sqlite3.connect(DB)
    weights = load_weights()
    # 子版块 id → display_name
    subs = pd.read_sql("SELECT id, display_name FROM subreddits", con)
    sub_name = dict(zip(subs.id, subs.display_name))

    rows = pd.read_sql(
        """
        SELECT m.ticker AS ticker,
               p.created_utc AS created_ts,
               ia.analyzed_at AS analyzed_at,
               p.subreddit_id AS sub_id,
               p.score AS score, p.num_comments AS ncom,
               m.confidence AS conf,
               ia.stance AS stance, ia.sentiment_score AS sent,
               ia.quality_score AS qual, ia.themes AS themes
        FROM mentions m
        JOIN posts p ON p.id = m.item_id
        JOIN item_analysis ia ON ia.item_id = m.item_id
        WHERE m.item_type='post' AND p.market='us' AND p.source='scan'
        """,
        con,
    )
    con.close()

    # ET 交易日归属：created_utc(UTC) → EDT(UTC-4) 的日历日，避免 UTC 日界把盘后帖错配到下一日
    ct = pd.to_datetime(rows["created_ts"])
    rows["day"] = (ct - pd.Timedelta(hours=4)).dt.strftime("%Y-%m-%d")
    # 防泄漏（entry-lag as-of）：在 session 日 D 的次交易日(D+1)开盘前可得的分析才算数。
    # 进场点设在 D+1（隔夜批次已跑完），故剔除「分析晚于 D+1」的真·未来泄漏帖。
    rows["analyzed_day"] = pd.to_datetime(rows["analyzed_at"]).dt.strftime("%Y-%m-%d")
    rows["asof"] = (pd.to_datetime(rows["day"]) + pd.Timedelta(days=1)).dt.strftime("%Y-%m-%d")
    before = len(rows)
    rows = rows[rows["analyzed_day"] <= rows["asof"]].copy()
    print(f"[signals] 防泄漏 as-of(≤D+1) 过滤：{before} → {len(rows)} 行")

    rows["stance"] = rows["stance"].replace(STANCE_FIX)
    rows["sub_name"] = rows["sub_id"].map(sub_name)
    rows["subw"] = rows["sub_name"].str.lower().map(weights).fillna(1.0)
    matched = rows["sub_name"].str.lower().isin(weights).mean()
    print(f"[signals] 子版块权重覆盖率 {matched*100:.0f}%（未匹配按 1.0）")
    rows["att_unit"] = rows["conf"] * (1 + np.log1p(rows["score"].clip(lower=0))) * rows["subw"]
    rows["sign"] = rows["stance"].map(SIGN).fillna(0.0)
    rows["is_sq"] = rows["themes"].fillna("").apply(
        lambda t: any(k.lower() in t.lower() for k in SQUEEZE_KEYS)
    )

    # 每日全 US 注意力分母（所有 ticker）
    day_total = rows.groupby("day")["att_unit"].sum().rename("att_day_total")

    def agg(g: pd.DataFrame) -> pd.Series:
        nb = (g.stance == "bull").sum()
        nr = (g.stance == "bear").sum()
        nn = (g.stance == "neutral").sum()
        nstance = nb + nr + nn
        att = g.att_unit.sum()
        qsum = g.qual.sum()
        # entropy
        ent = np.nan
        if nstance >= ENTROPY_MIN_N:
            ps = [x / nstance for x in (nb, nr, nn) if x > 0]
            ent = -sum(p * math.log2(p) for p in ps)
        return pd.Series({
            "n_stance": nstance,
            "att_raw": att,
            "raw_dir": (nb - nr) / nstance if nstance else np.nan,
            "mean_sentiment": g.sent.mean(),
            "qw_dir": (g.sign * g.qual).sum() / qsum if qsum else np.nan,
            "engagement": (g.score + g.ncom).sum(),
            "consensus_entropy": ent,
            "squeeze_flag": int(g.is_sq.any()),
        })

    sig = rows.groupby(["ticker", "day"]).apply(agg, include_groups=False).reset_index()
    sig = sig.merge(day_total, on="day", how="left")
    sig["attention_share"] = sig["att_raw"] / sig["att_day_total"]
    sig = sig[(sig.ticker.isin(CORE)) & (sig.n_stance >= MIN_N)].copy()
    return sig


# ---------------- 3. 价格（yfinance + 缓存）----------------
def get_prices() -> pd.DataFrame:
    tickers = CORE + [BENCH]
    if PRICE_CACHE.exists():
        cache = json.load(open(PRICE_CACHE))
        if set(cache.keys()) >= set(tickers):
            print("[prices] 用本地缓存")
            df = pd.DataFrame({t: pd.Series(cache[t]) for t in tickers})
            df.index = pd.to_datetime(df.index)
            return df.sort_index()
    import yfinance as yf
    print("[prices] yfinance 拉取中…")
    out = {}
    for t in tickers:
        h = yf.Ticker(t).history(start="2026-06-01", end="2026-06-21", interval="1d")
        out[t] = {d.strftime("%Y-%m-%d"): float(c) for d, c in h["Close"].items()}
    json.dump(out, open(PRICE_CACHE, "w"))
    df = pd.DataFrame({t: pd.Series(out[t]) for t in tickers})
    df.index = pd.to_datetime(df.index)
    return df.sort_index()


def fwd_returns(prices: pd.DataFrame) -> pd.DataFrame:
    """进场点 = session 日 D 的次交易日(D+1)收盘；前向收益 close[D+1+N]/close[D+1]-1。
    （信号用 D 当日帖，进场延后一日让隔夜 AI 批次跑完 → 无前视。）"""
    recs = []
    spy = prices[BENCH]
    for t in CORE:
        s = prices[t].dropna()
        sr = spy.reindex(s.index)
        for N in HORIZONS:
            fr = s.shift(-(1 + N)) / s.shift(-1) - 1     # 进场 D+1，持有 N 交易日
            frb = sr.shift(-(1 + N)) / sr.shift(-1) - 1
            for d in s.index:
                recs.append({"ticker": t, "day": d.strftime("%Y-%m-%d"), "N": N,
                             "fwd": fr.get(d, np.nan), "fwd_rel": (fr.get(d, np.nan) - frb.get(d, np.nan))})
    return pd.DataFrame(recs)


# ---------------- 4. 统计 ----------------
def pearson(x, y):
    if len(x) < 3:
        return np.nan
    if np.std(x) == 0 or np.std(y) == 0:
        return np.nan
    return float(np.corrcoef(x, y)[0, 1])


def shuffle_null_pct(x, y, r_actual):
    if np.isnan(r_actual) or len(x) < 3:
        return np.nan, np.nan
    null = np.empty(N_SHUFFLE)
    y = np.asarray(y)
    for i in range(N_SHUFFLE):
        null[i] = abs(pearson(x, RNG.permutation(y)))
    pct = float((null < abs(r_actual)).mean() * 100)  # |r| 超过 null 的比例
    p_one = float((null >= abs(r_actual)).mean())
    return pct, p_one


SIGNALS = ["attention_share", "raw_dir", "mean_sentiment", "qw_dir", "engagement", "consensus_entropy"]
GO_SET = ["attention_share", "raw_dir", "qw_dir", "mean_sentiment"]


def main():
    sig = build_signals()
    prices = get_prices()
    fwd = fwd_returns(prices)
    panel = sig.merge(fwd, on=["ticker", "day"], how="inner")

    print(f"\n面板规模：{sig.shape[0]} 个 (ticker,day) 信号格 → 合并价格后 "
          f"{panel[panel.N==3].fwd_rel.notna().sum()} 行 (N=3) / "
          f"{panel[panel.N==5].fwd_rel.notna().sum()} 行 (N=5)")
    print("逐标的 anchor 天数：",
          dict(panel[panel.N == 3].dropna(subset=["fwd_rel"]).groupby("ticker").size()))
    days = sorted(panel.day.unique())
    print(f"anchor 日期范围：{days[0]} → {days[-1]}")

    go_hits = []
    for N in HORIZONS:
        print(f"\n{'='*72}\n前向 N={N} 交易日 · SPY 相对收益\n{'='*72}")
        print(f"{'signal':18s} {'n':>3s} {'r_rel':>7s} {'null%':>6s} {'p1':>6s} "
              f"{'r_raw':>7s} | {'hi_mean%':>8s} {'lo_mean%':>8s} {'hi_win%':>7s} {'sign_agree':>10s}")
        sub = panel[panel.N == N].copy()
        for s in SIGNALS:
            d = sub.dropna(subset=[s, "fwd_rel"])
            x, y = d[s].to_numpy(), d["fwd_rel"].to_numpy()
            r = pearson(x, y)
            pct, p1 = shuffle_null_pct(x, y, r)
            r_raw = pearson(d[s].to_numpy(), d["fwd"].to_numpy())
            # 中位分桶
            if len(d) >= 4 and np.std(x) > 0:
                med = np.median(x)
                hi, lo = d[d[s] > med], d[d[s] <= med]
                hi_m, lo_m = hi.fwd_rel.mean() * 100, lo.fwd_rel.mean() * 100
                hi_w = (hi.fwd_rel > 0).mean() * 100
            else:
                hi_m = lo_m = hi_w = np.nan
            # 逐标的方向一致性
            signs = []
            for t in CORE:
                dt = d[d.ticker == t]
                rt = pearson(dt[s].to_numpy(), dt["fwd_rel"].to_numpy())
                if not np.isnan(rt):
                    signs.append(np.sign(rt))
            agree = (f"{int(sum(np.array(signs)==np.sign(r)))}/{len(signs)}"
                     if signs and not np.isnan(r) else "-")
            print(f"{s:18s} {len(d):3d} {r:7.3f} {pct:6.1f} {p1:6.3f} {r_raw:7.3f} | "
                  f"{hi_m:8.2f} {lo_m:8.2f} {hi_w:7.0f} {agree:>10s}")
            if N == 3 and s in GO_SET and not np.isnan(pct):
                monotonic = (not np.isnan(hi_m) and not np.isnan(lo_m)
                             and ((hi_m > lo_m) == (r > 0)))
                a_ok = signs and (sum(np.array(signs) == np.sign(r)) >= 3)
                if pct >= 95 and a_ok and monotonic:
                    go_hits.append(s)

    # 稳健性：日内去均值（剔除「哪天」效应，只测「同一天里高信号名是否跑赢」）
    print(f"\n{'='*72}\n稳健性 · 日内去均值横截面（N=3, SPY 相对）—— 破解 day-clustering\n{'='*72}")
    print(f"{'signal':18s} {'n':>3s} {'days':>4s} {'r_within':>8s} {'null%':>6s} {'p1':>6s}")
    s3 = panel[panel.N == 3].copy()
    for s in GO_SET + ["engagement", "consensus_entropy"]:
        d = s3.dropna(subset=[s, "fwd_rel"]).copy()
        if d.day.nunique() < 2 or len(d) < 4:
            print(f"{s:18s} {len(d):3d} {d.day.nunique():4d}  (样本不足)")
            continue
        d["sig_dm"] = d.groupby("day")[s].transform(lambda v: v - v.mean())
        d["ret_dm"] = d.groupby("day")["fwd_rel"].transform(lambda v: v - v.mean())
        x, y = d["sig_dm"].to_numpy(), d["ret_dm"].to_numpy()
        r = pearson(x, y)
        # 日内置换零假设：只在同一天内打乱收益，保留 day-block 结构
        null = np.empty(N_SHUFFLE)
        idx_by_day = [g.index.to_numpy() for _, g in d.groupby("day")]
        yv = d["ret_dm"].to_numpy()
        pos = {ix: k for k, ix in enumerate(d.index)}
        for i in range(N_SHUFFLE):
            yp = yv.copy()
            for grp in idx_by_day:
                ks = [pos[ix] for ix in grp]
                yp[ks] = RNG.permutation(yp[ks])
            null[i] = abs(pearson(x, yp))
        pct = float((null < abs(r)).mean() * 100) if not np.isnan(r) else np.nan
        p1 = float((null >= abs(r)).mean()) if not np.isnan(r) else np.nan
        print(f"{s:18s} {len(d):3d} {d.day.nunique():4d} {r:8.3f} {pct:6.1f} {p1:6.3f}")

    # squeeze 分层
    print(f"\n{'='*72}\nsqueeze/meme 分层（N=3, raw_dir）\n{'='*72}")
    s3 = panel[panel.N == 3].dropna(subset=["raw_dir", "fwd_rel"])
    for flag, lab in [(1, "squeeze"), (0, "non-sq")]:
        g = s3[s3.squeeze_flag == flag]
        if len(g):
            print(f"  {lab:8s} n={len(g):3d}  raw_dir↔fwd_rel r={pearson(g.raw_dir.to_numpy(), g.fwd_rel.to_numpy()):.3f}  "
                  f"mean_fwd_rel={g.fwd_rel.mean()*100:+.2f}%")

    print(f"\n{'='*72}\n预注册判定\n{'='*72}")
    if go_hits:
        print(f"  ✅ GO —— 通过零假设+方向+单调的信号：{go_hits}")
    else:
        print("  ⛔ NO-GO / 不确定 —— 没有信号在 N=3 同时通过 (null≥95% & 方向≥3/5 & 单调)。")
        print("     解读：6 周 / Reddit-only / n 极小下，未见可移植的前向预测力；先别建滚动 regime 引擎。")
    print("\n（提醒：n 为单位数量级、4-5 只共动大盘科技股、UTC 日界、单次未校准 LLM 打标 —— 仅供产生假设。）")


if __name__ == "__main__":
    main()
