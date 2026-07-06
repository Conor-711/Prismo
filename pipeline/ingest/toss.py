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
import json
import re
import time

import requests
from sqlalchemy import select

from ..common.config import ROOT
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

# Toss 股票代码（页面 URL /stocks/<code>/community）→ 我们的 ticker。
TOSS_STOCKS: dict[str, str] = {
    "US19890516001": "MU",
    "US20200930014": "PLTR",
}
TOSS_CODES_PATH = ROOT / "data" / "exports" / "toss_codes.json"


def _load_stock_map() -> dict[str, str]:
    """Return Toss stockCode -> ticker, merging the repo-maintained export map."""
    out = dict(TOSS_STOCKS)
    if not TOSS_CODES_PATH.exists():
        return out
    try:
        rows = json.loads(TOSS_CODES_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return out
    if not isinstance(rows, dict):
        return out
    for ticker, code in rows.items():
        tk = str(ticker or "").strip().upper()
        cd = str(code or "").strip()
        if tk and cd:
            out[cd] = tk
    return out

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


def _comment_id(row_id: str) -> str | None:
    try:
        return str(row_id).rsplit(":", 1)[1]
    except IndexError:
        return None


def _existing_bounds(ticker: str, code: str) -> tuple[str, dt.datetime, dt.datetime] | None:
    """返回本地已有窗口的 (最旧 commentId, 最旧时间, 最新时间)，供 --resume 从旧游标续抓。"""
    stmt = select(GrPost.id, GrPost.created_utc).where(
        GrPost.source == "toss",
        GrPost.ticker == ticker,
        GrPost.board_code == code,
    )
    with session_scope() as s:
        oldest = s.execute(stmt.order_by(GrPost.created_utc.asc()).limit(1)).first()
        newest = s.execute(stmt.order_by(GrPost.created_utc.desc()).limit(1)).first()
    if not oldest or not newest:
        return None
    cid = _comment_id(oldest[0])
    if not cid:
        return None
    return cid, oldest[1], newest[1]


def _crawl_loop(
    *,
    sess: requests.Session,
    dbs,
    ticker: str,
    code: str,
    cutoff: dt.datetime,
    max_pages: int,
    sleep: float,
    commit_pages: int,
    start_cursor: str | None = None,
    stop_before: dt.datetime | None = None,
    phase: str = "",
) -> dict:
    cursor = start_cursor
    got = pages = 0
    oldest = newest = None
    hit_cutoff = hit_overlap = False
    label = f"{ticker}{' ' + phase if phase else ''}"
    while pages < max_pages:
        params = {"subjectType": "STOCK", "subjectId": code, "commentSortType": "RECENT"}
        if cursor is not None:
            params["lastCommentId"] = cursor
        data = _get(sess, params)
        if not data:
            print(f"[toss] {label} 第 {pages+1} 页请求失败，停止。", flush=True)
            break
        res = (data.get("result") or {})
        rows = res.get("results") or []
        if not rows:
            break
        stop = False
        for c in rows:
            created = _parse_ts(c.get("createdAt") or "")
            newest = newest or created
            oldest = created
            if stop_before is not None and created < stop_before:
                hit_overlap = True
                stop = True
                break
            if created < cutoff:
                hit_cutoff = True
                stop = True
                break
            if _upsert(dbs, ticker=ticker, code=code, c=c, created=created):
                got += 1
        pages += 1
        if commit_pages > 0 and pages % commit_pages == 0:
            dbs.commit()
        if pages % 20 == 0:
            oldest_s = oldest.strftime("%Y-%m-%d %H:%M") if oldest else "—"
            print(f"[toss] {label} … {pages} 页 / merge {got} 条 / 最早 {oldest_s} UTC", flush=True)
        if stop or not res.get("hasNext"):
            break
        cursor = res.get("key")
        if cursor is None:
            break
        if sleep > 0:
            time.sleep(sleep)
    return {
        "got": got,
        "pages": pages,
        "oldest": oldest,
        "newest": newest,
        "hit_cutoff": hit_cutoff,
        "hit_overlap": hit_overlap,
    }


def crawl_stock(code: str, ticker: str, *, days: int = 14, max_pages: int = 1500,
                sleep: float = 0.3, commit_pages: int = 100, resume: bool = False) -> int:
    """游标翻页爬 RECENT 评论，直到早于 days 窗口或没有下一页。返回入库条数。"""
    cutoff = dt.datetime.utcnow() - dt.timedelta(days=days)
    sess = _session()
    with session_scope() as s:
        total_got = total_pages = 0
        oldest = None
        hit_cutoff = False
        bounds = _existing_bounds(ticker, code) if resume else None
        if bounds:
            oldest_cursor, local_oldest, local_newest = bounds
            print(
                f"[toss] {ticker} resume：本地已有 {local_oldest:%Y-%m-%d %H:%M} → "
                f"{local_newest:%Y-%m-%d %H:%M} UTC；先补新，再从 {oldest_cursor} 补旧。",
                flush=True,
            )
            head = _crawl_loop(
                sess=sess, dbs=s, ticker=ticker, code=code, cutoff=cutoff, max_pages=max_pages,
                sleep=sleep, commit_pages=commit_pages, stop_before=local_newest, phase="补新"
            )
            total_got += head["got"]
            total_pages += head["pages"]
            if local_oldest > cutoff:
                tail = _crawl_loop(
                    sess=sess, dbs=s, ticker=ticker, code=code, cutoff=cutoff, max_pages=max_pages,
                    sleep=sleep, commit_pages=commit_pages, start_cursor=oldest_cursor, phase="补旧"
                )
                total_got += tail["got"]
                total_pages += tail["pages"]
                oldest = tail["oldest"] or local_oldest
                hit_cutoff = bool(tail["hit_cutoff"])
            else:
                oldest = local_oldest
                hit_cutoff = True
        else:
            res = _crawl_loop(
                sess=sess, dbs=s, ticker=ticker, code=code, cutoff=cutoff, max_pages=max_pages,
                sleep=sleep, commit_pages=commit_pages
            )
            total_got = res["got"]
            total_pages = res["pages"]
            oldest = res["oldest"]
            hit_cutoff = bool(res["hit_cutoff"])
    oldest_s = oldest.strftime("%Y-%m-%d %H:%M") if oldest else "—"
    suffix = f"窗口 {days}d，最早至 {oldest_s} UTC"
    if total_pages >= max_pages and not hit_cutoff:
        suffix = f"达到 max_pages={max_pages}，尚未触达 {days}d 截止；最早至 {oldest_s} UTC"
    print(f"[toss] {ticker} 完成：{total_pages} 页，merge {total_got} 条（{suffix}）。", flush=True)
    return total_got


def crawl(days: int = 14, only: list[str] | None = None, max_pages: int = 1500,
          sleep: float = 0.3, commit_pages: int = 100, resume: bool = False) -> int:
    """爬 TOSS_STOCKS 里所有（或 only 指定 ticker）股票的近 days 天社区评论 → gr_post。"""
    _ensure_tables()
    total = 0
    only_set = {t.strip().upper() for t in only or [] if t.strip()}
    for code, ticker in _load_stock_map().items():
        if only_set and ticker not in only_set:
            continue
        print(f"[toss] ▶ {ticker}（{code}）近 {days} 天 …", flush=True)
        total += crawl_stock(code, ticker, days=days, max_pages=max_pages, sleep=sleep,
                             commit_pages=commit_pages, resume=resume)
    print(f"[toss] 全部完成，共入库 {total} 条 → gr_post(source='toss')。下一步：make gr-tag → make retail-sentiment/-volume。", flush=True)
    return total


if __name__ == "__main__":
    crawl()
