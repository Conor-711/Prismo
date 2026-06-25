"""推文 ↔ 标的 硬匹配（关键词，无 AI）。

读取 vertical_topic_metadata.json（每个 topic 一组 keyword_list，含 $cashtag / @handle /
#hashtag / 多词短语 / 单词），对 tw_tweet 全量做混合硬匹配，结果写入 tw_tweet_topic。

匹配语义（faithful，不做语义/AI）：
  - 大小写不敏感；卷曲撇号 ’ 归一为 '；Unicode 分词（韩日中字符算词字符）。
  - **带 sigil 的关键词只匹配同 sigil 的 token**：$nvda 只命中文本里的 "$nvda"，不命中裸 "nvda"
    （这正是该文件用 cashtag 给股票消歧的用意，避免 3 字母裸词误伤）。
  - 多词短语按「连续 token 完全相等」命中（短语与推文用同一分词器，标点处理一致）。
  - **strong 标记**：命中方式为 cashtag/handle/hashtag/phrase，或 word 且关键词 ≥3 字符 → strong=true；
    仅靠 ≤2 字符裸词（ai/hp/3m/o1…）命中 → strong=false。两类都入库，下游可只取 strong。

每条 (tweet_id, topic_id) 落一行，带命中方式集合、命中关键词数、strong 标记。幂等：整表重算。
"""
from __future__ import annotations

import json
import re
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

from sqlalchemy import (
    Boolean, Column, DateTime, Integer, MetaData, String, Table, Text,
    create_engine, func, insert, text,
)

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from pipeline.common.config import normalize_db_url, settings  # noqa: E402

META_PATH = Path(__file__).resolve().parents[2] / "vertical_topic_metadata.json"

_TOKEN_RE = re.compile(r"[$@#]?\w[\w']*", re.UNICODE)


def _norm(s: str) -> str:
    return s.replace("’", "'").replace("‘", "'").lower()


def tokenize(s: str) -> list[str]:
    return _TOKEN_RE.findall(_norm(s))


def _unquote(k: str) -> str:
    k = k.strip()
    if len(k) >= 2 and k[0] == '"' and k[-1] == '"':
        k = k[1:-1]
    return k.strip()


def _method(tok: str) -> str:
    if tok.startswith("$"):
        return "cashtag"
    if tok.startswith("@"):
        return "handle"
    if tok.startswith("#"):
        return "hashtag"
    return "word"


class Index:
    """单 token 索引 + 多词短语索引。topic 用整数下标，旁存元数据。"""

    def __init__(self):
        self.topics: list[tuple[str, str, str]] = []  # (topic_id, symbol, vertical)
        # token -> list[(topic_idx, method, strong, keyword_display)]
        self.single: dict[str, list[tuple]] = defaultdict(list)
        # first_token -> list[(tuple_tokens, topic_idx, keyword_display)]
        self.phrase: dict[str, list[tuple]] = defaultdict(list)
        self.n_kw = 0
        self.n_skipped = 0

    def add_topic(self, topic_id: str, symbol: str, vertical: str, keywords: list[str]):
        ti = len(self.topics)
        self.topics.append((topic_id, symbol, vertical))
        seen: set[str] = set()
        for raw in keywords:
            kw = _unquote(raw)
            if not kw:
                self.n_skipped += 1
                continue
            toks = tokenize(kw)
            if not toks:
                self.n_skipped += 1
                continue
            disp = kw
            if len(toks) == 1:
                tok = toks[0]
                if tok in seen:
                    continue
                seen.add(tok)
                meth = _method(tok)
                strong = meth != "word" or len(tok) >= 3
                self.single[tok].append((ti, meth, strong, disp))
            else:
                key = tuple(toks)
                if ("P", key) in seen:
                    continue
                seen.add(("P", key))
                self.phrase[toks[0]].append((tuple(toks), ti, disp))
            self.n_kw += 1


def load_index(path: Path = META_PATH) -> Index:
    data = json.load(open(path, encoding="utf-8"))
    # 按 topic_id 去重合并（文件里有重复 topic_id，如 AI_ENTITY_Replit 出现两次）：
    # 合并它们的 keyword_list，避免同一 (tweet,topic) 产生重复行（PK 冲突）。
    merged: dict[str, dict] = {}
    order: list[str] = []
    for t in data:
        tid = t.get("topic_id") or t.get("symbol") or ""
        if not tid:
            continue
        if tid not in merged:
            merged[tid] = {"symbol": t.get("symbol") or "",
                           "vertical": t.get("vertical") or "",
                           "kws": list(t.get("keyword_list") or [])}
            order.append(tid)
        else:
            merged[tid]["kws"].extend(t.get("keyword_list") or [])
    idx = Index()
    for tid in order:
        m = merged[tid]
        idx.add_topic(tid, m["symbol"], m["vertical"], m["kws"])
    return idx


def match_tweet(txt: str, idx: Index, kw_counter: Counter | None = None):
    """返回 {topic_idx: (methods:set, kw_set:set, strong:bool)}。"""
    toks = tokenize(txt)
    if not toks:
        return {}
    tset = set(toks)
    acc: dict[int, list] = {}

    def bump(ti, meth, strong, disp):
        e = acc.get(ti)
        if e is None:
            acc[ti] = [{meth}, {disp}, strong]
        else:
            e[0].add(meth)
            e[1].add(disp)
            e[2] = e[2] or strong
        if kw_counter is not None:
            kw_counter[disp] += 1

    # 单 token
    for tok in tset:
        hits = idx.single.get(tok)
        if hits:
            for ti, meth, strong, disp in hits:
                bump(ti, meth, strong, disp)
    # 多词短语
    n = len(toks)
    for i, tok in enumerate(toks):
        cands = idx.phrase.get(tok)
        if not cands:
            continue
        for ptoks, ti, disp in cands:
            L = len(ptoks)
            if i + L <= n and tuple(toks[i:i + L]) == ptoks:
                bump(ti, "phrase", True, disp)
    return acc


# ---------------------------------------------------------------- DB 部分
_md = MetaData()
tw_tweet_topic = Table(
    "tw_tweet_topic", _md,
    Column("tweet_id", String(40), primary_key=True),
    Column("topic_id", String(96), primary_key=True),
    Column("symbol", String(32)),
    Column("vertical", String(32)),
    Column("methods", String(64)),
    Column("kw_count", Integer),
    Column("strong", Boolean),
    Column("matched_at", DateTime(timezone=True), server_default=func.now()),
)


def _engine():
    url = normalize_db_url(settings.database_url or "")
    if not url.startswith("postgresql"):
        raise SystemExit("DATABASE_URL 需指向 Supabase(Postgres)。当前非 postgres。")
    return create_engine(url, connect_args={"prepare_threshold": None}, pool_pre_ping=True)


def run(page: int = 20000, batch: int = 8000):
    idx = load_index()
    print(f"[match] 载入 {len(idx.topics)} topics · 有效关键词 {idx.n_kw}"
          f"（单词索引 {len(idx.single)} / 短语首词 {len(idx.phrase)}；跳过空 {idx.n_skipped}）", flush=True)
    eng = _engine()
    # 建表 + 清空（整表重算，幂等）
    with eng.begin() as c:
        tw_tweet_topic.create(c, checkfirst=True)
        c.execute(text("TRUNCATE tw_tweet_topic"))
        total = c.execute(text("select count(*) from tw_tweet where text is not null")).scalar()
    print(f"[match] 待匹配推文 {total:,}", flush=True)

    kw_counter: Counter = Counter()
    topic_tweet = Counter()  # topic_id -> 命中推文数
    strong_pairs = 0
    last_id = ""
    seen_tweets = 0
    t0 = time.time()
    # 先全量匹配进内存（~14万行很小），再一次性 COPY 写入：避免把 COPY 语句开 6 分钟被
    # Supabase 的 statement_timeout 杀掉（之前的报错原因）。
    out_rows: list[tuple] = []
    read = eng.connect()
    while True:
        rows = read.execute(text(
            "select tweet_id, text from tw_tweet "
            "where text is not null and tweet_id > :last "
            "order by tweet_id limit :lim"), {"last": last_id, "lim": page}).all()
        if not rows:
            break
        for tweet_id, txt in rows:
            last_id = tweet_id
            seen_tweets += 1
            acc = match_tweet(txt or "", idx, kw_counter)
            for ti, (methods, kws, strong) in acc.items():
                topic_id, symbol, vertical = idx.topics[ti]
                out_rows.append((tweet_id, topic_id, symbol, vertical,
                                 ",".join(sorted(methods)), len(kws), strong))
                topic_tweet[topic_id] += 1
                if strong:
                    strong_pairs += 1
        print(f"  …{seen_tweets:,}/{total:,}  pairs={len(out_rows):,}  "
              f"{seen_tweets/max(1e-9,time.time()-t0):.0f} tw/s", flush=True)
    read.close()

    print(f"[match] 匹配完成 {seen_tweets:,} 推文 → {len(out_rows):,} 对，开始 COPY 写入…", flush=True)
    raw = eng.raw_connection()  # 原生 psycopg 连接走 COPY（快）
    try:
        cur = raw.cursor()
        cur.execute("SET statement_timeout = '600s'")
        copy_sql = ("COPY tw_tweet_topic "
                    "(tweet_id, topic_id, symbol, vertical, methods, kw_count, strong) FROM STDIN")
        with cur.copy(copy_sql) as cp:
            for r in out_rows:
                cp.write_row(r)
        raw.commit()
    finally:
        raw.close()

    total_pairs = topic_tweet.total()
    print(f"\n[match] 完成：{seen_tweets:,} 推文 → {total_pairs:,} (推文,标的) 对，"
          f"其中 strong {strong_pairs:,}（{100*strong_pairs/max(1,total_pairs):.1f}%）。耗时 {time.time()-t0:.0f}s")
    # 报告：命中标的数、Top 噪音关键词
    with eng.connect() as c:
        tw_with = c.execute(text("select count(distinct tweet_id) from tw_tweet_topic")).scalar()
        tw_strong = c.execute(text("select count(distinct tweet_id) from tw_tweet_topic where strong")).scalar()
    print(f"[match] 被匹配到 ≥1 标的的推文：{tw_with:,}（strong：{tw_strong:,}）"
          f" / 全部 {total:,}（{100*tw_with/max(1,total):.1f}% / {100*tw_strong/max(1,total):.1f}%）")
    print(f"[match] 命中标的数：{len(topic_tweet):,}")
    print("[match] Top20 标的（按命中推文数）：")
    for tid, n in topic_tweet.most_common(20):
        print(f"    {tid:32s} {n:>8,}")
    print("[match] Top25 高频关键词（核对误报；注意裸短词）：")
    for kw, n in kw_counter.most_common(25):
        print(f"    {kw[:28]:30s} {n:>8,}")


if __name__ == "__main__":
    run()
