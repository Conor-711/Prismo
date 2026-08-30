"use client";

import { useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import type { useLocale } from "@/components/i18n/LocaleProvider";
import type { HoldingHabit } from "@/lib/profile";

export const ONBOARDING_PRIMARY_BUTTON =
  "rounded-full bg-reddit text-[#06120f] font-bold tracking-tight hover:brightness-[1.06] active:brightness-95 transition disabled:opacity-60 disabled:pointer-events-none";

export function Welcome({ t, onStart, onSkip }: { t: OnboardingDict; onStart: () => void; onSkip: () => void }) {
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
      <button onClick={onStart} className={`${ONBOARDING_PRIMARY_BUTTON} mt-10 w-full max-w-[20rem] py-3.5 text-[15px]`}>
        {t.startBtn}
      </button>
      <button onClick={onSkip} className="mt-4 block w-full text-xs text-neutral-500 transition hover:text-reddit">
        {t.skip}
      </button>
    </div>
  );
}

export function Finish({
  t,
  followed,
  interests,
  onEnter,
}: {
  t: OnboardingDict;
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

      <button onClick={onEnter} className={`${ONBOARDING_PRIMARY_BUTTON} mt-9 w-full py-3.5 text-[15px]`}>
        {t.enterBtn}
      </button>
    </div>
  );
}

export function Question({
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
  children: ReactNode;
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

export function SelectRow({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
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
export function HabitRank({
  order,
  setOrder,
  t,
}: {
  order: HoldingHabit[];
  setOrder: (o: HoldingHabit[]) => void;
  t: OnboardingDict;
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
  const startDrag = (e: ReactPointerEvent, index: number) => {
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
        const style: CSSProperties = dragged
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

export function CatChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
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
      b
    </span>
  );
}

// 单选指示器：圆形 radio（圆=单选语义；与多选的方形 CheckDot 区分）。
export function Radio({ active }: { active: boolean }) {
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
export function CheckDot({ active }: { active: boolean }) {
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

export function TinyCheck() {
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

export function Logo({ ticker }: { ticker: string }) {
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

export type OnboardingDict = ReturnType<typeof useLocale>["dict"]["onboarding"];
