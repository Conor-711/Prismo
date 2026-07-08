"""Direct Xueqiu crawler via Playwright.

Plain HTTP requests hit the Aliyun WAF challenge. A real Playwright-controlled
Chrome page can execute the WAF script, then same-origin `fetch` returns the
JSON API used by the site. This crawler exports the same JSON shape consumed by
`global_retail_xueqiu.ingest`, with a few extra author metadata fields.
"""
from __future__ import annotations

import datetime as dt
import json
import time
from pathlib import Path
from typing import Any

from ..global_retail.regional import load_targets
from ..global_retail.xueqiu_export import ingest

DEFAULT_OUT = "data/exports/gr_cn_xueqiu_direct.json"


def _ms_to_dt(ms: int | float | None) -> dt.datetime | None:
    if not ms:
        return None
    try:
        return dt.datetime.utcfromtimestamp(float(ms) / 1000)
    except Exception:
        return None


def _to_int(v: Any, default: int = 0) -> int:
    try:
        return int(v or default)
    except Exception:
        return default


def _row(symbol: str, item: dict[str, Any]) -> dict[str, Any]:
    user = item.get("user") or {}
    uid = user.get("id") or item.get("user_id") or ""
    post_id = item.get("id")
    return {
        "sym": symbol,
        "id": str(post_id) if post_id is not None else "",
        "u": user.get("screen_name") or item.get("user_screen_name") or "雪球",
        "uid": str(uid) if uid is not None else "",
        "followers": _to_int(user.get("followers_count")),
        "friends": _to_int(user.get("friends_count")),
        "province": user.get("province") or "",
        "city": user.get("city") or "",
        "profile": user.get("profile") or (f"/{uid}" if uid else ""),
        "verified": bool(user.get("verified") or user.get("verified_realname")),
        "ts": _to_int(item.get("created_at")),
        "like": _to_int(item.get("like_count")),
        "reply": _to_int(item.get("reply_count")),
        "view": _to_int(item.get("view_count") or item.get("view_count_format")),
        "rt": _to_int(item.get("retweet_count")),
        "src": item.get("source") or "雪球",
        "t": item.get("text") or item.get("description") or item.get("title") or "",
    }


def _write_rows(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)


def _fetch_page(page, symbol: str, page_no: int, count: int, timeout_ms: int = 12_000) -> dict[str, Any]:  # noqa: ANN001
    return page.evaluate(
        """async ({ symbol, pageNo, count, timeoutMs }) => {
            const params = new URLSearchParams({
              symbol,
              count: String(count),
              comment: "0",
              hl: "0",
              source: "all",
              sort: "time",
              page: String(pageNo),
              q: ""
            });
            const ctrl = new AbortController();
            const timer = setTimeout(() => ctrl.abort(), timeoutMs);
            try {
              const res = await fetch(`/query/v1/symbol/search/status.json?${params.toString()}`, {
                headers: { accept: "application/json,text/plain,*/*" },
                credentials: "include",
                signal: ctrl.signal
              });
              const text = await res.text();
              if (!text.trim().startsWith("{")) {
                return {
                  ok: false,
                  status: res.status,
                  ctype: res.headers.get("content-type"),
                  text: text.slice(0, 400)
                };
              }
              return { ok: true, status: res.status, data: JSON.parse(text) };
            } catch (err) {
              return { ok: false, status: 0, ctype: "", text: String(err && err.message || err) };
            } finally {
              clearTimeout(timer);
            }
        }""",
        {"symbol": symbol, "pageNo": page_no, "count": count, "timeoutMs": timeout_ms},
    )


def crawl(
    *,
    out_path: str = DEFAULT_OUT,
    since_days: int = 14,
    only: list[str] | None = None,
    per_page: int = 20,
    max_pages: int = 80,
    sleep: float = 0.35,
    headless: bool = False,
    do_ingest: bool = True,
) -> dict[str, Any]:
    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # pragma: no cover - environment guidance
        raise RuntimeError(
            "Python Playwright is required for direct Xueqiu crawling. "
            "Run `pipeline/.venv/bin/pip install playwright`."
        ) from exc

    symbols = [t["ticker"].upper() for t in load_targets()]
    if only:
        wanted = {x.strip().upper() for x in only if x.strip()}
        symbols = [s for s in symbols if s in wanted]
        missing = sorted(wanted - set(symbols))
        if missing:
            print(f"[xueqiu-crawl] 标的池未包含：{missing}")

    since = dt.datetime.utcnow() - dt.timedelta(days=since_days)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, Any]] = []
    by: dict[str, int] = {}
    failures: dict[str, str] = {}

    print(
        f"[xueqiu-crawl] {len(symbols)} 标的 · 近 {since_days} 天(≥{since:%Y-%m-%d}) "
        f"· per_page={per_page} · max_pages={max_pages}",
        flush=True,
    )
    if not symbols:
        return {"exported": 0, "tickers": 0, "out": str(out), "by": {}}
    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            headless=headless,
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = browser.new_context(locale="zh-CN")
        page = context.new_page()
        try:
            # Warm up once so Aliyun WAF scripts install cookies and URL-signing hooks.
            page.goto("https://xueqiu.com/S/MU", wait_until="domcontentloaded", timeout=45_000)
            page.wait_for_timeout(1800)
            for i, symbol in enumerate(symbols, 1):
                seen: set[str] = set()
                got = 0
                stop_old = False
                print(f"  [{i:02d}/{len(symbols):02d}] {symbol}: start", flush=True)
                for page_no in range(1, max_pages + 1):
                    data = None
                    last_error = ""
                    for attempt in range(1, 4):
                        try:
                            data = _fetch_page(page, symbol, page_no, per_page)
                            break
                        except Exception as exc:
                            last_error = str(exc).splitlines()[0]
                            print(
                                f"    {symbol}: page {page_no} attempt {attempt} failed: {last_error}",
                                flush=True,
                            )
                            try:
                                page.goto(f"https://xueqiu.com/S/{symbol}", wait_until="domcontentloaded", timeout=45_000)
                                page.wait_for_timeout(1800)
                            except Exception as nav_exc:
                                last_error = str(nav_exc).splitlines()[0]
                    if data is None:
                        failures[f"{symbol}:{page_no}"] = last_error or "evaluate failed"
                        print(f"    {symbol}: stop at page {page_no}: {failures[f'{symbol}:{page_no}']}", flush=True)
                        break
                    if not data.get("ok") and page_no == 1:
                        page.goto(f"https://xueqiu.com/S/{symbol}", wait_until="domcontentloaded", timeout=45_000)
                        page.wait_for_timeout(1800)
                        data = _fetch_page(page, symbol, page_no, per_page)
                    if not data.get("ok"):
                        failures[f"{symbol}:{page_no}"] = (
                            f"non-json status={data.get('status')} ctype={data.get('ctype')} "
                            f"sample={data.get('text')!r}"
                        )
                        print(f"    {symbol}: stop at page {page_no}: {failures[f'{symbol}:{page_no}']}", flush=True)
                        break
                    items = ((data.get("data") or {}).get("list") or [])
                    if not items:
                        break
                    fresh_on_page = 0
                    old_on_page = 0
                    for item in items:
                        row = _row(symbol, item)
                        post_id = row.get("id")
                        if not post_id or post_id in seen:
                            continue
                        seen.add(post_id)
                        created = _ms_to_dt(row.get("ts"))
                        if created and created < since:
                            old_on_page += 1
                            continue
                        rows.append(row)
                        got += 1
                        fresh_on_page += 1
                    if old_on_page and fresh_on_page == 0:
                        stop_old = True
                        break
                    if page_no % 10 == 0:
                        print(f"    {symbol}: page {page_no}, got {got}", flush=True)
                    time.sleep(max(sleep, 0))
                by[symbol] = got
                print(
                    f"  [{i:02d}/{len(symbols):02d}] {symbol}: {got} 条"
                    + (" · reached since cutoff" if stop_old else ""),
                    flush=True,
                )
                _write_rows(out, rows)
        finally:
            browser.close()

    _write_rows(out, rows)
    print(f"[xueqiu-crawl] 导出 {len(rows)} 条 → {out}", flush=True)

    result: dict[str, Any] = {
        "exported": len(rows),
        "tickers": len(by),
        "out": str(out),
        "by": by,
        "failures": failures,
    }
    if do_ingest:
        result["ingest"] = ingest(str(out), since_days=since_days)
    return result


if __name__ == "__main__":
    crawl()
