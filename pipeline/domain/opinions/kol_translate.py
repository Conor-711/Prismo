"""KOL 原帖 · 完整忠实翻译（标的页「按视角 · 原帖流」的「译」选项数据）。

方案A 下正文展示**原帖原文**；本步给每条被展示的原帖烤一份**完整忠实翻译**(zh+en)，写回
`kol_refined.trans_zh/trans_en`。与「提炼(kol_refine)」彻底分开：

- `quote` = kol_refine 产的「最能代表其观点的一句」(≤50字 soundbite) —— **会压缩**，只配做可信度引文，
  不是翻译；
- `trans` = 本步产的**逐句直译、等篇幅、不概括、不删减**的全文翻译 —— 用户点「译」看的就是它。

要点：
- 只翻译**会被展示**的项：取 kol_refine 同一 top-N 候选，且必须已在 `kol_refined`(=已被提炼/展示)。
- 增量：已有 `trans_zh` 的默认跳过(`--force` 重译)。
- 同一 source+item 的原文翻译与 ticker 无关：复用已有兄弟行译文；新翻译也只调用一次并回填全部 ticker 行。
- 默认按 Qwen LOW → DeepSeek low → Gemini 兜底。覆盖 reddit / x / xueqiu / toss / yahoojp；YouTube 复用 `yt_analysis` 双语摘要、无需翻译。

⚠ 本地测试：`DATABASE_URL=sqlite:///./data/dev.db` 直接写本地快照(sqlite 自动补列)；
上云需先在云端加 `trans_zh/trans_en` 列(迁移)，再跑同一步 + cloud-pull。
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
import os
import re

from sqlalchemy import bindparam, text, update

from ...common import deepseek, gemini, llm
from ...common.config import settings
from ...common.db import engine, session_scope
from ...common.models import KolRefined
from .kol_refine import DEFAULT_PER_SOURCE, DEFAULT_SINCE_DAYS, TEXT_SOURCES, _load

# 强约束：①不压缩(逐句、等篇幅、不概括删减) ②按股票/投资语境**意译**行话俚语，不逐字机翻。
TRANS_SYSTEM = (
    "你是股票投资社区帖子的翻译器，既不是摘要器、也不是逐字机翻。给定某社区用户/博主关于一只美股的"
    "帖子原文(语言可能为中/英/日/韩)，把它**完整翻译**成自然、地道的中文和英文。硬性要求：\n"
    "1) 逐句翻译，原文有几句、译文就有几句，保持相当篇幅与段落/换行；不概括、不提炼、不合并、不删细节、不加原文没有的内容；\n"
    "2) 保留全部信息：数字、日期、价格、代码($NVDA 等)、公司名、事件、语气、强调；\n"
    "3) **按股票/投资语境意译行话与俚语，绝不字面直译**。常见(英→中)：(in/be) green=上涨/盈利(赚钱)、"
    "(in) red=下跌/亏损、bag/bagholder=套牢(盘)、to the moon=暴涨、tendies=收益、DD=深度研究、YOLO=梭哈、"
    "puts/calls=看跌/看涨期权、diamond hands=死拿不卖、paper hands=拿不住就割、printing money=疯狂赚钱、dip=回调。"
    "⚠ 涨跌/盈亏的颜色**一律译成涨跌/盈亏本身**：green / turn green / go green = 上涨/盈利/扭亏(写「转涨」「扭亏」「回到盈利」)、"
    "red / in the red = 下跌/亏损；中文译文里**绝不用「绿/红」表示涨跌**(尤其禁止「转绿/翻绿/飘绿」)——美股绿涨红跌、与 A 股相反，直译颜色会把意思弄反；\n"
    "4) 可去掉转发前缀(RT @xxx:)、@提及堆叠、纯链接等噪声，但正文一字不少；\n"
    "5) 若某语言已是原文语言，该字段输出清理后的原文本身。\n"
    "仅输出 JSON，不要多余文字：{\"zh\":\"完整自然的中文翻译\",\"en\":\"full natural English translation\"}"
)


def _ensure_table() -> None:
    """建表(checkfirst)；本地 sqlite 自动补 trans 列(云端 postgres 由迁移负责，不在此自动 DDL)。"""
    KolRefined.__table__.create(engine, checkfirst=True)
    if engine.dialect.name == "sqlite":
        with engine.begin() as conn:
            cols = {r[1] for r in conn.exec_driver_sql("PRAGMA table_info(kol_refined)").fetchall()}
            for c in ("trans_zh", "trans_en"):
                if c not in cols:
                    conn.exec_driver_sql(f"ALTER TABLE kol_refined ADD COLUMN {c} TEXT DEFAULT ''")
                    print(f"[kol-translate] dev.db += {c}", flush=True)


def _norm(d: dict | None) -> dict | None:
    if not isinstance(d, dict):
        return None
    zh = str(d.get("zh") or "").strip()[:4000]
    en = str(d.get("en") or "").strip()[:4000]
    if not zh and not en:
        return None
    return {"zh": zh or en, "en": en or zh}


def _parse_text_translation(text: str) -> dict | None:
    """Parse a plain text fallback in the form `ZH: ... EN: ...`."""
    if not text:
        return None
    m = re.search(r"(?:^|\n)\s*ZH\s*[:：]\s*(.*?)\s*(?:\n\s*EN\s*[:：]\s*|\Z)(.*)", text, re.S | re.I)
    if not m:
        return None
    zh = (m.group(1) or "").strip()
    en = (m.group(2) or "").strip()
    return _norm({"zh": zh, "en": en})


def _provider_order() -> list[str]:
    raw = os.environ.get("KOL_TRANSLATE_PROVIDERS", "qwen,deepseek,gemini")
    order: list[str] = []
    for p in raw.split(","):
        name = p.strip().lower()
        if name in {"qwen", "deepseek", "gemini"} and name not in order:
            order.append(name)
    return order or ["qwen", "deepseek", "gemini"]


def _provider_available(provider: str) -> bool:
    if provider == "qwen":
        return llm.available(llm.LOW)
    if provider == "deepseek":
        return settings.has_deepseek
    if provider == "gemini":
        return settings.has_gemini
    return False


def _provider_label(provider: str) -> str:
    if provider == "qwen":
        return llm.model_label(llm.LOW)
    if provider == "deepseek":
        return f"deepseek:{settings.deepseek_model_low}"
    if provider == "gemini":
        return f"gemini:{settings.gemini_model}"
    return provider


def _messages_json_with(provider: str, system: str, user: str, *, max_tokens: int) -> dict | None:
    if not _provider_available(provider):
        return None
    try:
        if provider == "qwen":
            return llm.messages_json(llm.LOW, system, user, max_tokens=max_tokens)
        if provider == "deepseek":
            return deepseek.messages_json(system, user, model=settings.deepseek_model_low, max_tokens=max_tokens)
        if provider == "gemini":
            return gemini.messages_json(system, user, model=settings.gemini_model, max_tokens=max_tokens)
    except Exception:
        return None
    return None


def _chat_with(provider: str, system: str, user: str, *, max_tokens: int, temperature: float = 0.1) -> str:
    if not _provider_available(provider):
        return ""
    try:
        if provider == "qwen":
            return llm.chat(llm.LOW, system, user, max_tokens=max_tokens, temperature=temperature)
        if provider == "deepseek":
            return deepseek.chat(
                system,
                user,
                model=settings.deepseek_model_low,
                max_tokens=max_tokens,
                temperature=temperature,
            )
        if provider == "gemini":
            return gemini.chat(
                system,
                user,
                model=settings.gemini_model,
                max_tokens=max_tokens,
                temperature=temperature,
            )
    except Exception:
        return ""
    return ""


def _refined_state(sources: list[str], only: set[str] | None) -> dict[tuple[str, str, str], bool]:
    """已在 kol_refined(=已展示)的键 → 是否已译。只译已提炼项，避免浪费在不展示的帖上。"""
    stmt = text(
        "SELECT source, item_id, ticker, COALESCE(trans_zh,'') AS tz, COALESCE(trans_en,'') AS te "
        "FROM kol_refined WHERE source IN :ss"
    ).bindparams(bindparam("ss", expanding=True))
    with session_scope() as s:
        rows = s.execute(stmt, {"ss": sources}).all()
    out: dict[tuple[str, str, str], bool] = {}
    for r in rows:
        tk = str(r[2])
        if only and tk.upper() not in only:
            continue
        out[(r[0], str(r[1]), tk.upper())] = bool(
            str(r[3] or "").strip() and str(r[4] or "").strip()
        )
    return out


def _translation_by_item(sources: list[str]) -> dict[tuple[str, str], dict[str, str]]:
    """Return one complete translation for each source item, independent of ticker."""
    stmt = text(
        "SELECT source, item_id, COALESCE(trans_zh,'') AS tz, COALESCE(trans_en,'') AS te "
        "FROM kol_refined WHERE source IN :ss "
        "AND TRIM(COALESCE(trans_zh,'')) <> '' AND TRIM(COALESCE(trans_en,'')) <> ''"
    ).bindparams(bindparam("ss", expanding=True))
    with session_scope() as s:
        rows = s.execute(stmt, {"ss": sources}).all()
    out: dict[tuple[str, str], dict[str, str]] = {}
    for r in rows:
        out.setdefault(
            (str(r[0]), str(r[1])),
            {"zh": str(r[2]).strip(), "en": str(r[3]).strip()},
        )
    return out


def _write_translations(items: list[tuple[dict, dict]]) -> int:
    """Write translations to every ticker row represented by each grouped item."""
    if not items:
        return 0
    written = 0
    with session_scope() as s:
        for r, norm in items:
            tickers = r.get("_translation_tickers") or [(r.get("ticker") or "").upper()]
            for ticker in tickers:
                s.execute(
                    update(KolRefined)
                    .where(
                        KolRefined.source == r["source"],
                        KolRefined.item_id == str(r["item_id"]),
                        KolRefined.ticker == ticker,
                    )
                    .values(trans_zh=norm["zh"], trans_en=norm["en"])
                )
                written += 1
    return written


def translate(sources: list[str] | None = None, per_source: int = DEFAULT_PER_SOURCE,
              only: list[str] | None = None, force: bool = False, workers: int = 6,
              since_days: int = DEFAULT_SINCE_DAYS) -> int:
    _ensure_table()
    providers = [p for p in _provider_order() if _provider_available(p)]
    if not providers:
        print("[kol-translate] 无可用翻译 provider(Qwen/DeepSeek/Gemini)，跳过。", flush=True)
        return 0
    srcs = [s for s in (sources or list(TEXT_SOURCES)) if s in TEXT_SOURCES]
    only_set = {t.strip().upper() for t in only} if only else None

    have = _refined_state(srcs, only_set)  # 已展示项 → 是否已译
    known_by_item = {} if force else _translation_by_item(srcs)
    reusable: list[tuple[dict, dict]] = []
    grouped: dict[tuple[str, str], dict] = {}
    for src in srcs:
        for r in _load(src, per_source, only_set, since_days):
            key = (r["source"], str(r["item_id"]), (r["ticker"] or "").upper())
            if key not in have:          # 只译已被提炼/展示的原帖
                continue
            if not force and have[key]:  # 已译 → 增量跳过
                continue
            item_key = (r["source"], str(r["item_id"]))
            ticker = (r["ticker"] or "").upper()
            if item_key in known_by_item:
                copy = dict(r)
                copy["_translation_tickers"] = [ticker]
                reusable.append((copy, known_by_item[item_key]))
                continue
            if item_key not in grouped:
                grouped[item_key] = dict(r)
                grouped[item_key]["_translation_tickers"] = []
            grouped[item_key]["_translation_tickers"].append(ticker)

    reused = _write_translations(reusable)
    plan = list(grouped.values())
    total = len(plan)
    target_rows = sum(len(r["_translation_tickers"]) for r in plan)
    label = " -> ".join(_provider_label(p) for p in providers)
    print(f"[kol-translate] 计划 {total} 条唯一原帖 / {target_rows} 个 ticker 行"
          f"(复用已有译文 {reused} 行；源 {','.join(srcs)}, per_source={per_source}, "
          f"近 {since_days} 天, model={label}, force={force})", flush=True)
    if not total:
        return reused

    done = reused
    done_items = fail = skip = 0
    buf: list[tuple[dict, dict]] = []

    def _flush() -> None:
        nonlocal done, done_items
        if not buf:
            return
        done += _write_translations(buf)
        done_items += len(buf)
        buf.clear()

    def _work(r: dict) -> tuple[dict, dict | None]:
        src = str(r["txt"] or "").strip()
        user_full = f"把下面这条帖子原文完整翻译成中文和英文(不要压缩)：\n\n{src[:2000]}"
        for provider in providers:
            norm = _norm(_messages_json_with(provider, TRANS_SYSTEM, user_full, max_tokens=2000))
            if norm:
                return r, norm

        simple_system = (
            "Translate the stock community post into Chinese and English. Output only JSON: "
            '{"zh":"中文完整翻译","en":"full English translation"}.'
        )
        simple_user = f"Post:\n{src[:1800]}"
        for provider in providers:
            norm = _norm(_messages_json_with(provider, simple_system, simple_user, max_tokens=1800))
            if norm:
                return r, norm

        plain_system = "Translate the stock community post fully. Do not summarize."
        plain_user = f"Post:\n{src[:1800]}\n\nOutput exactly:\nZH:\n<Chinese translation>\nEN:\n<English translation>"
        for provider in providers:
            norm = _parse_text_translation(
                _chat_with(provider, plain_system, plain_user, max_tokens=1800, temperature=0.1)
            )
            if norm:
                return r, norm

        return r, None

    with ThreadPoolExecutor(max_workers=max(1, workers)) as ex:
        futs = [ex.submit(_work, r) for r in plan]
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                r, norm = fut.result()
            except Exception as e:  # noqa: BLE001
                fail += 1
                if fail <= 8:
                    print(f"  [kol-translate] ✗ {str(e)[:90]}", flush=True)
                continue
            if norm is None:
                skip += len(r["_translation_tickers"])
                continue
            buf.append((r, norm))
            if len(buf) >= 40:  # 增量落库：中途被杀也不丢已完成的
                _flush()
            if i % 50 == 0:
                pending_rows = sum(len(item[0]["_translation_tickers"]) for item in buf)
                print(f"  [kol-translate] …{i}/{total} unique"
                      f"(rows={done}+buf{pending_rows} skip={skip} fail={fail})", flush=True)
    _flush()

    print(f"[kol-translate] 完成 {done} 行 / {done_items} 条唯一原帖"
          f"(跳过空 {skip} 行，失败 {fail} 条原帖)", flush=True)
    return done


if __name__ == "__main__":
    translate(only=["NVDA"], per_source=8)
