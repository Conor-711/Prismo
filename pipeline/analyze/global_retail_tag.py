"""全球散户多区看板——DeepSeek flash 全量打标（不使用千问）。

给每条 gr_post（日韩台散户讨论某美股）批量打情绪分 sentiment(-1..1)，并由分数派生
stance(bull/bear/neutral)。便宜+批量(每调一次打 batch_size 帖)，缺 key 回退 CJK 启发式。
内置 CJK 关键词启发式作为无 key / 单项失败兜底。
"""
from __future__ import annotations

from sqlalchemy import select, update

from ..common.db import session_scope
from ..common.llm import LOW, available, messages_json
from ..common.models import GrPost

JA_BULL = ["買い", "買いたい", "強気", "上昇", "上げ", "急騰", "ホールド", "期待", "強い",
           "最高値", "買い増し", "押し目", "仕込み", "上方修正", "好決算"]
JA_BEAR = ["売り", "売りたい", "弱気", "下落", "暴落", "損切り", "危険", "バブル", "過大評価",
           "下げ", "弱い", "高値掴み", "撤退", "下方修正"]
KO_BULL = ["매수", "사자", "강세", "상승", "급등", "호재", "가즈아", "존버", "텐배거",
           "우상향", "가자", "사라", "물타기", "반등", "신고가"]
KO_BEAR = ["매도", "팔자", "약세", "하락", "폭락", "손절", "악재", "거품", "고점",
           "비싸", "위험", "떨어", "손실", "물렸"]
ZH_BULL = ["看多", "做多", "買進", "買超", "航海王", "歐印", "起飛", "噴出", "噴", "穩了",
           "抱緊", "上看", "突破", "漲停", "多單", "加碼", "上攻", "創高", "嗨"]
ZH_BEAR = ["看空", "做空", "賣出", "賣超", "套牢", "畢業", "崩", "跌停", "認賠", "水餃",
           "殺", "空單", "違約交割", "回檔", "崩盤", "停損", "破底", "套"]
LABEL_PRIOR = {
    "強く買いたい": 0.9, "買いたい": 0.5, "中立": 0.0, "売りたい": -0.5, "強く売りたい": -0.9,
}


def _kw_for(region: str) -> tuple[list[str], list[str]]:
    if region == "jp":
        return JA_BULL, JA_BEAR
    if region == "kr":
        return KO_BULL, KO_BEAR
    return ZH_BULL, ZH_BEAR


def _count(words: list[str], text: str) -> int:
    return sum(text.count(w) for w in words)


def _cjk_score(region: str, text: str, label: str | None) -> float:
    if label in LABEL_PRIOR:
        return LABEL_PRIOR[label]
    bull, bear = _kw_for(region)
    nb, nr = _count(bull, text), _count(bear, text)
    return round((nb - nr) / (nb + nr), 2) if nb + nr else 0.0

SYSTEM_GR = """你是金融舆情情绪打分器。下面是若干条来自日本(Yahoo Finance)/韩国(Naver)/台湾(PTT)散户、讨论**某只美股**的帖子（日文/韩文/繁体中文，可能含黑话与反讽）。给**每一条**打一个情绪分 s：-1.0(极度看空) 到 +1.0(极度看多)，0=中性/无关/灌水/纯新闻。
黑话提示：日「押し目/仕込み/買い増し」=看多，「高値掴み/撤退/損切り」=看空；韩「가즈아/존버/우상향/물타기」=看多，「손절/물렸/거품/고점」=看空；台「歐印/航海王/起飛/噴/穩了」=看多，「套牢/畢業/水餃/違約交割/停損」=看空；用调侃语气唱多通常是反讽=看空。
只输出一个 JSON 数组，每个元素 {"i": 序号, "s": 分数}，序号与输入一一对应，不要任何多余文字。"""


def _stance(score: float) -> str:
    return "bull" if score > 0.15 else "bear" if score < -0.15 else "neutral"


def tag_all(batch_size: int = 15, workers: int = 8, only_new: bool = True,
            only: list[str] | None = None, sources: list[str] | None = None,
            regions: list[str] | None = None) -> int:
    """DeepSeek flash 给全部 gr_post 打情绪分 + 派生 stance。only_new 只打未打的。"""
    use_real = available(LOW)
    only_set = {x.strip().upper() for x in only if x.strip()} if only else None
    source_set = {x.strip() for x in sources if x.strip()} if sources else None
    region_set = {x.strip() for x in regions if x.strip()} if regions else None
    with session_scope() as s:
        stmt = select(GrPost.id, GrPost.region, GrPost.ticker, GrPost.title, GrPost.body, GrPost.label)
        if only_new:
            stmt = stmt.where(GrPost.sentiment.is_(None))
        if only_set:
            stmt = stmt.where(GrPost.ticker.in_(only_set))
        if source_set:
            stmt = stmt.where(GrPost.source.in_(source_set))
        if region_set:
            stmt = stmt.where(GrPost.region.in_(region_set))
        rows = s.execute(stmt).all()
    posts = [{"id": r[0], "region": r[1], "ticker": r[2],
              "text": f"{r[3] or ''} {r[4] or ''}".strip()[:280], "label": r[5]} for r in rows]
    total = len(posts)
    scope = []
    if only_set:
        scope.append("ticker=" + ",".join(sorted(only_set)))
    if source_set:
        scope.append("source=" + ",".join(sorted(source_set)))
    if region_set:
        scope.append("region=" + ",".join(sorted(region_set)))
    print(f"[gr-tag] 待打标 {total} 帖（flash real={use_real}, batch={batch_size}"
          f"{'; ' + '; '.join(scope) if scope else ''}）。", flush=True)
    if not total:
        return 0
    batches = [posts[i:i + batch_size] for i in range(0, total, batch_size)]

    def score_batch(batch: list[dict]) -> dict:
        if use_real:
            lines = []
            for i, p in enumerate(batch, 1):
                lbl = f"[{p['label']}]" if p["label"] else ""
                lines.append(f"{i}. ({p['region']}/{p['ticker']}){lbl} {p['text']}")
            try:
                data = messages_json(LOW, SYSTEM_GR, "\n".join(lines), max_tokens=1000)
            except Exception as e:  # noqa: BLE001
                print(f"[gr-tag] 批失败回退启发式：{e}", flush=True)
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
            for p in batch:  # 缺失项 → CJK 启发式兜底
                out.setdefault(p["id"], _cjk_score(p["region"], p["text"], p["label"]))
            return out
        return {p["id"]: _cjk_score(p["region"], p["text"], p["label"]) for p in batch}

    results: dict = {}
    if use_real and workers > 1:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(score_batch, b) for b in batches]
            for i, fut in enumerate(as_completed(futs), 1):
                results.update(fut.result())
                if i % 10 == 0 or i == len(batches):
                    print(f"[gr-tag] {i}/{len(batches)} 批", flush=True)
    else:
        for b in batches:
            results.update(score_batch(b))

    with session_scope() as s:
        for pid, sc in results.items():
            s.execute(update(GrPost).where(GrPost.id == pid).values(sentiment=sc, stance=_stance(sc)))
    print(f"[gr-tag] 完成 {len(results)} 帖打标。", flush=True)
    return len(results)


if __name__ == "__main__":
    tag_all()
