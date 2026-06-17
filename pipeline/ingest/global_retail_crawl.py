"""全球散户多区看板——爬日(Yahoo JP)/韩(Naver)/台(PTT) 本土板对「精选跨区美股」的讨论。

与 us/cn Reddit 主管线、asia_* 4 标的实验**均隔离**，写独立表 gr_post：
  - 日本 jp：finance.yahoo.co.jp/quote/{SYMBOL}/forum（美股代码直连，已验证）。
  - 韩国 kr：m.stock.naver.com front-api discussion（foreignStock + reutersCode，如 NVDA.O）。
  - 台湾 tw：ptt.cc/bbs/Stock 综合板抓一遍，再用别名（繁中名/英文代码）从标题+正文**抽取**精选标的。
US 区不在此爬——其情绪/声量在 rollup 阶段直接读现有 Reddit TickerRollup（只读，不污染）。

复用 asia_crawl.py 里成熟的 fetch_yahoo_jp / fetch_naver_discussion / fetch_ptt_stock。
打标在 analyze/global_retail_tag.py（DeepSeek flash，不用千问）。
"""
from __future__ import annotations

import datetime as dt
import re

import yaml

from ..common.config import PKG_DATA_DIR
from ..common.db import session_scope
from ..common.models import Base, GrPost
from .asia_crawl import fetch_naver_discussion, fetch_ptt_stock, fetch_yahoo_jp


def load_targets() -> list[dict]:
    with open(PKG_DATA_DIR / "global_targets.yml", "r", encoding="utf-8") as f:
        return yaml.safe_load(f)["tickers"]


def _ensure_tables() -> None:
    from ..common.db import engine
    Base.metadata.create_all(engine, tables=[
        GrPost.__table__,
        Base.metadata.tables["gr_ticker_region"],
        Base.metadata.tables["gr_ticker"],
    ])


def _upsert(s, *, region: str, source: str, ticker: str, board_code: str, lang: str, rec: dict) -> None:
    pid = f"{region}:{source}:{ticker}:{rec['native_id']}"
    s.merge(GrPost(
        id=pid, region=region, source=source, ticker=ticker, board_code=board_code, lang=lang,
        author=(rec.get("author") or "—")[:120], title=rec.get("title", "") or "", body=rec.get("body", "") or "",
        label=rec.get("label"), url=rec.get("url", "") or "",
        likes=int(rec.get("likes", 0) or 0), dislikes=int(rec.get("dislikes", 0) or 0),
        views=int(rec.get("views", 0) or 0), comments=int(rec.get("comments", 0) or 0),
        images=int(rec.get("images", 0) or 0), verified=bool(rec.get("verified", False)),
        created_utc=rec.get("created_utc") or dt.datetime.utcnow(),
        fetched_at=dt.datetime.utcnow(),
    ))


# ----------------------------- 台湾 PTT：从综合板文本抽取精选标的 -----------------------------
def _build_matchers(targets: list[dict]) -> list[tuple[str, list[str], "re.Pattern | None"]]:
    """每标的 → (ticker, CJK别名子串列表, 拉丁词边界正则)。
    拉丁别名只用长度≥3 的（避免 F/BA 等过短代码误命中）；CJK 别名按子串精确命中。"""
    matchers = []
    for t in targets:
        cjk, latin = [], []
        for a in t.get("aliases", []):
            if any("一" <= c <= "鿿" for c in a):  # 含中日韩汉字 → 子串匹配
                cjk.append(a)
            elif len(a) >= 3:                                # 拉丁词，词边界匹配
                latin.append(re.escape(a))
        pat = re.compile(r"(?<![A-Za-z0-9])(?:%s)(?![A-Za-z0-9])" % "|".join(latin), re.I) if latin else None
        matchers.append((t["ticker"], cjk, pat))
    return matchers


def crawl_tw(targets: list[dict], since: dt.datetime, limit: int = 1000, body_top: int = 300) -> dict:
    """抓 PTT Stock 近窗口帖，从标题+正文抽取精选标的；每个 (帖,命中标的) 落一条 gr_post(region=tw)。"""
    # 深抓：max_pages 大幅调高（PTT 不删帖，index 往回翻），靠 since 停 → 回看满 30 天
    posts = fetch_ptt_stock(limit=max(limit, 9000), since=since, body_top=body_top, max_pages=500)
    matchers = _build_matchers(targets)
    stats: dict[str, int] = {}
    with session_scope() as s:
        for p in posts:
            text = f"{p.get('title','')}\n{p.get('body','')}"
            low = text.lower()
            for ticker, cjk, pat in matchers:
                hit = any(a in text for a in cjk) or (pat.search(text) is not None) if (cjk or pat) else False
                # 拉丁命中已在 pat 内大小写不敏感；CJK 子串用原文
                if not hit:
                    continue
                rec = dict(p)
                rec["native_id"] = p["native_id"]  # 同帖多标的 → id 含 ticker 区分
                _upsert(s, region="tw", source="ptt", ticker=ticker, board_code="Stock", lang="zh", rec=rec)
                stats[ticker] = stats.get(ticker, 0) + 1
    tot = sum(stats.values())
    top = sorted(stats.items(), key=lambda x: -x[1])[:8]
    print(f"  [tw] PTT {len(posts)} 帖 → 抽取 {tot} 条(命中 {len(stats)} 标的)；Top: {top}")
    return {"tw_posts": len(posts), "tw_extracted": tot, "tw_tickers": len(stats)}


# ----------------------------- 主流程 -----------------------------
def crawl(per_board: int = 120, since_days: int = 14, regions: set[str] | None = None,
          only: list[str] | None = None) -> dict:
    """爬日韩台三区。US 不在此（rollup 读现有 Reddit）。only 给定时仅爬这些 ticker（调试）。"""
    _ensure_tables()
    targets = load_targets()
    if only:
        targets = [t for t in targets if t["ticker"] in set(only)]
    since = dt.datetime.utcnow() - dt.timedelta(days=since_days)
    print(f"[gr-crawl] {len(targets)} 标的 · 近 {since_days} 天(≥{since:%Y-%m-%d}) · 区={regions or 'jp,kr,tw'}")
    stats = {"jp": 0, "kr": 0, "tw_extracted": 0, "tw_posts": 0, "tw_tickers": 0}

    # 日本 + 韩国：逐标的的本土板
    with session_scope() as s:
        for t in targets:
            tk = t["ticker"]
            if (not regions or "jp" in regions) and t.get("yahoo_jp"):
                recs = fetch_yahoo_jp(t["yahoo_jp"], per_board, since=since)
                for rec in recs:
                    _upsert(s, region="jp", source="yahoo_jp", ticker=tk, board_code=t["yahoo_jp"], lang="ja", rec=rec)
                stats["jp"] += len(recs)
                if recs:
                    print(f"  [jp] {tk}: {len(recs)}")
            if (not regions or "kr" in regions) and t.get("naver_code"):
                # 深抓：max_pages 调高，靠 since(30天) 做停止条件 → 拿满窗口内全部主帖（offset 游标分页）
                recs = fetch_naver_discussion(t.get("naver_type", "foreignStock"), str(t["naver_code"]),
                                              per_board, since=since, max_pages=150)
                for rec in recs:
                    _upsert(s, region="kr", source="naver", ticker=tk, board_code=str(t["naver_code"]), lang="ko", rec=rec)
                stats["kr"] += len(recs)
                if recs:
                    print(f"  [kr] {tk}: {len(recs)}")

    # 台湾：综合板抽取
    if not regions or "tw" in regions:
        stats.update(crawl_tw(targets, since))

    print(f"[gr-crawl] 完成 {stats}")
    return stats


if __name__ == "__main__":
    crawl()
