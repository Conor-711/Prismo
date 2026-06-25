"""KOL 原帖 · 完整忠实翻译（标的页「按视角 · 原帖流」的「译」选项数据）。

方案A 下正文展示**原帖原文**；本步给每条被展示的原帖烤一份**完整忠实翻译**(zh+en)，写回
`kol_refined.trans_zh/trans_en`。与「提炼(kol_refine)」彻底分开：

- `quote` = kol_refine 产的「最能代表其观点的一句」(≤50字 soundbite) —— **会压缩**，只配做可信度引文，
  不是翻译；
- `trans` = 本步产的**逐句直译、等篇幅、不概括、不删减**的全文翻译 —— 用户点「译」看的就是它。

要点：
- 只翻译**会被展示**的项：取 kol_refine 同一 top-N 候选，且必须已在 `kol_refined`(=已被提炼/展示)。
- 增量：已有 `trans_zh` 的默认跳过(`--force` 重译)。
- 便宜档(LOW=千问 qwen-flash)。覆盖 reddit / x / xueqiu；YouTube 复用 `yt_analysis` 双语摘要、无需翻译。

⚠ 本地测试：`DATABASE_URL=sqlite:///./data/dev.db` 直接写本地快照(sqlite 自动补列)；
上云需先在云端加 `trans_zh/trans_en` 列(迁移)，再跑同一步 + cloud-pull。
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import bindparam, text, update

from ..common import llm
from ..common.db import engine, session_scope
from ..common.models import KolRefined
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


def _refined_state(sources: list[str], only: set[str] | None) -> dict[tuple[str, str, str], bool]:
    """已在 kol_refined(=已展示)的键 → 是否已译。只译已提炼项，避免浪费在不展示的帖上。"""
    stmt = text(
        "SELECT source, item_id, ticker, COALESCE(trans_zh,'') AS tz "
        "FROM kol_refined WHERE source IN :ss"
    ).bindparams(bindparam("ss", expanding=True))
    with session_scope() as s:
        rows = s.execute(stmt, {"ss": sources}).all()
    out: dict[tuple[str, str, str], bool] = {}
    for r in rows:
        tk = str(r[2])
        if only and tk.upper() not in only:
            continue
        out[(r[0], str(r[1]), tk.upper())] = bool(str(r[3] or "").strip())
    return out


def translate(sources: list[str] | None = None, per_source: int = DEFAULT_PER_SOURCE,
              only: list[str] | None = None, force: bool = False, workers: int = 6,
              since_days: int = DEFAULT_SINCE_DAYS) -> int:
    _ensure_table()
    if not llm.available(llm.LOW):
        print("[kol-translate] 无 LOW 档 key(QWEN_API_KEY)，跳过。", flush=True)
        return 0
    srcs = [s for s in (sources or list(TEXT_SOURCES)) if s in TEXT_SOURCES]
    only_set = {t.strip().upper() for t in only} if only else None

    have = _refined_state(srcs, only_set)  # 已展示项 → 是否已译
    plan: list[dict] = []
    for src in srcs:
        for r in _load(src, per_source, only_set, since_days):
            key = (r["source"], str(r["item_id"]), (r["ticker"] or "").upper())
            if key not in have:          # 只译已被提炼/展示的原帖
                continue
            if not force and have[key]:  # 已译 → 增量跳过
                continue
            plan.append(r)

    total = len(plan)
    label = llm.model_label(llm.LOW)
    print(f"[kol-translate] 计划 {total} 条(源 {','.join(srcs)}, per_source={per_source}, "
          f"近 {since_days} 天, model={label}, force={force})", flush=True)
    if not total:
        return 0

    done = fail = skip = 0
    buf: list[tuple[dict, dict]] = []

    def _flush() -> None:
        nonlocal done
        if not buf:
            return
        with session_scope() as s:  # 主线程单写者 → 无 sqlite 锁竞争
            for r, norm in buf:
                s.execute(
                    update(KolRefined)
                    .where(KolRefined.source == r["source"],
                           KolRefined.item_id == str(r["item_id"]),
                           KolRefined.ticker == (r["ticker"] or "").upper())
                    .values(trans_zh=norm["zh"], trans_en=norm["en"])
                )
        done += len(buf)
        buf.clear()

    def _work(r: dict) -> tuple[dict, dict | None]:
        data = llm.messages_json(
            llm.LOW, TRANS_SYSTEM,
            f"把下面这条帖子原文完整翻译成中文和英文(不要压缩)：\n\n{r['txt'][:2000]}",
            max_tokens=2000)
        return r, _norm(data)

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
                skip += 1
                continue
            buf.append((r, norm))
            if len(buf) >= 40:  # 增量落库：中途被杀也不丢已完成的
                _flush()
            if i % 50 == 0:
                print(f"  [kol-translate] …{i}/{total}(done={done}+buf{len(buf)} skip={skip} fail={fail})", flush=True)
    _flush()

    print(f"[kol-translate] 完成 {done}(跳过空 {skip}，失败 {fail})", flush=True)
    return done


if __name__ == "__main__":
    translate(only=["NVDA"], per_source=8)
