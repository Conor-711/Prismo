"use client";

// 首登 onboarding 向导（自然全屏页面，非卡片）。采集投资画像 5 维，顺序：
//   ① 关注赛道 ② 持有标的 ③ 持有习惯 ④ 投资年龄 ⑤ 投资金额。
// 完成时：① 写 user_profiles（saveProfile）② 标记 onboarded（markOnboarded → 门禁不再纠缠）
//         ③ 把所选持仓写进 user_collections 作为「追踪」（复用 addCollection）。
// 设计：DESIGN_LANGUAGE.md —— 近黑底 + 发丝边 + 青绿强调；不发光、不蓝紫；大气留白、居中内容列。
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { useAuth } from "@/components/auth/AuthProvider";
import { addCollection } from "@/lib/favorites";
import {
  loadProfile,
  saveProfile,
  markOnboarded,
  normalizeHabitRank,
  EXPERIENCE_KEYS,
  INTEREST_KEYS,
  HABIT_KEYS,
  SIZE_KEYS,
  type Experience,
  type HoldingHabit,
  type PortfolioSize,
} from "@/lib/profile";
import { INSTRUMENT_KINDS, type InstrumentKind } from "@/lib/instruments";

export interface OnbTicker {
  ticker: string;
  name_en: string;
  name_zh: string;
  kind: InstrumentKind;
}

// 5 个问答步（welcome=0、finish=6 不计入进度）：1 赛道 / 2 持仓 / 3 习惯 / 4 年龄 / 5 金额
const QUESTION_STEPS = 5;

// 主按钮：青绿底 + 近黑字（高对比、克制）；胶囊（设计语言：按钮=胶囊）
const BTN_PRIMARY =
  "rounded-full bg-reddit text-[#06120f] font-bold tracking-tight hover:brightness-[1.06] active:brightness-95 transition disabled:opacity-60 disabled:pointer-events-none";

// 内容列最大宽：大气留白，进度/内容/导航对齐到同一列
const COL = "mx-auto w-full max-w-[680px]";

export function OnboardingFlow({ tickers }: { tickers: OnbTicker[] }) {
  const { lang, dict } = useLocale();
  const t = dict.onboarding;
  const router = useRouter();
  const { user, loading } = useAuth();

  const [edit, setEdit] = useState(false);
  const [step, setStep] = useState(0);
  const [interests, setInterests] = useState<string[]>([]);
  const [holdings, setHoldings] = useState<string[]>([]);
  const [habitRank, setHabitRank] = useState<HoldingHabit[]>([...HABIT_KEYS]);
  const [experience, setExperience] = useState<Experience | null>(null);
  const [size, setSize] = useState<PortfolioSize | null>(null);
  const [query, setQuery] = useState("");
  const [cat, setCat] = useState<InstrumentKind | "all">("all"); // 持仓步：标的类别筛选
  const [saving, setSaving] = useState(false);

  // 编辑模式（从设置进入 /onboarding?edit=1）：读 query（避免 useSearchParams 在静态导出的 Suspense 约束）。
  useEffect(() => {
    if (typeof window !== "undefined" && new URLSearchParams(window.location.search).get("edit") === "1") {
      setEdit(true);
      setStep(1); // 编辑模式跳过欢迎屏
    }
  }, []);

  // 门禁：未登录直接来此 → 回登录页
  useEffect(() => {
    if (!loading && !user) router.replace(withLang(lang, "/login"));
  }, [loading, user, router, lang]);

  // 预填已有画像（编辑模式必填；首登若曾跳过也带回上次选择）
  useEffect(() => {
    let active = true;
    if (!user) return;
    loadProfile(user.id).then((p) => {
      if (!active || !p) return;
      if (p.interests?.length) setInterests(p.interests);
      if (p.holdings?.length) setHoldings(p.holdings);
      if (p.habit_rank?.length) setHabitRank(normalizeHabitRank(p.habit_rank));
      else if (p.holding_habit) setHabitRank(normalizeHabitRank([p.holding_habit]));
      if (p.experience) setExperience(p.experience);
      if (p.portfolio_size) setSize(p.portfolio_size);
    });
    return () => {
      active = false;
    };
  }, [user]);

  const pickName = (tk: OnbTicker) => (lang === "zh" ? tk.name_zh || tk.name_en : tk.name_en || tk.name_zh);

  // 该类别下有几个标的（隐藏空类别的 chip）
  const kindCounts = useMemo(() => {
    const m = new Map<InstrumentKind, number>();
    for (const tk of tickers) m.set(tk.kind, (m.get(tk.kind) ?? 0) + 1);
    return m;
  }, [tickers]);

  const filtered = useMemo(() => {
    const q = query.trim().toUpperCase();
    return tickers.filter((tk) => {
      if (cat !== "all" && tk.kind !== cat) return false;
      if (!q) return true;
      return tk.ticker.toUpperCase().includes(q) || pickName(tk).toUpperCase().includes(q);
    });
  }, [query, cat, tickers, lang]);

  const toggle = (arr: string[], v: string) => (arr.includes(v) ? arr.filter((x) => x !== v) : [...arr, v]);

  const profilePatch = () => ({
    experience,
    interests,
    holdings,
    holding_habit: habitRank[0] ?? null, // 兼容旧单值列：写排名队首
    habit_rank: habitRank,
    portfolio_size: size,
    onboarded_at: new Date().toISOString(),
  });

  // 落库 + 标记 + 自动追踪持仓
  const persist = async () => {
    if (!user) return;
    setSaving(true);
    await saveProfile(user.id, profilePatch());
    await markOnboarded(user.id);
    // 所选持仓 → 「追踪」（idempotent；不删未选的，保持非破坏性）
    await Promise.all(holdings.map((sym) => addCollection(user.id, "ticker", sym)));
    setSaving(false);
  };

  const finishToApp = async () => {
    await persist();
    if (edit) router.replace(withLang(lang, "/account"));
    else setStep(QUESTION_STEPS + 1); // 完成屏
  };

  // 「稍后再说」：仍标记 onboarded（门禁不再拦），保存已填部分，离开
  const skipAll = async () => {
    if (user) {
      await saveProfile(user.id, profilePatch());
      await markOnboarded(user.id);
    }
    router.replace(withLang(lang, edit ? "/account" : "/"));
  };

  if (loading || !user) {
    return <div className="fixed inset-0 z-[95] grid place-items-center bg-ink text-sm text-neutral-500">···</div>;
  }

  const isLastQuestion = step === QUESTION_STEPS; // step 5 = 金额
  const showChrome = step >= 1 && step <= QUESTION_STEPS;
  const atStart = step <= (edit ? 1 : 0);

  return (
    <div className="fixed inset-0 z-[95] flex flex-col overflow-hidden bg-ink">
      {/* 进度（仅问答步）：贴顶、对齐内容列 —— 自然页面，非卡片 */}
      {showChrome && (
        <div className="shrink-0">
          <div className={`${COL} px-6 pt-7 sm:pt-9`}>
            <div className="mb-3 flex items-center justify-between">
              <span className="text-[11px] font-semibold uppercase tracking-[0.14em] text-neutral-500 tabular">
                {t.stepOf.replace("{n}", String(step)).replace("{total}", String(QUESTION_STEPS))}
              </span>
              <button onClick={skipAll} className="text-xs text-neutral-500 transition hover:text-reddit">
                {t.skip}
              </button>
            </div>
            <div className="flex gap-1.5">
              {Array.from({ length: QUESTION_STEPS }).map((_, i) => (
                <span
                  key={i}
                  className={`h-1 flex-1 rounded-full transition-colors duration-300 ${i < step ? "bg-reddit" : "bg-line"}`}
                />
              ))}
            </div>
          </div>
        </div>
      )}

      {/* 主体：居中内容列，大气留白；可滚动 */}
      <div className="flex-1 overflow-y-auto">
        <div key={step} className={`onb-in flex min-h-full flex-col ${COL} px-6 py-12 sm:py-16`}>
          {step === 0 && <Welcome t={t} onStart={() => setStep(1)} onSkip={skipAll} />}

          {/* ① 关注赛道 */}
          {step === 1 && (
            <Question
              eyebrow={t.intEyebrow}
              title={t.intTitle}
              subtitle={t.intSubtitle}
              badge={interests.length ? t.selected.replace("{n}", String(interests.length)) : undefined}
            >
              <div className="grid grid-cols-2 gap-3">
                {INTEREST_KEYS.map((k) => {
                  const active = interests.includes(k);
                  return (
                    <button
                      key={k}
                      onClick={() => setInterests((a) => toggle(a, k))}
                      aria-pressed={active}
                      className={`group flex items-center gap-3 rounded-xl px-4 py-4 text-[15px] font-medium ring-1 ring-inset transition ${
                        active
                          ? "bg-reddit/[0.12] text-cream ring-reddit"
                          : "bg-card text-neutral-300 ring-line hover:bg-elevated hover:text-cream hover:ring-neutral-600"
                      }`}
                    >
                      <CheckDot active={active} />
                      <span className="truncate">{t.interests[k]}</span>
                    </button>
                  );
                })}
              </div>
            </Question>
          )}

          {/* ② 持有标的（广义：个股 + ETF / 杠杆反向 / 商品 / 加密 / 债券） */}
          {step === 2 && (
            <Question
              eyebrow={t.holdEyebrow}
              title={t.holdTitle}
              subtitle={t.holdSubtitle}
              badge={holdings.length ? t.selected.replace("{n}", String(holdings.length)) : undefined}
            >
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={t.holdSearch}
                className="w-full rounded-xl border border-line bg-card px-4 py-3 text-[15px] text-neutral-100 placeholder:text-neutral-600 focus:border-reddit/60 focus:outline-none focus:ring-2 focus:ring-reddit/15"
              />
              {/* 已选持仓：sticky 常驻，下滑浏览列表时始终可见（点 × 移除） */}
              {holdings.length > 0 && (
                <div className="sticky top-0 z-10 -mx-6 mt-3 border-b border-line bg-ink px-6 py-3">
                  <div className="flex flex-wrap gap-2">
                    {holdings.map((sym) => (
                      <button
                        key={sym}
                        onClick={() => setHoldings((a) => a.filter((x) => x !== sym))}
                        className="inline-flex items-center gap-1.5 rounded-full bg-reddit/15 py-1 pl-3 pr-2.5 text-[13px] font-semibold text-reddit ring-1 ring-inset ring-reddit/30 transition hover:bg-reddit/25"
                      >
                        {sym}
                        <svg viewBox="0 0 24 24" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round">
                          <path d="M18 6 6 18M6 6l12 12" />
                        </svg>
                      </button>
                    ))}
                  </div>
                </div>
              )}
              {/* 类别筛选 */}
              <div className="mt-4 flex flex-wrap gap-2">
                <CatChip active={cat === "all"} onClick={() => setCat("all")}>
                  {t.holdAll}
                </CatChip>
                {INSTRUMENT_KINDS.filter((k) => (kindCounts.get(k) ?? 0) > 0).map((k) => (
                  <CatChip key={k} active={cat === k} onClick={() => setCat(k)}>
                    {t.holdKinds[k]}
                  </CatChip>
                ))}
              </div>
              {filtered.length === 0 ? (
                <p className="mt-10 text-center text-sm text-neutral-600">{t.holdEmpty}</p>
              ) : (
                <div className="mt-4 grid grid-cols-2 gap-3">
                  {filtered.map((tk) => {
                    const active = holdings.includes(tk.ticker);
                    return (
                      <button
                        key={tk.ticker}
                        onClick={() => setHoldings((a) => toggle(a, tk.ticker))}
                        aria-pressed={active}
                        className={`flex items-center gap-3 rounded-xl px-3.5 py-3 text-left ring-1 ring-inset transition ${
                          active ? "bg-reddit/[0.12] ring-reddit" : "bg-card ring-line hover:bg-elevated hover:ring-neutral-600"
                        }`}
                      >
                        <Logo ticker={tk.ticker} />
                        <span className="min-w-0 flex-1">
                          <span className="block font-display text-[15px] font-bold leading-tight text-cream">{tk.ticker}</span>
                          <span className="block truncate text-[12px] text-neutral-500">{pickName(tk)}</span>
                        </span>
                        {active && (
                          <span className="grid h-[18px] w-[18px] shrink-0 place-items-center rounded-full bg-reddit text-[#06120f]">
                            <TinyCheck />
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              )}
            </Question>
          )}

          {/* ③ 持有习惯（拖动或上下箭头排序，序号即排名） */}
          {step === 3 && (
            <Question eyebrow={t.habitEyebrow} title={t.habitTitle} subtitle={t.habitSubtitle}>
              <HabitRank order={habitRank} setOrder={setHabitRank} t={t} />
            </Question>
          )}

          {/* ④ 投资年龄 */}
          {step === 4 && (
            <Question eyebrow={t.expEyebrow} title={t.expTitle} subtitle={t.expSubtitle}>
              <div className="space-y-3">
                {EXPERIENCE_KEYS.map((k) => {
                  const e = t.experiences[k];
                  const active = experience === k;
                  return (
                    <SelectRow key={k} active={active} onClick={() => setExperience(active ? null : k)}>
                      <Radio active={active} />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-[15px] font-semibold text-cream">{e.label}</span>
                          <span
                            className={`shrink-0 rounded-full px-2.5 py-0.5 text-[11px] tabular ${
                              active ? "bg-reddit/20 text-reddit" : "bg-white/5 text-neutral-500"
                            }`}
                          >
                            {e.years}
                          </span>
                        </div>
                        <p className="mt-1 text-[13.5px] leading-relaxed text-neutral-500">{e.desc}</p>
                      </div>
                    </SelectRow>
                  );
                })}
              </div>
            </Question>
          )}

          {/* ⑤ 投资金额 */}
          {step === 5 && (
            <Question eyebrow={t.sizeEyebrow} title={t.sizeTitle} subtitle={t.sizeSubtitle}>
              <div className="space-y-3">
                {SIZE_KEYS.map((k) => {
                  const active = size === k;
                  return (
                    <SelectRow key={k} active={active} onClick={() => setSize(active ? null : k)}>
                      <Radio active={active} />
                      <span className={`text-[15px] font-medium ${k === "na" ? "text-neutral-400" : "text-cream"}`}>{t.sizes[k]}</span>
                    </SelectRow>
                  );
                })}
              </div>
            </Question>
          )}

          {/* 完成 */}
          {step === 6 && (
            <Finish
              t={t}
              followed={holdings.length}
              interests={interests.map((k) => t.interests[k as keyof typeof t.interests])}
              onEnter={() => router.replace(withLang(lang, "/"))}
            />
          )}
        </div>
      </div>

      {/* 底部导航（仅问答步）：对齐内容列、细线分隔 —— 非卡片 */}
      {showChrome && (
        <div className="shrink-0 border-t border-line">
          <div className={`${COL} flex items-center justify-between gap-3 px-6 py-4 sm:py-5`}>
            <button
              onClick={() => setStep((s) => Math.max(edit ? 1 : 0, s - 1))}
              disabled={atStart}
              className="text-sm font-medium text-neutral-500 transition hover:text-cream disabled:pointer-events-none disabled:opacity-0"
            >
              {t.back}
            </button>
            <button
              onClick={isLastQuestion ? finishToApp : () => setStep((s) => s + 1)}
              disabled={saving}
              className={`${BTN_PRIMARY} min-w-[140px] px-8 py-3 text-[15px]`}
            >
              {saving ? t.saving : isLastQuestion ? (edit ? t.saveBtn : t.next) : t.next}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ---------- 子件 ---------- */

function Welcome({ t, onStart, onSkip }: { t: Dict; onStart: () => void; onSkip: () => void }) {
  return (
    <div className="m-auto w-full max-w-md text-center">
      <div className="flex justify-center">
        <BrandMark />
      </div>
      <h1 className="mt-6 font-display text-[30px] font-extrabold tracking-tight text-cream sm:text-[36px]">{t.welcomeTitle}</h1>
      <p className="mx-auto mt-3 max-w-[22rem] text-[15px] leading-relaxed text-neutral-400">{t.welcomeSubtitle}</p>
      <ul className="mx-auto mt-9 w-full max-w-[20rem] space-y-3.5 text-left">
        {[t.welcomeBullet1, t.welcomeBullet2, t.welcomeBullet3].map((b, i) => (
          <li key={i} className="flex items-start gap-3 text-[14.5px] text-neutral-300">
            <Check />
            <span className="leading-relaxed">{b}</span>
          </li>
        ))}
      </ul>
      <button onClick={onStart} className={`${BTN_PRIMARY} mt-10 w-full max-w-[20rem] py-3.5 text-[15px]`}>
        {t.startBtn}
      </button>
      <button onClick={onSkip} className="mt-4 block w-full text-xs text-neutral-500 transition hover:text-reddit">
        {t.skip}
      </button>
    </div>
  );
}

function Finish({
  t,
  followed,
  interests,
  onEnter,
}: {
  t: Dict;
  followed: number;
  interests: string[];
  onEnter: () => void;
}) {
  return (
    <div className="m-auto w-full max-w-md text-center">
      <div className="mx-auto grid h-16 w-16 place-items-center rounded-full bg-reddit/15 text-reddit ring-1 ring-reddit/30">
        <svg viewBox="0 0 24 24" className="h-8 w-8" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
          <path d="m20 6-11 11-5-5" />
        </svg>
      </div>
      <h1 className="mt-6 font-display text-[27px] font-extrabold tracking-tight text-cream">{t.finishTitle}</h1>
      <p className="mt-2.5 text-[14.5px] leading-relaxed text-neutral-400">{t.finishSubtitle}</p>

      <div className="mt-7 space-y-2.5 text-left">
        {followed > 0 && (
          <div className="flex items-center gap-3 rounded-xl bg-card px-4 py-3.5 text-sm text-neutral-300 ring-1 ring-inset ring-line">
            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-reddit/15 text-reddit">★</span>
            {t.finishFollowed.replace("{n}", String(followed))}
          </div>
        )}
        {interests.length > 0 && (
          <div className="rounded-xl bg-card px-4 py-3.5 ring-1 ring-inset ring-line">
            <div className="mb-2 text-[11px] font-medium text-neutral-500">{t.finishInterestsLabel}</div>
            <div className="flex flex-wrap gap-2">
              {interests.map((s, i) => (
                <span key={i} className="rounded-full bg-reddit/10 px-2.5 py-1 text-xs text-reddit">
                  {s}
                </span>
              ))}
            </div>
          </div>
        )}
      </div>

      <button onClick={onEnter} className={`${BTN_PRIMARY} mt-9 w-full py-3.5 text-[15px]`}>
        {t.enterBtn}
      </button>
    </div>
  );
}

function Question({
  eyebrow,
  title,
  subtitle,
  badge,
  children,
}: {
  eyebrow: string;
  title: string;
  subtitle: string;
  badge?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="w-full">
      <div className="mb-7">
        <div className="flex items-center justify-between gap-3">
          <span className="text-[11px] font-semibold uppercase tracking-[0.14em] text-reddit">{eyebrow}</span>
          {badge && (
            <span className="shrink-0 rounded-full bg-reddit/15 px-2.5 py-1 text-[11px] font-semibold tabular text-reddit ring-1 ring-inset ring-reddit/25">
              {badge}
            </span>
          )}
        </div>
        <h2 className="mt-2.5 font-display text-[28px] font-extrabold leading-[1.15] tracking-tight text-cream sm:text-[32px]">{title}</h2>
        <p className="mt-2.5 text-[14.5px] leading-relaxed text-neutral-500">{subtitle}</p>
      </div>
      {children}
    </div>
  );
}

function SelectRow({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      aria-pressed={active}
      className={`flex w-full items-center gap-3.5 rounded-xl px-5 py-4 text-left ring-1 ring-inset transition ${
        active ? "bg-reddit/[0.12] ring-reddit" : "bg-card ring-line hover:bg-elevated hover:ring-neutral-600"
      }`}
    >
      {children}
    </button>
  );
}

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));

type HabitDrag = { index: number; dy: number; slot: number };

// 持有习惯排名（拖拽排序）：整张卡片用 pointer 事件「拎起」跟手移动（放大+投影+置顶），
// 其余卡片带过渡平滑让位；落下瞬间关掉过渡直接定位、无跳变。右侧上下箭头供精确/无障碍操作。
function HabitRank({
  order,
  setOrder,
  t,
}: {
  order: HoldingHabit[];
  setOrder: (o: HoldingHabit[]) => void;
  t: Dict;
}) {
  const listRef = useRef<HTMLUListElement>(null);
  const [drag, setDrag] = useState<HabitDrag | null>(null);
  const dragRef = useRef<HabitDrag | null>(null);
  const set = (d: HabitDrag | null) => {
    dragRef.current = d;
    setDrag(d);
  };

  const move = (from: number, to: number) => {
    const t2 = clamp(to, 0, order.length - 1);
    if (t2 === from) return;
    const next = order.slice();
    const [it] = next.splice(from, 1);
    next.splice(t2, 0, it);
    setOrder(next);
  };

  // 整卡拖拽（pointer 事件，桌面+触屏统一）。在卡片上按下即开始；用 window 监听保证移出卡片也跟手。
  const startDrag = (e: React.PointerEvent, index: number) => {
    if (e.pointerType === "mouse" && e.button !== 0) return; // 仅鼠标左键
    e.preventDefault();
    const lis = listRef.current?.children;
    const slot =
      lis && lis.length > 1
        ? (lis[1] as HTMLElement).getBoundingClientRect().top - (lis[0] as HTMLElement).getBoundingClientRect().top
        : 80;
    const startY = e.clientY;
    set({ index, dy: 0, slot });

    const onMove = (ev: PointerEvent) => set({ index, dy: ev.clientY - startY, slot });
    const cleanup = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onCancel);
    };
    const onUp = () => {
      cleanup();
      const cur = dragRef.current;
      set(null); // 先清拖拽态 → 本帧过渡关闭、直接落到最终位（见下方 transition 逻辑），无跳变
      if (cur) move(index, index + Math.round(cur.dy / cur.slot));
    };
    const onCancel = () => {
      cleanup();
      set(null); // 被系统打断：还原，不重排
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onCancel);
  };

  const target = drag ? clamp(drag.index + Math.round(drag.dy / drag.slot), 0, order.length - 1) : -1;

  return (
    <ul ref={listRef} className="space-y-3 select-none">
      {order.map((k, i) => {
        const h = t.habits[k];
        const dragged = drag?.index === i;
        // 其余卡片：被拖卡跨过的区间内整体让位 ±1 个 slot
        let shift = 0;
        if (drag && !dragged) {
          if (drag.index < target && i > drag.index && i <= target) shift = -drag.slot;
          else if (drag.index > target && i >= target && i < drag.index) shift = drag.slot;
        }
        const style: React.CSSProperties = dragged
          ? { transform: `translateY(${drag!.dy}px) scale(1.015)`, zIndex: 30, transition: "none" }
          : { transform: `translateY(${shift}px)`, transition: drag ? "transform 200ms cubic-bezier(.2,1,.36,1)" : "none" };
        return (
          <li
            key={k}
            onPointerDown={(e) => startDrag(e, i)}
            style={{ ...style, touchAction: "none" }}
            className={`group flex items-center gap-3 rounded-xl px-3.5 py-3.5 ring-1 ring-inset ${
              dragged
                ? "cursor-grabbing bg-elevated ring-reddit shadow-[0_14px_34px_-10px_rgba(0,0,0,0.75)]"
                : "cursor-grab bg-card ring-line hover:bg-elevated hover:ring-neutral-600"
            }`}
          >
            {/* 左侧拖动手柄：静止即醒目（neutral-400），悬停加亮到主色 + grab 光标，明确「可拖动」 */}
            <span
              aria-hidden
              className="-ml-1 grid h-9 w-7 shrink-0 cursor-grab place-items-center text-neutral-400 transition group-hover:text-cream"
            >
              <Grip />
            </span>
            <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-reddit/15 font-display text-[13px] font-bold tabular text-reddit">
              {i + 1}
            </span>
            <div className="min-w-0 flex-1">
              <span className="text-[15px] font-semibold text-cream">{h.label}</span>
              <p className="mt-0.5 text-[13px] leading-relaxed text-neutral-500">{h.desc}</p>
            </div>
            {/* 右侧：上下箭头（精确/无障碍）。各自 stopPropagation，点箭头不触发拖动；拖拽由左侧手柄/整卡发起。 */}
            <div className="flex shrink-0 items-center gap-0.5">
              <button
                type="button"
                onPointerDown={(e) => e.stopPropagation()}
                onClick={() => move(i, i - 1)}
                disabled={i === 0}
                aria-label="↑"
                className="grid h-7 w-7 place-items-center rounded-md text-neutral-500 transition hover:bg-white/5 hover:text-cream disabled:pointer-events-none disabled:opacity-20"
              >
                <Chevron up />
              </button>
              <button
                type="button"
                onPointerDown={(e) => e.stopPropagation()}
                onClick={() => move(i, i + 1)}
                disabled={i === order.length - 1}
                aria-label="↓"
                className="grid h-7 w-7 place-items-center rounded-md text-neutral-500 transition hover:bg-white/5 hover:text-cream disabled:pointer-events-none disabled:opacity-20"
              >
                <Chevron />
              </button>
            </div>
          </li>
        );
      })}
    </ul>
  );
}

function Chevron({ up = false }: { up?: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className="h-4 w-4"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={up ? undefined : { transform: "rotate(180deg)" }}
    >
      <path d="m6 15 6-6 6 6" />
    </svg>
  );
}

function Grip() {
  return (
    <svg viewBox="0 0 16 16" className="h-[19px] w-[19px]" fill="currentColor" aria-hidden>
      <circle cx="5.5" cy="3.5" r="1.5" />
      <circle cx="10.5" cy="3.5" r="1.5" />
      <circle cx="5.5" cy="8" r="1.5" />
      <circle cx="10.5" cy="8" r="1.5" />
      <circle cx="5.5" cy="12.5" r="1.5" />
      <circle cx="10.5" cy="12.5" r="1.5" />
    </svg>
  );
}

function CatChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      aria-pressed={active}
      className={`rounded-full px-3 py-1.5 text-[13px] font-medium ring-1 ring-inset transition ${
        active ? "bg-reddit/15 text-reddit ring-reddit/50" : "bg-card text-neutral-400 ring-line hover:text-cream hover:ring-neutral-600"
      }`}
    >
      {children}
    </button>
  );
}

function BrandMark() {
  return (
    <span
      className="grid h-16 w-16 place-items-center rounded-2xl font-display text-[28px] font-extrabold text-white ring-1 ring-inset ring-white/15"
      style={{ backgroundImage: "var(--grad-brand)" }}
    >
      P
    </span>
  );
}

// 单选指示器：圆形 radio（圆=单选语义；与多选的方形 CheckDot 区分）。
function Radio({ active }: { active: boolean }) {
  return (
    <span
      className={`grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full border-2 transition ${
        active ? "border-reddit" : "border-line"
      }`}
    >
      {active && <span className="h-2.5 w-2.5 rounded-full bg-reddit" />}
    </span>
  );
}

// 多选指示器：方形复选框（方=多选语义；与单选的圆形 Radio 区分）。
function CheckDot({ active }: { active: boolean }) {
  return (
    <span
      className={`grid h-5 w-5 shrink-0 place-items-center rounded-[5px] border transition ${
        active
          ? "border-reddit bg-reddit text-[#06120f]"
          : "border-line bg-transparent text-transparent group-hover:border-neutral-500"
      }`}
    >
      <TinyCheck />
    </span>
  );
}

function TinyCheck() {
  return (
    <svg viewBox="0 0 24 24" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="m20 6-11 11-5-5" />
    </svg>
  );
}

function Check() {
  return (
    <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-reddit/15 text-reddit">
      <svg viewBox="0 0 24 24" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
        <path d="m20 6-11 11-5-5" />
      </svg>
    </span>
  );
}

function Logo({ ticker }: { ticker: string }) {
  const [bad, setBad] = useState(false);
  if (bad) {
    return (
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white/5 text-[11px] font-bold text-neutral-400">
        {ticker.charAt(0)}
      </span>
    );
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={`https://assets.parqet.com/logos/symbol/${ticker}?format=png&size=64`}
      alt={ticker}
      onError={() => setBad(true)}
      className="h-8 w-8 shrink-0 rounded-full bg-white object-contain"
      loading="lazy"
    />
  );
}

type Dict = ReturnType<typeof useLocale>["dict"]["onboarding"];
