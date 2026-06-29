"""YouTube 判断参数结构化抽取：从**已有** yt_analysis 的观点/论据里抽出
「时间周期 / 目标价位 / 关键位置」三项交易参数 → 本地 yt_judgment 表。

供 YouTube 作者页「① 标的判断」每条判断的结构化 chip（时间周期 / 目标价 / 关键位）。
**不重看视频、不重花 Gemini 配额**：只读 `yt_analysis`（Gemini/字幕已蒸馏好的 summary + key_points
+ 原始 price_target），跑 **LOW 档（qwen-flash，便宜）** 做一次纯文本抽取。信息其实就埋在那些
散文里（「预计到 2028」「突破牛旗 $52」「RSI 超买」）；这一步把它**结构化**出来。

**反臆造**：只抽**明确出现**的项，没提到就 null（多数视频只有方向、没有明确周期/关键位 → 大量 null 是对的）。
增量：已在 yt_judgment 的 video_id 跳过（`--force` 重跑）。直接读写**本地 dev.db**（同 youtube_digest 范式：
裸 sqlite3、绕开可能指向云端的 SQLAlchemy engine；该表不进 models.py，与 yt_digest 一致）。

用法：pipeline/.venv/bin/python -m pipeline.analyze.youtube_judgment [--force] [--only TICKER,...] [--workers N]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
from concurrent.futures import ThreadPoolExecutor, as_completed

from ..common import llm

DB = os.environ.get("PRICE_DB", os.path.join(os.path.dirname(__file__), "..", "..", "data", "dev.db"))

SYSTEM = (
    "你是金融观点结构化抽取器。给你一位分析者对某只美股的**已蒸馏**观点（摘要 + 论据要点，可能中英混合）"
    "和一个可能存在的目标价原文。请只抽取其中**明确出现**的三项交易参数；"
    "**只要原文没有明确给出，就填 null —— 绝不臆造、绝不自行推断或编造数字**：\n"
    "1) horizon 时间周期：作者给出的投资/持有期限或时间锚点（如『未来 6-12 个月』『长期·2028』『短线几周』"
    "『财报后』）。给中英各一句短语 horizon_zh / horizon_en（≤14 字 / ≤8 词）。没提到 → 两者皆 null。\n"
    "2) target 目标价位：作者给出的目标价或区间，规整成简洁形式（如『$800』『$1200–1600』『$50-60』）；"
    "语言无关、保留货币符号、多个取最主要的一个。没给 → null。\n"
    "3) key_levels 关键位置：作者提到的关键技术位——支撑 / 阻力 / 突破位 / 形态位 / 均线（如"
    "『支撑 $140 · 阻力 $160』『突破牛旗 $52』『站上 200 日均线』）。给中英各一句短语 "
    "key_levels_zh / key_levels_en。没提到 → 两者皆 null。\n"
    '严格只输出 JSON（不存在的字段值用 null，不要省略键）：'
    '{"horizon_zh":null,"horizon_en":null,"target":null,"key_levels_zh":null,"key_levels_en":null}'
)

_NULLISH = {"", "null", "none", "n/a", "na", "-", "无", "暂无", "未提及", "未提到", "没有", "不适用"}


def _clean(s, cap: int = 80) -> str | None:
    """规整一项抽取值：空 / 各种「无」→ None；否则裁剪长度。"""
    if s is None:
        return None
    t = str(s).strip()
    return None if t.lower() in _NULLISH else t[:cap]


def _points(raw) -> list[str]:
    try:
        a = json.loads(raw or "[]")
    except (json.JSONDecodeError, TypeError):
        return []
    return [str(x).strip() for x in a if str(x).strip()] if isinstance(a, list) else []


def _user(ticker: str, stance: str, summary: str, points: list[str], raw_target: str | None) -> str:
    parts = [f"标的：{ticker}", f"方向立场：{stance or '未知'}"]
    if summary:
        parts.append(f"观点摘要：{summary}")
    if points:
        parts.append("论据要点：\n" + "\n".join(f"- {p}" for p in points[:6]))
    if raw_target and raw_target.strip() and raw_target.strip().lower() != "null":
        parts.append(f"另：分析中提到的目标价原文 = {raw_target.strip()}（如确为目标价请规整后填入 target）")
    return "\n".join(parts)


def _ensure(con: sqlite3.Connection) -> None:
    con.execute(
        """CREATE TABLE IF NOT EXISTS yt_judgment (
             video_id TEXT PRIMARY KEY, ticker TEXT,
             horizon_zh TEXT, horizon_en TEXT,
             target TEXT,
             key_levels_zh TEXT, key_levels_en TEXT,
             model TEXT, tagged_at TEXT)"""
    )


def _extract(row) -> tuple[str, str, dict] | None:
    """单条 LLM 抽取（线程内只做网络，不碰 DB）。返回 (video_id, ticker, fields)；硬失败返回 None。"""
    vid, ticker, stance, s_zh, s_en, kp_zh, kp_en, raw_target = row
    summary = (s_zh or "").strip() or (s_en or "").strip()
    points = _points(kp_zh) or _points(kp_en)
    if not summary and not points:
        return vid, ticker, {}  # 无可抽内容 → 落空行（标记已处理、不再重试）
    user = _user(ticker, stance, summary, points, raw_target)
    data = None
    for _ in range(3):  # LOW 偶发 JSON 截断/None → 重试，绝不静默落空
        data = llm.messages_json(llm.LOW, SYSTEM, user, max_tokens=400)
        if isinstance(data, dict):
            break
    if not isinstance(data, dict):
        return None
    return vid, ticker, {
        "horizon_zh": _clean(data.get("horizon_zh"), 40),
        "horizon_en": _clean(data.get("horizon_en"), 60),
        "target": _clean(data.get("target"), 64),
        "key_levels_zh": _clean(data.get("key_levels_zh"), 80),
        "key_levels_en": _clean(data.get("key_levels_en"), 100),
    }


def run(force: bool = False, only: set[str] | None = None, workers: int = 8) -> int:
    if not llm.available(llm.LOW):
        print("[yt-judgment] ⚠ 缺 QWEN_API_KEY（LOW 档）→ 跳过")
        return 0
    con = sqlite3.connect(os.path.abspath(DB))
    _ensure(con)
    done = {r[0] for r in con.execute("SELECT video_id FROM yt_judgment").fetchall()} if not force else set()
    rows = con.execute(
        "SELECT video_id, ticker, stance, summary_zh, summary_en, key_points_zh, key_points_en, price_target "
        "FROM yt_analysis"
    ).fetchall()
    todo = [r for r in rows if r[0] not in done and (not only or (r[1] or "").upper() in only)]
    print(f"[yt-judgment] 计划 {len(todo)} 条（已有 {len(done)} / 共 {len(rows)}；model={llm.model_label(llm.LOW)}）", flush=True)
    if not todo:
        con.close()
        return 0

    now = dt.datetime.now(dt.timezone.utc).isoformat()
    label = llm.model_label(llm.LOW)
    ok = fail = withval = 0
    buf: list[tuple] = []

    def _flush() -> None:
        if not buf:
            return
        con.executemany(
            "INSERT OR REPLACE INTO yt_judgment "
            "(video_id,ticker,horizon_zh,horizon_en,target,key_levels_zh,key_levels_en,model,tagged_at) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            buf,
        )
        con.commit()
        buf.clear()

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_extract, r) for r in todo]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                out = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [yt-judgment] ✗ {str(e)[:90]}", flush=True)
                continue
            if out is None:
                fail += 1
                continue
            vid, ticker, f = out
            buf.append((vid, ticker, f.get("horizon_zh"), f.get("horizon_en"), f.get("target"),
                        f.get("key_levels_zh"), f.get("key_levels_en"), label, now))
            ok += 1
            if any(f.get(k) for k in ("horizon_zh", "target", "key_levels_zh")):
                withval += 1
            if len(buf) >= 40:
                _flush()
            if i % 100 == 0:
                print(f"  [yt-judgment] …{i}/{len(todo)}（ok={ok} 有值={withval} fail={fail}）", flush=True)
    _flush()
    print(f"[yt-judgment] 完成：{ok} 成功（其中 {withval} 抽到至少一项）/ {fail} 失败 → yt_judgment", flush=True)
    con.close()
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="重抽全部（默认只补未抽的）")
    ap.add_argument("--only", type=str, default=None, help="逗号分隔 ticker，只跑这些")
    ap.add_argument("--workers", type=int, default=8, help="LLM 并发数")
    a = ap.parse_args()
    run(force=a.force, only={x.strip().upper() for x in a.only.split(",")} if a.only else None, workers=a.workers)
