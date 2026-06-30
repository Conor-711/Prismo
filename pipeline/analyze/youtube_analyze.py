"""YouTube 观点 · 混合分析 + 聚合。

每标的按浏览量排序：**top N 用 Gemini 原生看视频**（画面+音频，最准）；**其余优先字幕文本**
（不占 8h/天视频预算），字幕拿不到再低分辨率原生兜底（受预算）。输出 → yt_analysis；
浏览量加权聚合 → yt_ticker_summary。缺 GEMINI_API_KEY 或 `--mock` → 生成样本验证看板。
"""
from __future__ import annotations

import datetime as dt
import html
import json
import os
import re
import shutil
import subprocess
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from sqlalchemy import delete, select, update

from ..common import gemini, llm
from ..common.config import ROOT, settings
from ..common.db import engine, session_scope
from ..common.models import YtAnalysis, YtFulltext, YtTickerSummary, YtVideo
from ..ingest.youtube_crawl import _ensure_tables

SYSTEM = (
    "你是金融视频观点分析器。给定一条讨论某只美股的 YouTube 视频（语言可能为英/韩/日/中），"
    "判断 UP 主（含其引用的分析师）对该股的投资观点。仅输出 JSON，不要多余文字：\n"
    '{"stance":"bull|bear|neutral","sentiment":-1.0~1.0,"conviction":0~1,'
    '"summary_zh":"两句中文总结","summary_en":"two-sentence English summary",'
    '"key_points_zh":["论点1","论点2"],"key_points_en":["point1","point2"],'
    '"price_target":"若提到价格目标则填写，否则 null"}'
)


def _prompt(v: YtVideo) -> str:
    return f"标的 {v.ticker}。频道《{v.channel}》。请判断该视频对 {v.ticker} 的观点，按系统要求输出 JSON。"


def _stance_from(score: float) -> str:
    return "bull" if score > 0.15 else "bear" if score < -0.15 else "neutral"


def _mood(net: float) -> str:
    return "看多" if net > 0.15 else "看空" if net < -0.15 else "中性"


def fetch_transcript(video_id: str, max_chars: int = 8000) -> str | None:
    """尽力从 watch 页解析字幕轨 → 取文本（拿不到返回 None；生产环境 IP 通常可用）。"""
    try:
        r = requests.get(f"https://www.youtube.com/watch?v={video_id}", timeout=20,
                         headers={"User-Agent": "Mozilla/5.0", "Accept-Language": "en"})
        m = re.search(r'"captionTracks":(\[.*?\])', r.text)
        if not m:
            return None
        tracks = json.loads(m.group(1))
        url = (tracks[0].get("baseUrl") if tracks else None)
        if not url:
            return None
        xml = requests.get(url, timeout=20).text
        txt = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", xml))).strip()
        return txt[:max_chars] or None
    except Exception:  # noqa: BLE001
        return None


def _normalize(data: dict) -> dict | None:
    if not isinstance(data, dict):
        return None
    sc = max(-1.0, min(1.0, float(data.get("sentiment", 0) or 0)))
    return dict(
        stance=(data.get("stance") or _stance_from(sc)), sentiment=sc,
        conviction=max(0.0, min(1.0, float(data.get("conviction", 0) or 0))),
        summary_zh=(data.get("summary_zh") or "")[:800], summary_en=(data.get("summary_en") or "")[:800],
        key_points_zh=data.get("key_points_zh") or [], key_points_en=data.get("key_points_en") or [],
        price_target=(data.get("price_target") or None),
    )


def _analyze_real(v: YtVideo, mode: str, low_res: bool) -> dict | None:
    if mode == "transcript":
        tx = fetch_transcript(v.id)
        if not tx:
            return None
        return _normalize(gemini.messages_json(SYSTEM, f"{_prompt(v)}\n\n字幕：\n{tx}", max_tokens=1200) or {})
    return _normalize(gemini.video_json(v.url, _prompt(v), system=SYSTEM, low_res=low_res, max_tokens=1200) or {})


def _mock_one(v: YtVideo) -> dict:
    import random
    sc = round(random.uniform(-0.6, 0.75), 2)
    st = _stance_from(sc)
    zh = {"bull": "看多", "bear": "看空", "neutral": "中性"}[st]
    return dict(
        stance=st, sentiment=sc, conviction=round(random.uniform(0.4, 0.9), 2),
        summary_zh=f"该频道对 {v.ticker} 整体{zh}，围绕近期催化剂与估值给出判断。（mock）",
        summary_en=f"The channel is {st} on {v.ticker}, citing recent catalysts and valuation. (mock)",
        key_points_zh=[f"{v.ticker} 近期催化剂", "估值与基本面", "主要风险"],
        key_points_en=["recent catalyst", "valuation", "key risk"], price_target=None,
    )


def tag(top_native: int = 2, only_new: bool = True, mock: bool = False,
        per_ticker_cap: int | None = None, workers: int = 1,
        only: set[str] | None = None) -> int:
    _ensure_tables()
    use_real = settings.has_gemini and not mock
    only = {t.strip().upper() for t in only} if only else None  # 仅跑这些标的（如「前十讨论度」）
    # per_ticker_cap 语义 = 「每标的 top-N 视频（按播放量、**全集**）都要被 Gemini 分析」：
    # 先在全集里取每标的 top-N，再剔除已 Gemini 分析(analyzed=True)的 → 只补缺口（幂等、可续跑）。
    # 这样 --per-ticker 10 = 保证每标的最热 10 条都看过，而不是「再多看 10 条」。
    with session_scope() as s:
        all_vids = list(s.execute(select(YtVideo)).scalars())
    grouped: dict[str, list[YtVideo]] = {}
    for v in all_vids:
        grouped.setdefault(v.ticker, []).append(v)
    by_tk: dict[str, list[YtVideo]] = {}
    for k, lst in grouped.items():
        if only and (k or "").upper() not in only:
            continue
        lst = sorted(lst, key=lambda x: -x.view_count)
        if per_ticker_cap:
            lst = lst[:per_ticker_cap]  # 每标的 top-N（按播放量，含已分析的）
        todo = [v for v in lst if not (only_new and v.analyzed)]  # 跳过已 Gemini 看过的
        if todo:
            by_tk[k] = todo
    # 「档位跨标的」排序：先每个标的的第 1 热门，再第 2……→ 预算在标的间铺开，
    # 保证 Gemini 8h/天预算耗尽前尽量让每个标的都拿到它最热的视频分析。
    maxrank = max((len(l) for l in by_tk.values()), default=0)
    plan: list[tuple[int, str, YtVideo]] = []
    for rank in range(maxrank):
        for tk, lst in by_tk.items():
            if rank < len(lst):
                plan.append((rank, tk, lst[rank]))

    # 并发路径（billing 解锁 8h/天后用）：多线程真看视频，主线程逐批落库。
    if use_real and workers > 1:
        return _tag_concurrent(plan, len(by_tk), top_native, workers)

    budget = float(settings.yt_daily_video_minutes)  # 原生看视频分钟预算（8h/天上限留余量）
    done = fail = skip = 0
    consec = 0  # 连续「无结果」计数：配额耗尽/预算用尽时干净中止，避免对几百条狂跑重试
    QUOTA_STOP = 15
    total = len(plan)
    print(f"[yt-tag] 计划 {total} 视频 / {len(by_tk)} 标的（gemini real={use_real}, top_native={top_native}, 预算 {budget:.0f}min）", flush=True)
    for rank, tk, v in plan:
        native = rank < top_native
        res, mode = None, "video"
        try:  # 网络/解析失败只跳过这条（不毁整批；该条留 analyzed=False 下次再试）
            if not use_real:
                res = _mock_one(v); mode = "video" if native else "transcript"
            elif native and budget - v.duration_s / 60 > 0:
                res = _analyze_real(v, "video", low_res=False); budget -= v.duration_s / 60; mode = "video"
            else:
                res = _analyze_real(v, "transcript", low_res=True); mode = "transcript"
                if res is None and budget - v.duration_s / 60 > 0:  # 字幕失败→低清原生兜底
                    res = _analyze_real(v, "video", low_res=True); budget -= v.duration_s / 60; mode = "video"
        except Exception as e:  # noqa: BLE001
            fail += 1
            consec += 1
            print(f"  [yt-tag] ✗ {tk} {v.id}: {str(e)[:90]}", flush=True)
            if consec >= QUOTA_STOP:
                print(f"[yt-tag] 连续 {consec} 条无结果（疑似配额/预算耗尽），提前中止；已分析的已落库。", flush=True)
                break
            continue
        if res is None:
            skip += 1
            consec += 1
            if consec >= QUOTA_STOP:
                print(f"[yt-tag] 连续 {consec} 条无结果（疑似配额/预算耗尽），提前中止；已分析的已落库。", flush=True)
                break
            continue
        consec = 0  # 有成功结果 → 重置
        try:  # 逐条提交：部分成功也落库（避免一次性 commit 失败全丢）
            with session_scope() as s:
                s.merge(YtAnalysis(video_id=v.id, ticker=tk, mode=mode,
                                   model=(f"gemini:{settings.gemini_model}" if use_real else "mock"),
                                   analyzed_at=dt.datetime.utcnow(), **res))
                s.execute(update(YtVideo).where(YtVideo.id == v.id).values(analyzed=True))
            done += 1
            print(f"  [yt-tag] ✓ {tk} {v.id} {res['stance']} ({mode}) [{done}/{total}]", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"  [yt-tag] 写库失败 {tk} {v.id}: {str(e)[:90]}", flush=True)
    print(f"[yt-tag] 完成 {done}（失败 {fail}，跳过 {skip}），原生预算余 {budget:.0f}min", flush=True)
    rollup()
    return done


def _tag_concurrent(plan: list[tuple[int, str, "YtVideo"]], n_tk: int,
                    top_native: int, workers: int) -> int:
    """billing 版：多线程真看视频（top_native 条全清、其余低清省成本）。

    transcript 这台 IP 抓不到 → 一律原生 video。主线程 as_completed 逐批落库（单写者，避锁）。
    系统性失败（如鉴权坏）：连续 30 条无结果 → 置 abort，后续任务即刻空跑收尾，避免烧钱。
    """
    total = len(plan)
    print(f"[yt-tag] 计划 {total} 视频 / {n_tk} 标的（gemini 并发 workers={workers}, top_native={top_native}，"
          f"billing 无 8h 预算限制；top-{top_native} 全清其余低清）", flush=True)
    if not total:
        rollup()
        return 0
    MAX_NATIVE_S = 150 * 60  # 低清下 ~1M token 上下文约够 2.5h 视频；超过则跳过(交给 DeepSeek 标题兜底)，其余一律真看视频
    done = fail = skip = 0
    consec_fail = 0
    abort = threading.Event()
    buf: list[tuple[str, "YtVideo", dict]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:
            for tk, v, res in buf:
                s.merge(YtAnalysis(video_id=v.id, ticker=tk, mode="video",
                                   model=f"gemini:{settings.gemini_model}",
                                   analyzed_at=dt.datetime.utcnow(), **res))
                s.execute(update(YtVideo).where(YtVideo.id == v.id).values(analyzed=True))
        done += len(buf)
        buf.clear()

    def _work(item: tuple[int, str, "YtVideo"]):
        if abort.is_set():
            return None
        rank, tk, v = item
        if (v.duration_s or 0) > MAX_NATIVE_S:  # 超长 → 跳过原生(不计 consec)，DeepSeek 文本兜底
            return None
        res = _analyze_real(v, "video", low_res=(rank >= top_native))  # top-N 全清，其余低清
        return tk, v, res

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(_work, it) for it in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                out = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1; consec_fail += 1
                if fail <= 12:
                    print(f"  [yt-tag] ✗ {str(e)[:90]}", flush=True)
                out = None
            if out is None or out[2] is None:
                if out is None:
                    skip += 1  # abort 空跑或异常已计
                else:
                    skip += 1; consec_fail += 1
                if consec_fail and consec_fail % 30 == 0 and not abort.is_set():
                    abort.set()
                    print(f"[yt-tag] 连续 {consec_fail} 条无结果（疑似系统性失败），中止后续；已分析的已落库。", flush=True)
                continue
            consec_fail = 0
            tk, v, res = out
            buf.append((tk, v, res))
            print(f"  [yt-tag] ✓ {tk} {v.id} {res.get('stance')} [{done + len(buf)}/{total}] skip={skip} fail={fail}", flush=True)
            if len(buf) >= 10:
                _flush()
    _flush()
    print(f"[yt-tag] 完成 {done}（失败 {fail}，跳过 {skip}）", flush=True)
    rollup()
    return done


# ----------------------------- 无 Gemini 配额兜底：标题+简介 → DeepSeek -----------------------------

SYSTEM_TEXT = (
    "你是金融视频观点分析器。下面给出一条 YouTube 财经视频的【标题】与【简介】"
    "（注意：不是视频内容本身，简介里可能混有推广/链接）。请据此推断 UP 主对该股的投资观点，"
    "并给出双语结果。务必『提炼』而非照抄标题。仅输出 JSON，不要多余文字：\n"
    '{"stance":"bull|bear|neutral","sentiment":-1.0~1.0,"conviction":0~1,'
    '"summary_zh":"两句中文：为什么看多/看空/中性","summary_en":"two-sentence English: the why",'
    '"key_points_zh":["要点1","要点2"],"key_points_en":["point1","point2"],'
    '"price_target":"若提到价格目标则填，否则 null"}\n'
    "若标题/简介几乎只有推广链接、无实质观点，summary 写「仅据标题/简介推断，信息有限」/"
    "\"inferred from title only, limited info\"、stance 取 neutral、conviction 取低值。"
)


def _text_input(v: YtVideo) -> str:
    desc = (v.description or "")[:1500]
    return f"标的 {v.ticker}。频道《{v.channel}》。\n标题：{v.title}\n简介：{desc}"


def tag_text(per_ticker: int = 20, workers: int = 6) -> int:
    """无 Gemini 配额的兜底分析：用 **标题+简介** 跑 DeepSeek(flash) 出双语观点 → yt_analysis(mode=text)。

    覆盖 Gemini 没看的视频，至少做到「翻译 + 立场/理由推断」而非照搬原标题。
    - 只处理**尚无 yt_analysis** 的视频（不看 analyzed 旗标）；**不置 analyzed=True** →
      Gemini `tag()` 之后仍可用视频理解升级这些条目（merge 覆盖 DeepSeek 版，质量更高）。
    - 每标的取播放量 top-N（默认 20=前端 KOL 流 LIMIT）。并发只在网络层，主线程逐批落库。
    """
    _ensure_tables()
    if not llm.available(llm.LOW):
        print("[yt-text] 无 DeepSeek key（DEEPSEEK_API_KEY），跳过。", flush=True)
        return 0
    with session_scope() as s:
        all_vids = list(s.execute(select(YtVideo)).scalars())
        have = set(s.execute(select(YtAnalysis.video_id)).scalars())
    by_tk: dict[str, list[YtVideo]] = {}
    for v in all_vids:
        if v.id in have:
            continue
        by_tk.setdefault(v.ticker, []).append(v)
    plan: list[YtVideo] = []
    for k in by_tk:
        by_tk[k].sort(key=lambda x: -x.view_count)
        plan += by_tk[k][:per_ticker]

    total = len(plan)
    print(f"[yt-text] 计划 {total} 视频 / {len(by_tk)} 标的（DeepSeek 标题+简介，model={llm.model_label(llm.LOW)}）", flush=True)
    if not total:
        return 0
    done = fail = skip = 0
    buf: list[tuple[YtVideo, dict]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:
            for v, res in buf:
                s.merge(YtAnalysis(video_id=v.id, ticker=v.ticker, mode="text",
                                   model=f"deepseek:{settings.deepseek_model_low}",
                                   analyzed_at=dt.datetime.utcnow(), **res))
        done += len(buf)
        buf.clear()

    def _work(v: YtVideo) -> tuple[YtVideo, dict | None]:
        data = llm.messages_json(llm.LOW, SYSTEM_TEXT, _text_input(v), max_tokens=600)
        res = _normalize(data) if data else None
        if res and not (res.get("summary_zh") or res.get("summary_en")):
            res = None  # 空总结不入库
        return v, res

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, v) for v in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                v, res = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [yt-text] ✗ {str(e)[:90]}", flush=True)
                continue
            if res is None:
                skip += 1
                continue
            buf.append((v, res))
            if len(buf) >= 40:
                _flush()
            if i % 50 == 0:
                print(f"  [yt-text] …{i}/{total}（done={done}+buf{len(buf)} skip={skip} fail={fail}）", flush=True)
    _flush()
    print(f"[yt-text] 完成 {done}（跳过 {skip}，失败 {fail}）", flush=True)
    rollup()
    return done


def rollup(window_hours: int = 24) -> int:
    _ensure_tables()
    with session_scope() as s:
        rows = s.execute(
            select(YtVideo.ticker, YtVideo.market, YtVideo.view_count, YtAnalysis.stance, YtAnalysis.sentiment)
            .join(YtAnalysis, YtAnalysis.video_id == YtVideo.id)
        ).all()
        allv = s.execute(select(YtVideo.ticker, YtVideo.market, YtVideo.view_count)).all()

    agg: dict[tuple, dict] = {}
    for tk, mkt, vc, stance, senti in rows:
        d = agg.setdefault((tk, mkt), dict(b=0, be=0, n=0, wsum=0.0, wt=0))
        d["b" if stance == "bull" else "be" if stance == "bear" else "n"] += 1
        w = max(1, vc or 0); d["wsum"] += (senti or 0) * w; d["wt"] += w
    vcount: dict[tuple, int] = {}
    vviews: dict[tuple, int] = {}
    for tk, mkt, vc in allv:
        vcount[(tk, mkt)] = vcount.get((tk, mkt), 0) + 1
        vviews[(tk, mkt)] = vviews.get((tk, mkt), 0) + (vc or 0)

    with session_scope() as s:
        s.execute(delete(YtTickerSummary))
        for (tk, mkt), d in agg.items():
            net = round(d["wsum"] / d["wt"], 3) if d["wt"] else 0.0
            s.add(YtTickerSummary(
                ticker=tk, market=mkt, window_hours=window_hours,
                video_count=vcount.get((tk, mkt), 0), analyzed_count=d["b"] + d["be"] + d["n"],
                bull_count=d["b"], bear_count=d["be"], neutral_count=d["n"],
                net_sentiment=net, mood_label=_mood(net), total_views=vviews.get((tk, mkt), 0),
                overview_zh="", overview_en="", updated_at=dt.datetime.utcnow()))
    print(f"[yt-rollup] {len(agg)} 标的汇总")
    return len(agg)


# ----------------------------- 完整内容还原（优化字幕 + 关键画面）-----------------------------

SYSTEM_FULLTEXT = (
    "你是金融视频口播转录器。把视频里**人说的话完整还原**成有序段落，让读者不看视频也能读全、且读得轻松。\n"
    '每段：{"type":"speech","speaker":"说话人","text":"该段口播（通顺中文书面语，可含 Markdown 行内强调）"}\n'
    "规则：\n"
    "1) **只转口播**：只还原人说的话；**绝不**描述画面/图表/幻灯片/字幕（不要出现「画面显示」「图中」之类）。\n"
    "2) **书面化但不删信息**：去口水话/重复/语气词、理顺语序，但保留每一个论点/数据/推理/结论——是完整还原，不是摘要。\n"
    "3) **按语义分段**：把讲同一个点的句子归到同一段，话题/论点切换才另起一段。每段约 **3-6 句、120-280 字**——既不要一句一段（太碎），也**绝不**整篇一段。\n"
    "4) **划重点（Markdown 行内强调）**：在 text 里用 `**加粗**` 标出该段最关键的结论/数据/催化剂/标的名/目标价，用 `*斜体*` 标出转折、强调或重要旁白。**务必克制**：每段加粗至多 1-3 处关键短语，绝不整句整段加粗、绝不滥用（多数句子应是普通文字）。\n"
    "5) **标记说话人 speaker**：\n"
    "   · 访谈/播客/对话/连线等多人视频——每段填说话人；能听出名字就用名字，否则用「主持人」「嘉宾」，多位嘉宾用「嘉宾A」「嘉宾B」并全程一致。\n"
    "   · 全程只有一个人讲（独白/单人分析）——speaker 一律填空字符串 \"\"（前端会按无说话人排版）。\n"
    "6) **剔除与投资无关内容**：赞助商口播/广告、点赞订阅、加入VIP/Discord/Patreon/直播间、App下载/二维码、自我推广、抽奖——都不要输出。\n"
    "7) 按时间顺序；中立转述（是说话人的话，不要加你自己的评论）。\n"
    '仅输出 JSON，不要多余文字：{"segments":[...]}'
)

_NODE_DIR = os.path.expanduser("~/.nvm/versions/node/v22.22.2/bin")


def _ensure_fulltext_table() -> None:
    YtFulltext.__table__.create(engine, checkfirst=True)


def _tool_env() -> dict:
    """给 yt-dlp/ffmpeg 的 PATH 补上 node(EJS 解 n-sig) + deno(bgutil PO token) + brew(ffmpeg)。"""
    env = dict(os.environ)
    extra = [p for p in (_NODE_DIR, "/opt/homebrew/bin") if os.path.isdir(p)]
    env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
    return env


def _download_video(url: str, out_base: str) -> str | None:
    """下载视频到临时文件（截完帧即删）。配方：web client + 浏览器 cookies + bgutil PO token + deno EJS。
    YouTube 对本机 IP 开了 SABR/反爬→只 format 18(360p) 可靠可下；360p 足够看清幻灯/图表数字。"""
    ytdlp = str(ROOT / "pipeline" / ".venv" / "bin" / "yt-dlp")
    cmd = [ytdlp, "--cookies-from-browser", "chrome", "--extractor-args", "youtube:player_client=web",
           "-f", "18/best[height<=480][ext=mp4]/best[height<=480]/best", "--no-warnings", "--quiet",
           "--socket-timeout", "30", "--retries", "8", "-o", out_base + ".%(ext)s", url]
    try:
        subprocess.run(cmd, env=_tool_env(), capture_output=True, text=True, timeout=420)
    except Exception:  # noqa: BLE001
        return None
    for ext in ("mp4", "mkv", "webm"):
        p = out_base + "." + ext
        if os.path.exists(p) and os.path.getsize(p) > 10000:
            return p
    return None


_FRAME_DEDUP = 22  # aHash 汉明距离：<阈值=近似帧→折叠
_STOP = {"the", "and", "for", "with", "this", "that", "are", "you", "was", "has", "have", "will",
         "from", "not", "but", "all", "can", "its", "now", "new", "more", "most", "than", "then",
         "also", "may", "one", "two", "get", "let", "see", "via", "per", "inc", "corp", "ltd",
         "their", "they", "what", "when", "how", "who", "why", "into", "out", "over", "your"}


def _tok(text: str) -> set[str]:
    """从文案/OCR 文本抽「语言无关 token」：英文词(≥3,去停用词) + 数字串(去分隔符,≥2 位)。
    captioned「市值3229.4亿」→ '32294'；slide「$322.94B」→ '32294' → 可匹配。"""
    t = (text or "").lower()
    words = {w for w in re.findall(r"[a-z][a-z&\-]{2,}", t) if w not in _STOP and len(w) >= 3}
    nums = set(re.findall(r"\d{2,}", re.sub(r"[.,]", "", t)))
    return words | nums


def _select_frames(mp4: str, visuals: list[dict], viddir, ffmpeg: str, tesseract: str, step: int = 2) -> int:
    """OCR 按内容匹配帧（不信 Gemini 时间戳）：每 step 秒采一帧 → aHash 折叠近似屏 → OCR 各独立屏 →
    每条画面文案按 token 重叠**有序贪心**匹配到 OCR 文本最吻合的那一帧（要求重叠≥2，否则丢弃该画面）。"""
    from PIL import Image
    sdir = viddir.parent / (viddir.name + "_samp")
    if sdir.exists():
        shutil.rmtree(sdir)
    sdir.mkdir(parents=True, exist_ok=True)
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", mp4, "-vf", f"fps=1/{step}",
                    str(sdir / "s_%04d.jpg")], capture_output=True)
    samples = sorted(sdir.glob("s_*.jpg"))
    if not samples:
        shutil.rmtree(sdir, ignore_errors=True)
        for seg in visuals:
            seg["_drop"] = True
        return 0

    def ahash(p, n=16):
        px = list(Image.open(p).convert("L").resize((n, n)).getdata())
        a = sum(px) / len(px)
        return [1 if v > a else 0 for v in px]

    def ham(a, b):
        return sum(x != y for x, y in zip(a, b))

    distinct: list[dict] = []  # 去重后的独立屏：{path, hash, tok(OCR)}
    last = None
    for p in samples:
        h = ahash(p)
        if last is not None and ham(last, h) < _FRAME_DEDUP:
            continue
        last = h
        try:
            txt = subprocess.run([tesseract, str(p), "stdout", "-l", "eng"],
                                 capture_output=True, text=True, timeout=30).stdout
        except Exception:  # noqa: BLE001
            txt = ""
        distinct.append({"path": p, "tok": _tok(txt)})

    kept = 0
    ptr = 0  # 有序：第 i 条画面只在上一条匹配位置之后找
    for seg in visuals:
        ctok = _tok(seg.get("caption", ""))
        best, besti = 0, -1
        for j in range(ptr, len(distinct)):
            sc = len(ctok & distinct[j]["tok"])
            if sc > best:
                best, besti = sc, j
        if best >= 2 and besti >= 0:
            shutil.copy(distinct[besti]["path"], str(viddir / f"{kept}.jpg"))
            seg["frame"] = f"yt-frames/{viddir.name}/{kept}.jpg"
            kept += 1
            ptr = besti + 1
        else:
            seg["_drop"] = True  # 没有内容吻合的帧 → 宁缺勿错
    shutil.rmtree(sdir, ignore_errors=True)
    return kept


_SENT_SPLIT = re.compile(r"(?<=[。！？!?…])")  # 句末切分(保留标点在前句)
_MD_STRIP = re.compile(r"\*{1,2}(.+?)\*{1,2}")  # 去 **加粗** / *斜体* → 纯文本


def _strip_md(s: str) -> str:
    return _MD_STRIP.sub(r"\1", s or "")


def _split_speech_text(text: str, target: int = 220, hard: int = 320) -> list[str]:
    """把口播段落按句子聚合成易读小段（目标 ~target 字/段）。Gemini 现按语义分段(每段一个 speech)，
    这里只兜底它偶尔把整篇塞进一段的情况；≤hard 的段原样保留（尊重 Gemini 的语义分段 + 行内强调）。
    断段只在 ** 配对闭合处，避免切断 Markdown 加粗。"""
    text = (text or "").strip()
    if not text:
        return []
    out: list[str] = []
    for block in re.split(r"\n+", text):
        block = block.strip()
        if not block:
            continue
        if len(block) <= hard:
            out.append(block)
            continue
        buf = ""
        for sent in (s for s in _SENT_SPLIT.split(block) if s.strip()):
            if buf and len(buf) + len(sent) > target and buf.count("**") % 2 == 0:
                out.append(buf)
                buf = sent
            else:
                buf += sent
        if buf.strip():
            out.append(buf.strip())
    return out


def gen_fulltext(only: set[str] | None = None, per_ticker: int = 10, workers: int = 4,
                 force: bool = False, low_res: bool = False, max_native_min: int = 150,
                 frames: bool = True) -> int:
    """Gemini 真看视频 → 结构化「完整内容」（优化口播 + 关键画面**真实视频帧**）→ yt_fulltext。

    每视频：① Gemini 出有序段落(口播/画面+文案，剔宣传) → ② yt-dlp 下载(360p,瞬时,截完即删)
    → ③ 采样帧 + OCR **按文案内容匹配**出真正那张幻灯片(不信 Gemini 时间戳)、aHash 折叠近似屏 →
    ④ 命中帧存 web/public/yt-frames/、段落记 frame 路径；未命中的画面段丢弃(宁缺勿错) →
    存 segments(有序) + content_zh(扁平口播)。顺序处理、逐条落库(可续)。按 only + 每标的 top-N 播放量。
    """
    _ensure_fulltext_table()
    if not settings.has_gemini:
        print("[yt-full] 无 GEMINI_API_KEY，跳过。", flush=True)
        return 0
    ffmpeg = shutil.which("ffmpeg", path=_tool_env()["PATH"]) or "/opt/homebrew/bin/ffmpeg"
    tesseract = shutil.which("tesseract", path=_tool_env()["PATH"]) or "/opt/homebrew/bin/tesseract"
    only = {t.strip().upper() for t in only} if only else None
    cap_s = max_native_min * 60
    frames_root = ROOT / "web" / "public" / "yt-frames"
    tmpdir = ROOT / "data" / "_ytframes_tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)

    with session_scope() as s:
        all_vids = list(s.execute(select(YtVideo)).scalars())
        have = set(s.execute(select(YtFulltext.video_id)).scalars()) if not force else set()
    grouped: dict[str, list[YtVideo]] = {}
    for v in all_vids:
        if only and (v.ticker or "").upper() not in only:
            continue
        grouped.setdefault(v.ticker, []).append(v)
    plan: list[YtVideo] = []
    for lst in grouped.values():
        for v in sorted(lst, key=lambda x: -x.view_count)[:per_ticker]:
            if v.id not in have and (v.duration_s or 0) <= cap_s:
                plan.append(v)

    total = len(plan)
    print(f"[yt-full] 计划 {total} 视频 / {len(grouped)} 标的（结构化+真帧, model={settings.gemini_model}, force={force}）", flush=True)
    if not total:
        return 0

    done = fail = skip = 0
    for i, v in enumerate(plan, 1):
        try:
            prompt = f"标的 {v.ticker}。频道《{v.channel}》。按系统要求结构化还原该视频。"
            data = gemini.video_json(v.url, prompt, system=SYSTEM_FULLTEXT, low_res=low_res, max_tokens=8000)
            segs = (data or {}).get("segments") if isinstance(data, dict) else None
            if not isinstance(segs, list) or not segs:
                skip += 1
                print(f"  [yt-full] – {v.ticker} {v.id} 无段落", flush=True)
                continue
            norm: list[dict] = []
            visuals: list[dict] = []
            for sg in segs:
                if not isinstance(sg, dict):
                    continue
                if sg.get("type") == "speech":
                    tx = str(sg.get("text") or "").strip()
                    if tx:
                        spk = str(sg.get("speaker") or "").strip()  # 多人(访谈/播客)才有；独白留空
                        for para in _split_speech_text(tx):  # 兜底拆分过长段落，保证可读
                            seg = {"type": "speech", "text": para}
                            if spk:
                                seg["speaker"] = spk
                            norm.append(seg)
                elif sg.get("type") == "visual" and isinstance(sg.get("sec"), (int, float)):  # 旧档兼容；新提示只产口播
                    seg = {"type": "visual", "sec": int(sg["sec"]), "caption": str(sg.get("caption") or "").strip()}
                    norm.append(seg)
                    visuals.append(seg)
            flat = "\n\n".join(  # 扁平兜底文本去掉 Markdown（卡片/搜索用纯文本；富文本只在 segments）
                (f"{s['speaker']}：{_strip_md(s['text'])}" if s.get("speaker") else _strip_md(s["text"]))
                for s in norm if s["type"] == "speech"
            )

            mp4 = _download_video(v.url, str(tmpdir / v.id)) if (visuals and frames) else None
            if visuals and mp4:
                viddir = frames_root / v.id
                if viddir.exists():
                    shutil.rmtree(viddir)
                viddir.mkdir(parents=True, exist_ok=True)
                _select_frames(mp4, visuals, viddir, ffmpeg, tesseract)  # OCR 按内容匹配真正的幻灯片
                try:
                    os.remove(mp4)
                except OSError:
                    pass
            else:
                for seg in visuals:  # 无帧（无 visual 或下载失败）→ 去掉视觉段，保留口播
                    seg["_drop"] = True

            final = [s for s in norm if not (s.get("type") == "visual" and (s.get("_drop") or not s.get("frame")))]
            for s in final:
                s.pop("_drop", None)
                s.pop("sec", None)
            nframes = sum(1 for s in final if s.get("type") == "visual")
            with session_scope() as s:
                s.merge(YtFulltext(video_id=v.id, ticker=v.ticker, content_zh=flat, content_en="",
                                   segments=final, model=f"gemini:{settings.gemini_model}",
                                   created_at=dt.datetime.utcnow()))
            done += 1
            print(f"  [yt-full] ✓ {v.ticker} {v.id} 段{len(final)}/帧{nframes} [{done}/{total}] skip={skip} fail={fail}", flush=True)
        except Exception as e:  # noqa: BLE001
            fail += 1
            print(f"  [yt-full] ✗ {v.ticker} {v.id}: {str(e)[:100]}", flush=True)
    print(f"[yt-full] 完成 {done}（跳过 {skip}，失败 {fail}）", flush=True)
    return done


if __name__ == "__main__":
    tag(mock=True)
