"""X(Twitter) 推文情绪打分 —— DeepSeek flash 批量（写云端 tw_tweet_sentiment）。

给每条被映射到某美股的推文（tw_tweet_topic 命中的、tw_tweet 正文）打情绪分 s ∈ [-1, 1]，
便宜+批量（每调一次打 batch_size 条）。**情绪是推文级**（PK=tweet_id），后续每日 rollup 再按
tw_tweet_topic 把该推文归到它提到的各标的。

⚠ 写**云端**：tw_* 都在 Supabase（不在 dev.db）。默认 .env 的 DATABASE_URL 指向云端即写云端；
tw_tweet_sentiment 不在 models.py（仓库外加载的表），故用原生 SQL 读写、ON CONFLICT 幂等增量。
"""
from __future__ import annotations

import datetime as dt
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import text

from ..common.db import engine
from ..common.llm import LOW, available, messages_json, model_label

SYSTEM = (
    "你是金融舆情情绪打分器。下面是若干条提到某只美股的推文(X/Twitter，多为英文，也有中/日/韩；"
    "含金融黑话、反讽、表情符号)。给**每一条**打一个情绪分 s：-1.0(极度看空) 到 +1.0(极度看多)，"
    "0=中性/与该股无关/纯新闻转述/灌水。\n"
    "英文黑话：to the moon/🚀/LFG/calls/long/load up/buy the dip/diamond hands=看多；"
    "puts/short/dump/bagholder/rug/dead cat bounce/overvalued/sell=看空；用浮夸语气唱多通常是反讽=看空。\n"
    "只输出一个 JSON 数组，每个元素 {\"i\": 序号, \"s\": 分数}，序号与输入一一对应，不要任何多余文字。"
)


# 前十帖数但缺 X 的大票（vertical_topic_metadata.json 漏收其 cashtag）：
# 只**打分**它们的 $cashtag 推文（写 tw_tweet_sentiment）；「推文→标的」归属在 kol_sentiment 本地 rollup
# 里按 cashtag 临时算，**不写**云端共享表 tw_tweet_topic（不污染共享映射、避免推断数据入库）。
MEGACAP = {
    "NVDA": ["nvda"], "GOOGL": ["googl", "goog"], "MSFT": ["msft"], "MU": ["mu"],
    "TSLA": ["tsla"], "AMD": ["amd"], "AMZN": ["amzn"], "BABA": ["baba"],
    "AVGO": ["avgo"], "HOOD": ["hood"],
}


def megacap_regex(tags: list[str] | None = None) -> str:
    """Postgres `~*` 模式：匹配 $cashtag（$ 前后须非字母数字，避免 $NVDAX 这类）。tags=None → 全部大票。"""
    bodies = tags or [t for v in MEGACAP.values() for t in v]
    return r"(^|[^a-z0-9])\$(" + "|".join(bodies) + r")([^a-z0-9]|$)"


def _parse(data, k: int) -> dict[int, float]:
    out: dict[int, float] = {}
    if not isinstance(data, list):
        return out
    for el in data:
        if not isinstance(el, dict):
            continue
        try:
            i = int(el.get("i"))
            s = float(el.get("s"))
        except (TypeError, ValueError):
            continue
        if 0 <= i < k:
            out[i] = max(-1.0, min(1.0, s))
    return out


def _candidates(only_new: bool, limit: int | None) -> list[tuple[str, str]]:
    """被映射到标的的去重推文（tw_tweet_topic）⋈ 正文；only_new 跳过已打分的。"""
    # 候选 = tw_tweet_topic 命中的推文（原有）∪ 大票 $cashtag 命中的推文（新增，只读匹配）。
    sql = (
        "SELECT t.tweet_id, t.text FROM tw_tweet t WHERE t.text IS NOT NULL "
        "AND (EXISTS (SELECT 1 FROM tw_tweet_topic tt WHERE tt.tweet_id = t.tweet_id) "
        "     OR t.text ~* :mega) "
    )
    params = {"mega": megacap_regex()}
    if only_new:
        sql += "AND NOT EXISTS (SELECT 1 FROM tw_tweet_sentiment s WHERE s.tweet_id = t.tweet_id) "
    sql += "ORDER BY t.tweet_id"
    if limit:
        sql += f" LIMIT {int(limit)}"
    with engine.connect() as c:
        return [(r[0], (r[1] or "")[:300]) for r in c.execute(text(sql), params)]


def score(batch_size: int = 20, workers: int = 8, only_new: bool = True, limit: int | None = None) -> int:
    if not available(LOW):
        print("[tw-sentiment] 无 DeepSeek key（DEEPSEEK_API_KEY），跳过。", flush=True)
        return 0
    cand = _candidates(only_new, limit)
    total = len(cand)
    label = model_label(LOW)
    print(f"[tw-sentiment] 待打分 {total:,} 条推文（flash {label}, batch={batch_size}, workers={workers}）", flush=True)
    if not total:
        return 0

    batches = [cand[i:i + batch_size] for i in range(0, total, batch_size)]
    now = dt.datetime.utcnow()
    done = fail = 0
    buf: list[dict] = []

    ins = text(
        "INSERT INTO tw_tweet_sentiment (tweet_id, sentiment, model, tagged_at) "
        "VALUES (:tweet_id, :sentiment, :model, :tagged_at) ON CONFLICT (tweet_id) DO NOTHING"
    )

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with engine.begin() as c:
            c.execute(ins, buf)
        done += len(buf)
        buf.clear()

    def _work(batch: list[tuple[str, str]]):
        user = "\n".join(f"[{i}] {txt}" for i, (_id, txt) in enumerate(batch))
        data = messages_json(LOW, SYSTEM, user, max_tokens=900)
        scores = _parse(data, len(batch))
        return [(batch[i][0], scores.get(i, 0.0)) for i in range(len(batch))], (len(scores) == 0)

    t0 = now
    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, b) for b in batches]
        for n, fut in enumerate(as_completed(futs), 1):
            try:
                rows, empty = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [tw-sentiment] ✗ {str(e)[:90]}", flush=True)
                continue
            if empty:
                fail += 1  # 整批解析失败：计 fail、不落 0 分污染
                continue
            for tid, s in rows:
                buf.append({"tweet_id": tid, "sentiment": s, "model": label, "tagged_at": now})
            if len(buf) >= 800:
                _flush()
            if n % 50 == 0:
                print(f"  [tw-sentiment] …{n}/{len(batches)} 批（done={done:,}+buf{len(buf)} fail={fail}）", flush=True)
    _flush()
    print(f"[tw-sentiment] 完成 {done:,} 条（失败批 {fail}）", flush=True)
    return done


if __name__ == "__main__":
    score(limit=60)
