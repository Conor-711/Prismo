"""亚洲散户舆情实验爬虫：日本(Yahoo Finance JP) + 韩国(Naver) 本土社区。

爬 NVIDIA / Micron / SK 海力士 三标的在日韩本土散户板的讨论，写入隔离表 asia_posts
（不污染 Reddit 主管线）。沙箱出口 IP 可达这两站（不像 Reddit 被直连屏蔽）。

三个数据通道（见 pipeline/data/asia_targets.yml）：
  - yahoo_jp     : finance.yahoo.co.jp/quote/{CODE}/forum —— 服务端渲染 HTML，直接解析（NVDA/MU）。
  - naver_kr     : finance.naver.com/item/board.naver?code={6位} —— 经典种子讨论板(종목토론방)，SSR（海力士 000660）。
  - naver_world  : apis.naver.com cbox 评论（ticket=finance&pool=cbox12）—— 海外股(NVDA.O/MU.O)，
                   需 objectId（Chrome 抓一次填入 asia_targets.yml 的 naver_object_id 即激活）。

无本土板的缺口格（如 JP-海力士）与抓取失败时，从 pipeline/data/asia_samples.json 取清晰标注的
样本（origin='sample'）兜底，保证页面网格完整、AI 全流程可演示——绝不冒充真实抓取。
"""
from __future__ import annotations

import datetime as dt
import html as _html
import json
import re
import time

import requests
import yaml

from ..common.config import PKG_DATA_DIR
from ..common.db import session_scope
from ..common.models import AsiaPost, Base

UA_MOBILE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
UA_PC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

YAHOO_FORUM = "https://finance.yahoo.co.jp/quote/{code}/forum"
YAHOO_OLD_ORIGIN = "https://finance.yahoo.co.jp"
YAHOO_COMMENT_LIST = "https://finance.yahoo.co.jp/cm/ds/comment/listview"
# Naver 移动端讨论 front-api：海外股(foreignStock)/国内股(domesticStock)统一接口，返回完整正文。
NAVER_FRONT = "https://m.stock.naver.com/front-api/discussion/list"
NAVER_CCOUNT = "https://m.stock.naver.com/front-api/discussion/comment/counts"  # 每帖评论数
NAVER_WEB = {"foreignStock": "https://m.stock.naver.com/worldstock/stock/{code}/discussion",
             "domesticStock": "https://m.stock.naver.com/domestic/stock/{code}/discussion"}

# 日本/韩国均为 UTC+9（JST/KST）。
TZ_OFFSET = dt.timedelta(hours=9)


# ----------------------------- 工具 -----------------------------
def load_targets() -> list[dict]:
    with open(PKG_DATA_DIR / "asia_targets.yml", "r", encoding="utf-8") as f:
        return yaml.safe_load(f)["tickers"]


def _clean(html_fragment: str) -> str:
    """去标签 + 反转义 + 规整空白；<br> → 换行。"""
    s = re.sub(r"<br\s*/?>", "\n", html_fragment, flags=re.I)
    s = re.sub(r"<[^>]+>", " ", s)
    s = _html.unescape(s)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\n\s*\n+", "\n", s)
    return s.strip()


def _to_utc(local: dt.datetime) -> dt.datetime:
    return local - TZ_OFFSET


def _parse_jp_date(s: str) -> dt.datetime:
    """'2026/6/14 7:52' / '7月3日 11:21'（JST）→ UTC；缺年份按当年。"""
    s = s.strip()
    m = re.search(r"(?:(\d{4})/)?(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})", s)
    if m:
        y = int(m.group(1)) if m.group(1) else dt.datetime.utcnow().year
        return _to_utc(dt.datetime(y, int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))))
    m = re.search(r"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日\s+(\d{1,2}):(\d{2})", s)
    if m:
        y = int(m.group(1)) if m.group(1) else dt.datetime.utcnow().year
        return _to_utc(dt.datetime(y, int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))))
    return dt.datetime.utcnow()


def _session(ua: str) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": ua, "Accept-Language": "ja,en;q=0.8,ko;q=0.6"})
    return s


def _get(sess: requests.Session, url: str, *, params: dict | None = None,
         tries: int = 3, timeout: int = 30) -> requests.Response | None:
    """带退避重试的 GET（应对偶发 SSL EOF / 连接重置）。"""
    last = ""
    for i in range(tries):
        try:
            r = sess.get(url, params=params, timeout=timeout)
            if r.status_code == 200:
                return r
            last = f"HTTP {r.status_code}"
            if r.status_code in (403, 404):
                break  # 不重试
        except requests.RequestException as e:
            last = str(e)[:80]
        time.sleep(0.8 * (i + 1))
    print(f"  [get] {url.split('?')[0]} 失败：{last}")
    return None


# ----------------------------- 日本：Yahoo Finance JP 掲示板 -----------------------------
_JP_LABELS = ("強く買いたい", "買いたい", "様子見", "売りたい", "強く売りたい")


def _discover_yahoo_old_thread(symbol: str) -> tuple[str, str, str, str] | None:
    """从新版 quote/{symbol}/forum 发现旧掲示板入口。

    新页面只稳定暴露最近一屏；旧页面带 thread/part 与 AJAX listview，能补齐 14 天历史。
    返回 (category, thread, base_url, thread_name)。
    """
    r = _get(_session(UA_PC), YAHOO_FORUM.format(code=symbol))
    if r is None:
        return None
    m = re.search(r'href="https://finance\.yahoo\.co\.jp/cm/message/(\d+)/([a-z0-9]+)"', r.text)
    if not m:
        return None
    category, thread = m.group(1), m.group(2)
    name = _html.unescape(_first(r"<h1[^>]*>(.*?)</h1>", r.text) or f"{symbol} 掲示板")
    return category, thread, f"{YAHOO_OLD_ORIGIN}/cm/message/{category}/{thread}", _clean(name)


def _split_old_comment_blocks(html: str) -> list[tuple[str, str]]:
    """旧掲示板 HTML/listview fragment → [(display_no, block)]."""
    starts = list(re.finditer(r'<li\s+[^>]*id="c(\d+)"[^>]*data-comment="\d+"[^>]*>', html))
    out: list[tuple[str, str]] = []
    for i, m in enumerate(starts):
        end = starts[i + 1].start() if i + 1 < len(starts) else len(html)
        out.append((m.group(1), html[m.start():end]))
    return out


def _parse_yahoo_old_comments(symbol: str, html: str) -> list[dict]:
    recs: list[dict] = []
    for display_no, block in _split_old_comment_blocks(html):
        cid = _first(r'<div class="comment" data-comment="(\d+)"', block) or display_no
        body_m = re.search(r'<p class="comText">(.*?)</p>', block, re.S)
        body = _clean(body_m.group(1)) if body_m else ""
        if not body:
            continue
        author_html = _first(r'<p class="comWriter">(.*?)</p>', block, flags=re.S)
        author = _clean(re.sub(r"<span>.*?</span>", "", author_html, flags=re.S)) if author_html else "—"
        date_text = _first(r'rel="nofollow">([\s\S]*?\d{1,2}:\d{2})\s*</a>', block)
        created = _parse_jp_date(date_text)
        label = next((x for x in _JP_LABELS if x in block), None)
        likes = _first(r'class="positive"[\s\S]*?<span>(\d+)</span>', block, flags=re.S)
        dislikes = _first(r'class="negative"[\s\S]*?<span>(\d+)</span>', block, flags=re.S)
        recs.append({
            "native_id": cid,
            "author": author or "—",
            "title": "",
            "body": body,
            "label": label,
            "url": f"{YAHOO_OLD_ORIGIN}/quote/{symbol}/forum/{cid}",
            "likes": int(likes) if likes else 0,
            "dislikes": int(dislikes) if dislikes else 0,
            "images": len(re.findall(r"<img\b", block, re.I)),
            "views": 0,
            "comments": 0,
            "verified": False,
            "created_utc": created,
            "_display_no": int(display_no),
        })
    return recs


def _fetch_yahoo_old_part(sess: requests.Session, *, base_url: str, category: str, thread: str,
                          part: int, thread_name: str, symbol: str, limit: int,
                          since: dt.datetime | None) -> tuple[list[dict], bool]:
    """抓一个旧 part；返回 (records, should_continue_older_parts)。"""
    page_url = f"{base_url}/{part}"
    r = _get(sess, page_url)
    if r is None:
        return [], False
    out: list[dict] = []
    page = 1
    html = r.text
    while True:
        recs = _parse_yahoo_old_comments(symbol, html)
        if recs:
            out.extend(recs)
        if len(out) >= limit:
            return out[:limit], True
        if since and recs and min(x["created_utc"] for x in recs) < since:
            return out, False
        if not recs:
            return out, False
        last_no = min(int(x["_display_no"]) for x in recs)
        if last_no <= 1:
            return out, True
        page += 1
        sess.headers.update({"Referer": page_url, "X-Requested-With": "XMLHttpRequest"})
        params = {
            "category": category,
            "thread": thread,
            "part": str(part),
            "thread_feel_type": "1",
            "thread_stop_flag": "false",
            "tieup_name": "finance",
            "thread_name": thread_name,
            "offset": str(last_no - 1),
            "page": str(page),
        }
        rr = _get(sess, YAHOO_COMMENT_LIST, params=params, timeout=25)
        if rr is None:
            return out, True
        try:
            html = rr.json().get("feed", {}).get("content", "")
        except ValueError:
            return out, True
        if not html.strip():
            return out, True


def _fetch_yahoo_old(symbol: str, limit: int, since: dt.datetime | None) -> list[dict]:
    found = _discover_yahoo_old_thread(symbol)
    if not found:
        return []
    category, thread, base_url, thread_name = found
    sess = _session(UA_PC)
    first = _get(sess, base_url)
    if first is None:
        return []
    part_s = _first(r'data-part="(\d+)"', first.text) or _first(r"/cm/message/%s/%s/(\d+)" % (category, thread), first.text)
    if not part_s:
        return []
    part = int(part_s)
    seen: set[str] = set()
    out: list[dict] = []
    for p in range(part, 0, -1):
        remain = max(0, limit - len(out))
        if remain <= 0:
            break
        recs, keep_older = _fetch_yahoo_old_part(
            sess, base_url=base_url, category=category, thread=thread, part=p,
            thread_name=thread_name, symbol=symbol, limit=remain, since=since,
        )
        for rec in recs:
            rec["url"] = f"{YAHOO_OLD_ORIGIN}/quote/{symbol}/forum/{rec['native_id']}"
            if since and rec["created_utc"] < since:
                continue
            if rec["native_id"] in seen:
                continue
            rec.pop("_display_no", None)
            seen.add(rec["native_id"])
            out.append(rec)
        if not keep_older:
            break
    out.sort(key=lambda x: x["created_utc"], reverse=True)
    return out[:limit]


def _fetch_yahoo_new(symbol: str, limit: int, since: dt.datetime | None) -> list[dict]:
    """新版 SSR 兜底：最近一屏，结构更稳定但历史覆盖有限。"""
    url = YAHOO_FORUM.format(code=symbol)
    r = _get(_session(UA_MOBILE), url)
    if r is None:
        return []
    html = r.text
    out: list[dict] = []
    for block in re.findall(r"<article\b[^>]*>(.*?)</article>", html, re.S):
        if "_BbsItem__body_" not in block:
            continue
        mid = re.search(r'href="(/quote/[^/]+/forum/(\d+))"[^>]*_BbsItem__commentNo_', block)
        if not mid:
            continue
        native_id = mid.group(2)
        body_m = re.search(r'_BbsItem__body_[^"]*">(.*?)</div>', block, re.S)
        body = _clean(body_m.group(1)) if body_m else ""
        if not body:
            continue
        created = _parse_jp_date(_first(r'_BbsItem__postDate_[^"]*">([^<]*)<', block))
        if since and created < since:
            continue
        author = _first(r'_BbsItem__userName_[^"]*">([^<]*)<', block)
        label = _first(r'_BbsItem__label_[^"]*">([^<]*)<', block) or None
        counts = re.findall(r'_ReactionButton__count_[^"]*">(\d+)<', block)
        out.append({
            "native_id": native_id,
            "author": author or "—",
            "title": "",
            "body": body,
            "label": label,
            "url": "https://finance.yahoo.co.jp" + mid.group(1),
            "likes": int(counts[0]) if len(counts) >= 1 else 0,
            "dislikes": int(counts[1]) if len(counts) >= 2 else 0,
            "images": len(re.findall(r"_BbsItem__image_", block)),
            "views": 0, "comments": 0, "verified": False,
            "created_utc": created,
        })
        if len(out) >= limit:
            break
    return out


def fetch_yahoo_jp(symbol: str, limit: int = 60, since: dt.datetime | None = None) -> list[dict]:
    """Yahoo JP 掲示板。

    先用旧掲示板 AJAX listview 补历史分页（可覆盖 14 天以上），失败时回退新版 SSR 最近一屏。
    """
    old = _fetch_yahoo_old(symbol, limit=limit, since=since)
    if old:
        return old
    return _fetch_yahoo_new(symbol, limit=limit, since=since)


# ----------------------------- 台湾：PTT Stock 板（综合股票讨论板） -----------------------------
PTT_BASE = "https://www.ptt.cc"
PTT_INDEX = "https://www.ptt.cc/bbs/Stock/index.html"
# 标题里的 [類別] 标签（[標的]/[請益]/[新聞]/[心得]/[閒聊]/[情報]/[標的] 等），当 label 维度。
_PTT_CAT = re.compile(r"^(?:Re:|Fw:)?\s*\[([^\]]{1,6})\]")


def _ptt_push(raw: str) -> int:
    raw = (raw or "").strip()
    if raw == "爆":
        return 100
    if raw.startswith("X"):  # 噓多于推（负向），记 0（仅作热度，不为负）
        return 0
    try:
        return int(raw)
    except ValueError:
        return 0


def fetch_ptt_stock(limit: int = 400, since: dt.datetime | None = None,
                    body_top: int = 40, max_pages: int = 40) -> list[dict]:
    """爬 PTT Stock 板近 since 起的帖。M.{epoch} 给精确发文时间(unix)，按窗口过滤、翻「上頁」往旧翻。
    先抓全窗口元数据(标题/作者/推文數)，再给热度 Top body_top 帖抓正文（控请求数）。"""
    sess = _session(UA_PC)
    out: list[dict] = []
    url = PTT_INDEX
    seen: set[str] = set()
    for pg in range(max_pages):
        r = _get(sess, url)
        if r is None:
            break
        page = r.text
        in_window = 0
        for ent in page.split('<div class="r-ent">')[1:]:
            mlink = re.search(r'href="(/bbs/Stock/(M\.(\d+)\.A\.[^."]+)\.html)"', ent)
            if not mlink:  # 已删除/无链接
                continue
            href, mid, epoch = mlink.group(1), mlink.group(2), int(mlink.group(3))
            if mid in seen:
                continue
            seen.add(mid)
            created = dt.datetime.utcfromtimestamp(epoch)
            if since and created < since:
                continue  # 窗口外（含置顶旧公告）→ 跳过，但不停翻页
            title_m = re.search(r'class="title">\s*<a[^>]*>(.*?)</a>', ent, re.S)
            if not title_m:
                continue
            title = _clean(title_m.group(1))
            author = _first(r'class="author">([^<]*)<', ent) or "—"
            nrec = re.search(r'class="nrec">(?:<span[^>]*>([^<]*)</span>)?', ent)
            push = _ptt_push(nrec.group(1) if nrec and nrec.group(1) else "")
            cat = _PTT_CAT.search(title)
            out.append({
                "native_id": mid, "author": author, "title": title, "body": title,
                "label": cat.group(1) if cat else None,  # [標的]/[請益]/[新聞]…
                "url": PTT_BASE + href, "likes": push, "dislikes": 0,
                "views": 0, "comments": push, "images": 0, "verified": False,
                "created_utc": created, "_href": href,
            })
            in_window += 1
            if len(out) >= limit:
                break
        if len(out) >= limit:
            break
        if in_window == 0 and pg > 0:  # 整页都在窗口外 → 翻到头了
            break
        nxt = re.search(r'href="(/bbs/Stock/index\d+\.html)">\s*&[lrasqou;]+\s*上頁', page)
        if not nxt:
            nxt = re.search(r'href="(/bbs/Stock/index\d+\.html)">[^<]*上頁', page)
        if not nxt:
            break
        url = PTT_BASE + nxt.group(1)
        time.sleep(0.5)

    # 给热度最高的帖抓正文（控请求数）
    out.sort(key=lambda x: x["likes"], reverse=True)
    for rec in out[:body_top]:
        rp = _get(sess, PTT_BASE + rec["_href"])
        if rp is None:
            continue
        bm = re.search(r'<div id="main-content"[^>]*>(.*?)(?:<span class="f2">※ 發信站|<div class="push">)', rp.text, re.S)
        if bm:
            # 去掉 作者/看板/標題/時間 的 metaline 行，只留正文
            content = re.sub(r'<div class="article-metaline[^"]*">.*?</div>', "", bm.group(1), flags=re.S)
            body = _clean(content)
            if len(body) > 12:
                rec["body"] = body[:1500]
        time.sleep(0.3)
    for rec in out:
        rec.pop("_href", None)
    return out


# ----------------------------- 韩国：Naver 移动端讨论 front-api（国内/海外统一） -----------------------------
def fetch_naver_discussion(discussion_type: str, item_code: str, limit: int = 60,
                           since: dt.datetime | None = None, max_pages: int = 12) -> list[dict]:
    """Naver 移动端 discussion/list：domesticStock(000660) / foreignStock(NVDA.O/SPCX.O)。
    返回**完整正文** + 推荐/浏览数；按时间倒序分页（offset=-{上一页末贴 id}）。
    since 给定时翻页直到遇到窗口外旧帖即停（拿满一周）。"""
    sess = _session(UA_MOBILE)
    sess.headers["Referer"] = NAVER_WEB.get(discussion_type, "https://m.stock.naver.com/").format(code=item_code)
    out: list[dict] = []
    seen: set[str] = set()
    offset: str | None = None
    web = NAVER_WEB.get(discussion_type, "").format(code=item_code) if discussion_type in NAVER_WEB else ""
    reached_old = False
    capped = False
    for _ in range(max_pages):
        params = {
            "discussionType": discussion_type, "itemCode": item_code, "pageSize": 50,
            "isHolderOnly": "false", "excludesItemNews": "true", "isItemNewsOnly": "false",
        }
        if offset:
            params["offset"] = offset
        r = _get(sess, NAVER_FRONT, params=params, timeout=25)
        if r is None:
            break
        try:
            result = r.json().get("result", {})
        except ValueError:
            break
        posts = result.get("posts") or result.get("list") if isinstance(result, dict) else result
        if not posts and isinstance(result, dict):  # 兜底：取 result 里第一个对象数组
            posts = next((v for v in result.values() if isinstance(v, list) and v), [])
        if not posts:
            break
        last_id = None
        for p in posts:
            pid = str(p.get("id") or "")
            if pid:
                last_id = pid
            if not pid or pid in seen:
                continue
            seen.add(pid)
            if p.get("postType") not in (None, "normal"):  # 跳过新闻/公告
                continue
            if p.get("replyDepth") or p.get("parentId"):  # 只取主帖，跳过回复
                continue
            title = (p.get("title") or "").strip()
            body = _clean(p.get("contentSwReplaced") or p.get("contentSwReplacedButImg") or "")
            if not body and not title:
                continue
            created = _parse_iso(p.get("writtenAt") or "")  # KST → UTC
            if since and created < since:  # 窗口外旧帖 → 标记停翻页
                reached_old = True
                continue
            writer = p.get("writer") or {}
            out.append({
                "native_id": pid,
                "author": writer.get("nickname") or "—",
                "title": title,
                "body": body or title,
                "label": None,
                "url": f"{web}/{pid}" if web else "",
                "likes": int(p.get("recommendCount", 0) or 0),     # 추천
                "dislikes": int(p.get("notRecommendCount", 0) or 0),  # 비추천
                "views": int(p.get("viewCount", 0) or 0),
                "images": int(p.get("imageCount", 0) or 0),
                "verified": bool(writer.get("isHolderVerified")),  # 持股认证用户
                "comments": 0,  # 下方批量补
                "created_utc": created,
            })
            if len(out) >= limit:
                capped = True
                break
        if capped or reached_old or len(posts) < 50 or not last_id:
            break
        offset = f"-{last_id}"
        time.sleep(0.4)
    _fill_naver_comment_counts(sess, out)  # 批量补真实评论(回复)数
    return out


def _fill_naver_comment_counts(sess: requests.Session, recs: list[dict]) -> None:
    """用 front-api/discussion/comment/counts 批量取每帖真实评论数（讨论深度），回填 rec['comments']。"""
    ids = [r["native_id"] for r in recs if r.get("native_id")]
    by_id: dict[str, dict] = {r["native_id"]: r for r in recs}
    for i in range(0, len(ids), 20):
        chunk = ids[i:i + 20]
        r = _get(sess, NAVER_CCOUNT, params={"postIds": ",".join(chunk)}, timeout=20)
        if r is None:
            continue
        try:
            for c in (r.json().get("result", {}) or {}).get("commentCounts", []) or []:
                pid = str(c.get("postId") or "")
                if pid in by_id:
                    by_id[pid]["comments"] = int(c.get("commentCount", 0) or 0)
        except ValueError:
            continue
        time.sleep(0.2)


# ----------------------------- 小工具 -----------------------------
def _first(pattern: str, text: str, flags: int = re.S) -> str:
    m = re.search(pattern, text, flags)
    return _html.unescape(m.group(1)).strip() if m else ""


def _parse_iso(s: str) -> dt.datetime:
    """ISO 时间 '2026-06-14T06:45:35'（KST，无时区）→ UTC。失败回退现在。"""
    s = (s or "").strip()
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})", s)
    if not m:
        return dt.datetime.utcnow()
    return _to_utc(dt.datetime(*(int(m.group(i)) for i in range(1, 6))))


# ----------------------------- 落库 -----------------------------
def _upsert(s, *, market: str, source: str, ticker: str, board_code: str, origin: str, rec: dict) -> None:
    pid = f"{source}:{ticker}:{rec['native_id']}"
    s.merge(AsiaPost(
        id=pid, market=market, source=source, ticker=ticker, board_code=board_code, origin=origin,
        author=rec.get("author", "—")[:120], title=rec.get("title", "") or "", body=rec.get("body", "") or "",
        label=rec.get("label"), url=rec.get("url", "") or "",
        likes=int(rec.get("likes", 0) or 0), dislikes=int(rec.get("dislikes", 0) or 0),
        views=int(rec.get("views", 0) or 0), comments=int(rec.get("comments", 0) or 0),
        images=int(rec.get("images", 0) or 0), verified=bool(rec.get("verified", False)),
        reply_count=int(rec.get("comments", 0) or 0),  # 兼容旧列
        created_utc=rec.get("created_utc") or dt.datetime.utcnow(),
        fetched_at=dt.datetime.utcnow(),
    ))


def _load_samples() -> dict:
    try:
        with open(PKG_DATA_DIR / "asia_samples.json", "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return {}


def _ensure_tables() -> None:
    """只建 asia 三表（幂等），并给已存在的 asia_posts 补新列（ADD COLUMN，幂等）。"""
    from sqlalchemy import inspect
    from ..common.db import engine
    Base.metadata.create_all(engine, tables=[
        AsiaPost.__table__,
        Base.metadata.tables["asia_analysis"],
        Base.metadata.tables["asia_ticker_summary"],
        Base.metadata.tables["asia_price"],
    ])
    # 老库（无新列）→ 补列，避免重建丢数据。
    try:
        cols = {c["name"] for c in inspect(engine).get_columns("asia_posts")}
    except Exception:  # noqa: BLE001
        cols = set()
    new_cols = (("views", "INTEGER DEFAULT 0"), ("comments", "INTEGER DEFAULT 0"),
                ("images", "INTEGER DEFAULT 0"), ("verified", "BOOLEAN DEFAULT 0"),
                ("sentiment", "FLOAT"))
    missing = [(c, d) for c, d in new_cols if cols and c not in cols]
    if missing:
        with engine.begin() as conn:
            for col, decl in missing:
                conn.exec_driver_sql(f"ALTER TABLE asia_posts ADD COLUMN {col} {decl}")
        print(f"[asia] asia_posts 补列：{[c for c,_ in missing]}")


# ----------------------------- 主流程 -----------------------------
def crawl(per_board: int = 200, sample_fallback: bool = True, markets: set[str] | None = None,
          since_days: int = 7) -> dict:
    _ensure_tables()
    targets = load_targets()
    samples = _load_samples() if sample_fallback else {}
    since = dt.datetime.utcnow() - dt.timedelta(days=since_days) if since_days else None
    stats = {"jp_live": 0, "kr_live": 0, "tw_live": 0, "sample": 0}
    if since:
        print(f"[asia-crawl] 时间窗：仅 {since:%Y-%m-%d %H:%M} (UTC) 之后的帖（近 {since_days} 天）。")

    with session_scope() as s:
        for tgt in targets:
            tk = tgt["ticker"]

            # 日本：Yahoo JP
            if (not markets or "jp" in markets):
                got = 0
                if tgt.get("yahoo_jp"):
                    recs = fetch_yahoo_jp(tgt["yahoo_jp"], per_board, since=since)
                    for rec in recs:
                        _upsert(s, market="jp", source="yahoo_jp", ticker=tk,
                                board_code=tgt["yahoo_jp"], origin="live", rec=rec)
                    got = len(recs)
                    stats["jp_live"] += got
                    print(f"  [jp] {tk}({tgt['yahoo_jp']}): {got} 帖 live")
                if got == 0:  # 无本土板 / 抓取失败 → 标注样本兜底
                    stats["sample"] += _insert_samples(s, samples, "jp", tk)

            # 韩国：Naver 移动端讨论 front-api（国内 domesticStock / 海外 foreignStock 统一）
            if (not markets or "kr" in markets):
                kr_got = 0
                if tgt.get("naver_type") and tgt.get("naver_code"):
                    dtype = tgt["naver_type"]
                    src = "naver_world" if dtype == "foreignStock" else "naver_kr"
                    recs = fetch_naver_discussion(dtype, str(tgt["naver_code"]), per_board, since=since)
                    for rec in recs:
                        _upsert(s, market="kr", source=src, ticker=tk,
                                board_code=str(tgt["naver_code"]), origin="live", rec=rec)
                    kr_got = len(recs)
                    stats["kr_live"] += kr_got
                    print(f"  [kr] {tk}({tgt['naver_code']}/{dtype}): {kr_got} 帖 live")
                if kr_got == 0:
                    stats["sample"] += _insert_samples(s, samples, "kr", tk)

        # 台湾：PTT Stock 综合板（board 级聚合，ticker=TWSTOCK；非按个股分板）
        if not markets or "tw" in markets:
            recs = fetch_ptt_stock(limit=max(per_board * 2, 400), since=since)
            for rec in recs:
                _upsert(s, market="tw", source="ptt", ticker="TWSTOCK", board_code="Stock", origin="live", rec=rec)
            stats["tw_live"] = len(recs)
            print(f"  [tw] PTT/Stock: {len(recs)} 帖 live")

    print(f"[asia-crawl] 完成 {stats}")
    return stats


def _insert_samples(s, samples: dict, market: str, ticker: str) -> int:
    key = f"{market}:{ticker}"
    rows = samples.get(key) or []
    n = 0
    base = dt.datetime.utcnow()
    for i, r in enumerate(rows):
        rec = dict(r)
        rec.setdefault("native_id", f"s{i}")
        rec.setdefault("created_utc", base - dt.timedelta(hours=i + 1))
        src = "yahoo_jp" if market == "jp" else "naver_kr"
        _upsert(s, market=market, source=src, ticker=ticker, board_code="sample", origin="sample", rec=rec)
        n += 1
    if n:
        print(f"  [{market}] {ticker}: 无 live，插入 {n} 条标注样本（origin=sample）")
    return n


if __name__ == "__main__":
    crawl()
