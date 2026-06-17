"""亚洲散户帖 AI 分析（沿用 common/llm.py 档位路由）。

两级，与主管线一致：
  - 逐帖打标：HIGH=通义千问（思考模式），读日/韩散户原文，产出双语（中+英）情绪/多空/质量/摘要/论点。
  - 每格汇总：MID=DeepSeek，把一格(市场×标的)的逐帖结论综述成一段 overview（中+英）。
缺 key 时回退确定性的 CJK 关键词启发式（analyze_mock_asia），零成本跑通全流程（仿 item_analyze.analyze_mock）。
"""
from __future__ import annotations

import datetime as dt

from sqlalchemy import delete, select, update

from ..common.db import session_scope
from ..common.llm import HIGH, LOW, MID, available, chat, messages_json, model_label
from ..common.models import AsiaAnalysis, AsiaPost, AsiaTickerSummary

# 每格语言由 market 决定（日本=日文，韩国=韩文，台湾=繁中），无需检测。
LANG_BY_MARKET = {"jp": "ja", "kr": "ko", "tw": "zh"}
MARKET_NAME = {"jp": "日本(Yahoo Finance)", "kr": "韩国(Naver)", "tw": "台湾(PTT Stock)"}

# 固定主题标签（半导体散户语境），与站点中文标签风格一致。
ASIA_THEMES = ["HBM/高带宽内存", "AI算力需求", "财报业绩", "估值与泡沫", "内存周期",
               "竞争格局", "出口管制与地缘", "短线投机", "股息回购", "供需与价格"]

# ----------------------------- mock 关键词（CJK） -----------------------------
JA_BULL = ["買い", "買いたい", "強気", "上昇", "上げ", "急騰", "ホールド", "期待", "強い",
           "最高値", "買い増し", "押し目", "仕込み", "上方修正", "好決算"]
JA_BEAR = ["売り", "売りたい", "弱気", "下落", "暴落", "損切り", "危険", "バブル", "過大評価",
           "下げ", "弱い", "高値掴み", "撤退", "下方修正"]
KO_BULL = ["매수", "사자", "강세", "상승", "급등", "호재", "가즈아", "존버", "텐배거",
           "우상향", "가자", "사라", "물타기", "반등", "신고가"]
KO_BEAR = ["매도", "팔자", "약세", "하락", "폭락", "손절", "악재", "거품", "고점",
           "비싸", "위험", "떨어", "손실", "물렸"]
# 台股繁中黑话：航海王/歐印=all in/起飛/噴=看多；套牢/畢業/水餃/違約交割=看空。
ZH_BULL = ["看多", "做多", "買進", "買超", "航海王", "歐印", "起飛", "噴出", "噴", "穩了",
           "抱緊", "上看", "突破", "漲停", "多單", "加碼", "上攻", "創高", "嗨"]
ZH_BEAR = ["看空", "做空", "賣出", "賣超", "套牢", "畢業", "崩", "跌停", "認賠", "水餃",
           "殺", "空單", "違約交割", "回檔", "崩盤", "停損", "破底", "套"]


def _kw_for(market: str):
    if market == "jp":
        return JA_BULL, JA_BEAR
    if market == "kr":
        return KO_BULL, KO_BEAR
    return ZH_BULL, ZH_BEAR
# 原生情绪标签 → 倾向先验（强信号）。
LABEL_PRIOR = {
    "強く買いたい": 0.9, "買いたい": 0.5, "中立": 0.0, "売りたい": -0.5, "強く売りたい": -0.9,
}


def _count(words: list[str], text: str) -> int:
    return sum(text.count(w) for w in words)


def analyze_mock_asia(post: AsiaPost) -> dict:
    lang = LANG_BY_MARKET.get(post.market, "ja")
    text = f"{post.title}\n{post.body}"
    bull, bear = _kw_for(post.market)
    nb, nr = _count(bull, text), _count(bear, text)
    score = 0.0
    if post.label in LABEL_PRIOR:  # 原生标签优先
        score = LABEL_PRIOR[post.label]
    elif nb + nr:
        score = round((nb - nr) / (nb + nr), 2)
    stance = "bull" if score > 0.15 else "bear" if score < -0.15 else "neutral"
    label = "bullish" if stance == "bull" else "bearish" if stance == "bear" else "neutral"
    quality = round(min(1.0, 0.3 + min(len(post.body), 200) / 400 + (0.1 if post.likes > 5 else 0)), 2)
    snippet = (post.body or post.title)[:80]
    return {
        "lang": lang, "sentiment_label": label, "sentiment_score": score, "stance": stance,
        "quality_score": quality, "themes": [],
        "tldr_zh": snippet, "tldr_en": snippet,
        "bull_points_zh": [], "bull_points_en": [], "bear_points_zh": [], "bear_points_en": [],
        "model": "mock-cjk-heuristic",
    }


# ----------------------------- 真实千问 -----------------------------
SYSTEM_ASIA = """你是专业的亚洲股市社媒舆情分析师，精通日文、韩文、台湾繁中散户黑话与反讽。读一条来自日本(Yahoo Finance 掲示板)、韩国(Naver 종목토론방)或台湾(PTT Stock 板)的散户帖，给出严谨、结构化的分析。只输出一个 JSON 对象（不要任何额外文字），字段全部必填：
- sentiment_label: "bullish" | "bearish" | "neutral"
- sentiment_score: -1.0~1.0（作者对该标的的情绪方向与强度）
- stance: "bull" | "bear" | "neutral"
- quality_score: 0~1（有数据/逻辑=高；纯情绪宣泄/段子/灌水=低）
- themes: 从下列固定列表挑 0~3 个最贴切的，原样照抄："HBM/高带宽内存","AI算力需求","财报业绩","估值与泡沫","内存周期","竞争格局","出口管制与地缘","短线投机","股息回购","供需与价格"
- tldr_zh: 一句简体中文摘要（<=50字，保留 ticker/数字/专有名词）
- tldr_en: 对应英文一句话摘要（<=140字符）
- bull_points_zh / bear_points_zh: 看多/看空论据的简体中文数组（各≤2，从原文提炼，可空[]）
- bull_points_en / bear_points_en: 与中文一一对应的英文数组（长度必须相同）

要点：① 读懂日韩台散户黑话与反讽（日："強く買いたい/押し目/仕込み"=看多，"高値掴み/撤退"=看空。韩："가즈아/존버/텐배거/우상향"=看多，"손절/물렸/거품/고점"=看空。台股："歐印(all in)/航海王/起飛/噴/穩了"=看多，"套牢/畢業/水餃股/違約交割/停損"=看空。台股标题 [標的]=个股多空、[請益]=提问、[新聞]=新闻、[心得]/[閒聊]）。用调侃语气唱多往往是反讽=看空。② 论据要真实可成立；玩笑/灌水给低 quality 且论据可空。③ 严格只输出 JSON。"""


def _build_user(post: AsiaPost, name_zh: str) -> str:
    lbl = f"\n用户原生标签: {post.label}" if post.label else ""
    return (f"市场: {MARKET_NAME.get(post.market, post.market)}\n标的: {name_zh}({post.ticker})\n"
            f"赞数: {post.likes}{lbl}\n帖子原文（{LANG_BY_MARKET.get(post.market)}）:\n{(post.body or post.title)[:1200]}")


def analyze_asia(post: AsiaPost, name_zh: str) -> dict:
    data = messages_json(HIGH, SYSTEM_ASIA, _build_user(post, name_zh),
                         max_tokens=1500, enable_thinking=True) or {}

    def _arr(k: str) -> list:
        v = data.get(k)
        return [str(x) for x in v][:2] if isinstance(v, list) else []

    bz, be = _arr("bull_points_zh"), _arr("bull_points_en")
    rz, re_ = _arr("bear_points_zh"), _arr("bear_points_en")
    be = (be + [""] * len(bz))[: len(bz)]  # 对齐中英长度
    re_ = (re_ + [""] * len(rz))[: len(rz)]
    themes = [t for t in (data.get("themes") or []) if t in ASIA_THEMES][:3]
    return {
        "lang": LANG_BY_MARKET.get(post.market, ""),
        "sentiment_label": data.get("sentiment_label", "neutral") or "neutral",
        "sentiment_score": float(data.get("sentiment_score", 0) or 0),
        "stance": data.get("stance", "neutral") or "neutral",
        "quality_score": float(data.get("quality_score", 0.4) or 0.4),
        "themes": themes,
        "tldr_zh": str(data.get("tldr_zh", "") or "")[:160],
        "tldr_en": str(data.get("tldr_en", "") or "")[:240],
        "bull_points_zh": bz, "bull_points_en": be,
        "bear_points_zh": rz, "bear_points_en": re_,
        "model": model_label(HIGH),
    }


# ----------------------------- 逐帖打标主流程 -----------------------------
def _name_map() -> dict[str, str]:
    from ..ingest.asia_crawl import load_targets
    return {t["ticker"]: t.get("name_zh", t["ticker"]) for t in load_targets()}


def run_asia_analyze(limit_per: int = 12, mock: bool = False, workers: int = 6) -> int:
    """增量逐帖打标：每格(市场×标的)按 赞数/时间 取 Top limit_per，跳过已分析。"""
    use_real = (not mock) and available(HIGH)
    if not mock and not use_real:
        print("[asia-analyze] 无 HIGH key，回退 mock 启发式。")
    names = _name_map()

    with session_scope() as s:
        done = {pid for (pid,) in s.execute(select(AsiaAnalysis.post_id)).all()}
        posts = s.execute(select(AsiaPost)).scalars().all()
        # 按格分组，组内按 赞数→时间 排序，取 Top limit_per 里未分析的
        groups: dict[tuple, list] = {}
        for p in posts:
            groups.setdefault((p.market, p.ticker), []).append(p)
        work = []
        for key, plist in groups.items():
            plist.sort(key=lambda x: (x.likes, x.created_utc or dt.datetime.min), reverse=True)
            for p in plist[:limit_per]:
                if p.id not in done:
                    work.append(p)
                    s.expunge(p)

    total = len(work)
    print(f"[asia-analyze] 待分析 {total} 帖（real={use_real}）。", flush=True)

    def one(p: AsiaPost) -> tuple[str, dict]:
        try:
            res = analyze_asia(p, names.get(p.ticker, p.ticker)) if use_real else analyze_mock_asia(p)
        except Exception as e:  # noqa: BLE001
            res = analyze_mock_asia(p)
            res["model"] = "asia-fallback-mock"
            print(f"[asia-analyze] {p.id} 失败回退 mock：{e}", flush=True)
        return p.id, res

    results: list[tuple[str, dict]] = []
    if use_real and workers > 1 and total:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(one, p) for p in work]
            for i, fut in enumerate(as_completed(futs), 1):
                results.append(fut.result())
                if i % 10 == 0 or i == total:
                    print(f"[asia-analyze] {i}/{total}", flush=True)
    else:
        results = [one(p) for p in work]

    with session_scope() as s:
        for pid, res in results:
            s.merge(AsiaAnalysis(
                post_id=pid, lang=res["lang"], sentiment_label=res["sentiment_label"],
                sentiment_score=res["sentiment_score"], stance=res["stance"],
                quality_score=res["quality_score"], themes=res["themes"],
                tldr_zh=res["tldr_zh"], tldr_en=res["tldr_en"],
                bull_points_zh=res["bull_points_zh"], bull_points_en=res["bull_points_en"],
                bear_points_zh=res["bear_points_zh"], bear_points_en=res["bear_points_en"],
                model=res["model"], analyzed_at=dt.datetime.utcnow(),
            ))
    print(f"[asia-analyze] 完成 {total} 帖。", flush=True)
    return total


# ----------------------------- 全量情绪打分（DeepSeek flash，便宜，供每日时间序列） -----------------------------
SYSTEM_FLASH = """你是金融舆情情绪打分器。下面是若干条来自日本/韩国/台湾散户的股票讨论帖（日文/韩文/繁中，可能含黑话与反讽）。给**每一条**打一个情绪分：-1.0(极度看空) 到 +1.0(极度看多)，0=中性/无关/灌水。台股黑话：歐印/航海王/起飛=看多，套牢/畢業/水餃/違約交割=看空；用调侃语气唱多通常是反讽=看空。只输出一个 JSON 数组，每个元素 {"i": 序号, "s": 分数}，序号必须与输入一一对应，不要任何多余文字。"""


def _cjk_score(market: str, text: str, label) -> float:
    """无 key 时的确定性兜底分。"""
    if label in LABEL_PRIOR:
        return LABEL_PRIOR[label]
    bull, bear = _kw_for(market)
    nb, nr = _count(bull, text), _count(bear, text)
    return round((nb - nr) / (nb + nr), 2) if nb + nr else 0.0


def score_all_flash(batch_size: int = 12, workers: int = 8, only_new: bool = True) -> int:
    """用 DeepSeek flash(LOW) 给**全部** asia_posts 批量打情绪分 → asia_posts.sentiment。
    便宜+批量(每调一次打 batch_size 帖)，供「每日情绪/变化」时间序列。缺 key 回退 CJK 启发式。"""
    use_real = available(LOW)
    with session_scope() as s:
        stmt = select(AsiaPost.id, AsiaPost.market, AsiaPost.ticker, AsiaPost.title, AsiaPost.body, AsiaPost.label)
        if only_new:
            stmt = stmt.where(AsiaPost.sentiment.is_(None))
        rows = s.execute(stmt).all()
    posts = [{"id": r[0], "market": r[1], "ticker": r[2],
              "text": f"{r[3] or ''} {r[4] or ''}".strip()[:280], "label": r[5]} for r in rows]
    total = len(posts)
    print(f"[asia-score] 待打分 {total} 帖（flash real={use_real}, batch={batch_size}）。", flush=True)
    if not total:
        return 0
    batches = [posts[i:i + batch_size] for i in range(0, total, batch_size)]

    def score_batch(batch: list[dict]) -> dict:
        if use_real:
            lines = []
            for i, p in enumerate(batch, 1):
                lbl = f"[{p['label']}]" if p["label"] else ""
                lines.append(f"{i}. ({p['market']}/{p['ticker']}){lbl} {p['text']}")
            try:
                data = messages_json(LOW, SYSTEM_FLASH, "\n".join(lines), max_tokens=900)
            except Exception as e:  # noqa: BLE001
                print(f"[asia-score] 批失败回退启发式：{e}", flush=True)
                data = None
            out: dict = {}
            if isinstance(data, list):
                for it in data:
                    try:
                        idx = int(it.get("i")); sc = float(it.get("s"))
                        if 1 <= idx <= len(batch):
                            out[batch[idx - 1]["id"]] = max(-1.0, min(1.0, round(sc, 3)))
                    except (TypeError, ValueError, AttributeError):
                        continue
            for p in batch:  # 缺失项兜底
                out.setdefault(p["id"], _cjk_score(p["market"], p["text"], p["label"]))
            return out
        return {p["id"]: _cjk_score(p["market"], p["text"], p["label"]) for p in batch}

    results: dict = {}
    if use_real and workers > 1:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(score_batch, b) for b in batches]
            for i, fut in enumerate(as_completed(futs), 1):
                results.update(fut.result())
                if i % 10 == 0 or i == len(batches):
                    print(f"[asia-score] {i}/{len(batches)} 批", flush=True)
    else:
        for b in batches:
            results.update(score_batch(b))

    with session_scope() as s:
        for pid, sc in results.items():
            s.execute(update(AsiaPost).where(AsiaPost.id == pid).values(sentiment=sc))
    print(f"[asia-score] 完成 {len(results)} 帖打分。", flush=True)
    return len(results)


# ----------------------------- 每格汇总（overview） -----------------------------
SYSTEM_SUMM = """你是亚洲股市舆情主编。下面是某市场散户对某只股票的若干条帖子结论（含情绪与多空论据）。请综述成**两段**：第一段简体中文（<=120字），第二段英文（<=80词）。客观概括散户整体情绪倾向、主要看多/看空理由与分歧点，不加投资建议。用「===EN===」分隔中英两段，不要其它多余文字。"""


def _mood_key(score: float) -> str:
    return "bull" if score > 0.2 else "bear" if score < -0.2 else ("mixed" if abs(score) <= 0.05 else "neutral")


def summarize_asia(mock: bool = False) -> int:
    use_real = (not mock) and available(MID)
    names = _name_map()
    n = 0
    with session_scope() as s:
        rows = s.execute(
            select(AsiaPost, AsiaAnalysis).join(AsiaAnalysis, AsiaAnalysis.post_id == AsiaPost.id)
        ).all()
        by: dict[tuple, list] = {}
        for p, a in rows:
            by.setdefault((p.market, p.ticker, p.source), []).append((p, a))
        # 同一格可能有多 source（罕见）；按 (market,ticker) 合并
        merged: dict[tuple, list] = {}
        src_of: dict[tuple, str] = {}
        for (mk, tk, src), items in by.items():
            merged.setdefault((mk, tk), []).extend(items)
            src_of[(mk, tk)] = src
        total_posts = {}
        for p in s.execute(select(AsiaPost)).scalars().all():
            total_posts[(p.market, p.ticker)] = total_posts.get((p.market, p.ticker), 0) + 1

        # 派生汇总表：全量重算（仿 rollups），先清空再插，避免 (market,ticker) 唯一约束冲突。
        s.execute(delete(AsiaTickerSummary))
        for (mk, tk), items in merged.items():
            scores = [a.sentiment_score for _, a in items]
            bull = sum(1 for _, a in items if a.stance == "bull")
            bear = sum(1 for _, a in items if a.stance == "bear")
            neu = len(items) - bull - bear
            mood = round(sum(scores) / len(scores), 3) if scores else 0.0
            # 取质量高的帖的论点做代表
            items.sort(key=lambda x: x[1].quality_score, reverse=True)
            top_bull_zh, top_bull_en, top_bear_zh, top_bear_en, themes = [], [], [], [], []
            for _, a in items:
                for z in (a.bull_points_zh or []):
                    if z and z not in top_bull_zh and len(top_bull_zh) < 4:
                        top_bull_zh.append(z)
                for e in (a.bull_points_en or []):
                    if e and e not in top_bull_en and len(top_bull_en) < 4:
                        top_bull_en.append(e)
                for z in (a.bear_points_zh or []):
                    if z and z not in top_bear_zh and len(top_bear_zh) < 4:
                        top_bear_zh.append(z)
                for e in (a.bear_points_en or []):
                    if e and e not in top_bear_en and len(top_bear_en) < 4:
                        top_bear_en.append(e)
                for th in (a.themes or []):
                    if th not in themes:
                        themes.append(th)

            ov_zh, ov_en = _overview(mk, tk, names.get(tk, tk), items, bull, bear, neu, mood, use_real)
            tot = total_posts.get((mk, tk), len(items))
            s.add(AsiaTickerSummary(
                market=mk, ticker=tk, source=src_of.get((mk, tk), ""),
                post_count=tot, analyzed_count=len(items),
                bull_pct=round(100 * bull / len(items), 1), bear_pct=round(100 * bear / len(items), 1),
                neutral_pct=round(100 * neu / len(items), 1), mood_score=mood, mood_label=_mood_key(mood),
                overview_zh=ov_zh, overview_en=ov_en,
                top_bull_zh=top_bull_zh, top_bull_en=top_bull_en,
                top_bear_zh=top_bear_zh, top_bear_en=top_bear_en, top_themes=themes[:5],
                updated_at=dt.datetime.utcnow(),
            ))
            n += 1
    print(f"[asia-summarize] 写入 {n} 格汇总（real={use_real}）。")
    return n


def _overview(mk, tk, name_zh, items, bull, bear, neu, mood, use_real) -> tuple[str, str]:
    tot = len(items)
    tendency = "偏多" if mood > 0.2 else "偏空" if mood < -0.2 else "分歧"
    if use_real:
        bullets = "\n".join(f"- [{a.stance}] {a.tldr_zh}" for _, a in items[:12])
        user = f"市场:{MARKET_NAME.get(mk, mk)} 标的:{name_zh}({tk}) 多{bull}/空{bear}/中{neu}\n{bullets}"
        # MID 是推理模型，reasoning 会吃掉 token 预算；给足额度，且偶发返回空 → 重试一次再退模板。
        for attempt in range(2):
            try:
                txt = (chat(MID, SYSTEM_SUMM, user, max_tokens=2200) or "").strip()
            except Exception as e:  # noqa: BLE001
                print(f"[asia-summarize] {mk}:{tk} overview LLM 失败：{e}")
                break
            if txt:
                if "===EN===" in txt:
                    zh, en = txt.split("===EN===", 1)
                    if zh.strip() and en.strip():
                        return zh.strip()[:600], en.strip()[:600]
                else:
                    return txt[:600], txt[:600]
        print(f"[asia-summarize] {mk}:{tk} overview 返回空，用模板兜底。")
    zh = f"{name_zh}在{MARKET_NAME.get(mk, mk)}散户中整体情绪{tendency}（看多{bull}/看空{bear}/中性{neu}，共{tot}帖分析）。"
    en = f"{tk}: {MARKET_NAME.get(mk, mk)} retail leans {('bullish' if mood>0.2 else 'bearish' if mood<-0.2 else 'mixed')} ({bull} bull / {bear} bear / {neu} neutral of {tot})."
    return zh, en


if __name__ == "__main__":
    import sys
    m = "--mock" in sys.argv
    run_asia_analyze(mock=m)
    summarize_asia(mock=m)
