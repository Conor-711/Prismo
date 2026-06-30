"""Toss(토스증권) 종목 커뮤니티 爬取 → 隔离表 gr_post（source='toss', region='kr'）。

韩国散户除 Naver 外的另一大票仓——Toss Securities(tossinvest.com) 的股票社区评论。
逆向其 Web 前端 API（无需登录，浏览器头即可）：

  GET https://wts-cert-api.tossinvest.com/api/v4/comments
      ?subjectType=STOCK&subjectId={stockCode}&commentSortType=RECENT[&lastCommentId={cursor}]

  响应：{"result": {"results": [ ...评论... ], "key": <游标>, "hasNext": bool, "totalCount": int}}
  每页固定 11 条（无 size 参数）；游标分页 = 把上一页的 `key` 作为下一页的 `lastCommentId`。
  RECENT 排序（新→旧）→ 一旦遇到早于时间窗的评论即可停（其后全更早）。

每条顶层评论(parentId=null) = 一条 gr_post（与 Naver/Yahoo JP/PTT 同隔离表）。落库后照常
`make gr-tag`(打情绪) → `make retail-sentiment`/`make retail-volume`(进散户 rollup 的 toss 列)。

stockCode 即页面 URL 里那段（如 Palantir = US20200930014）；映射到我们的 ticker 见 TOSS_STOCKS。
"""
from __future__ import annotations

import datetime as dt
import re
import time

import requests

from ..common.db import session_scope
from ..common.models import Base, GrPost

API = "https://wts-cert-api.tossinvest.com/api/v4/comments"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
HEADERS = {
    "User-Agent": UA,
    "Accept": "application/json",
    "Referer": "https://www.tossinvest.com/",
    "Origin": "https://www.tossinvest.com",
}

# Toss 股票代码（页面 URL /stocks/<code>/community）→ 我们的 ticker。先 Palantir；后续扩展即可。
TOSS_STOCKS: dict[str, str] = {
    "US20200930014": "PLTR",
}

_ISO = re.compile(r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([+-]\d{2}:\d{2}|Z)?")


def _parse_ts(s: str) -> dt.datetime:
    """Toss createdAt 形如 '2026-06-28T14:11:59.845955523+09:00'（纳秒精度 + 时区）→ naive UTC。"""
    if not s:
        return dt.datetime.utcnow()
    m = _ISO.match(s)
    if not m:
        return dt.datetime.utcnow()
    Y, Mo, D, h, mi, se, frac, tz = m.groups()
    base = dt.datetime(int(Y), int(Mo), int(D), int(h), int(mi), int(se))
    if frac:
        base = base.replace(microsecond=int(frac[:6].ljust(6, "0")))
    if tz and tz != "Z":
        sign = 1 if tz[0] == "+" else -1
        oh, om = int(tz[1:3]), int(tz[4:6])
        base = base - sign * dt.timedelta(hours=oh, minutes=om)  # → UTC
    return base


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update(HEADERS)
    return s


def _get(sess: requests.Session, params: dict, tries: int = 3, timeout: int = 20):
    for i in range(tries):
        try:
            r = sess.get(API, params=params, timeout=timeout)
            if r.status_code == 200:
                return r.json()
            # 429/5xx → 退避重试
            time.sleep(1.5 * (i + 1))
        except requests.RequestException:
            time.sleep(1.5 * (i + 1))
    return None


def _ensure_tables() -> None:
    from ..common.db import engine
    Base.metadata.create_all(engine, tables=[GrPost.__table__])


def _upsert(s, *, ticker: str, code: str, c: dict, created: dt.datetime) -> bool:
    msg = (c.get("message") or {})
    title = (msg.get("title") or "").strip()
    body = (msg.get("message") or "").strip()
    if not title and not body:
        return False  # 纯图片/空文本帖 → 跳过（情绪/讨论无意义）
    cid = c.get("commentId")
    if cid is None:
        return False
    stat = (c.get("statistic") or {})
    author = ((c.get("author") or {}).get("nickname") or "—")[:120]
    s.merge(GrPost(
        id=f"kr:toss:{ticker}:{cid}", region="kr", source="toss", ticker=ticker,
        board_code=code, lang="ko", author=author, title=title, body=body,
        url=f"https://www.tossinvest.com/community/posts/{cid}",
        likes=int(stat.get("likeCount", 0) or 0),
        comments=int(stat.get("replyCount", 0) or 0),
        views=int(stat.get("readCount", 0) or 0),
        verified=bool((c.get("author") or {}).get("type") == "USER" and stat.get("followerCount", 0)),
        created_utc=created, fetched_at=dt.datetime.utcnow(),
    ))
    return True


def crawl_stock(code: str, ticker: str, *, days: int = 14, max_pages: int = 1500,
                sleep: float = 0.3) -> int:
    """游标翻页爬 RECENT 评论，直到早于 days 窗口或没有下一页。返回入库条数。"""
    cutoff = dt.datetime.utcnow() - dt.timedelta(days=days)
    sess = _session()
    cursor = None
    got = pages = 0
    oldest = None
    with session_scope() as s:
        while pages < max_pages:
            params = {"subjectType": "STOCK", "subjectId": code, "commentSortType": "RECENT"}
            if cursor is not None:
                params["lastCommentId"] = cursor
            data = _get(sess, params)
            if not data:
                print(f"[toss] {ticker} 第 {pages+1} 页请求失败，停止。", flush=True)
                break
            res = (data.get("result") or {})
            rows = res.get("results") or []
            if not rows:
                break
            stop = False
            for c in rows:
                created = _parse_ts(c.get("createdAt") or "")
                oldest = created
                if created < cutoff:
                    stop = True
                    break  # RECENT 排序：此后全更早
                if _upsert(s, ticker=ticker, code=code, c=c, created=created):
                    got += 1
            pages += 1
            if pages % 20 == 0:
                print(f"[toss] {ticker} … {pages} 页 / 入库 {got} 条 / 最早 {oldest:%Y-%m-%d %H:%M} UTC", flush=True)
            if stop or not res.get("hasNext"):
                break
            cursor = res.get("key")
            if cursor is None:
                break
            time.sleep(sleep)
    oldest_s = oldest.strftime("%Y-%m-%d %H:%M") if oldest else "—"
    print(f"[toss] {ticker} 完成：{pages} 页，入库 {got} 条（窗口 {days}d，最早至 {oldest_s} UTC）。", flush=True)
    return got


def crawl(days: int = 14, only: list[str] | None = None, max_pages: int = 1500) -> int:
    """爬 TOSS_STOCKS 里所有（或 only 指定 ticker）股票的近 days 天社区评论 → gr_post。"""
    _ensure_tables()
    total = 0
    for code, ticker in TOSS_STOCKS.items():
        if only and ticker not in only:
            continue
        print(f"[toss] ▶ {ticker}（{code}）近 {days} 天 …", flush=True)
        total += crawl_stock(code, ticker, days=days, max_pages=max_pages)
    print(f"[toss] 全部完成，共入库 {total} 条 → gr_post(source='toss')。下一步：make gr-tag → make retail-sentiment/-volume。", flush=True)
    return total


if __name__ == "__main__":
    crawl()
