"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { KolSource } from "@/shared/market/mockDetail";
import { SOURCE } from "@/shared/market/kolPresentation";
import type { PersonalDirection, PersonalPrefs, PersonalStyle } from "@/features/ticker/opinionExplorerTypes";

export function Chip({
  active,
  dim,
  onClick,
  children,
}: {
  active: boolean;
  dim?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={`rounded-md px-2 py-0.5 text-[11.5px] font-medium ring-1 ring-inset transition ${
        active ? "bg-elevated text-cream ring-[#57D7BA]" : `${dim ? "text-neutral-600" : "text-neutral-400"} ring-line hover:text-neutral-200`
      }`}
    >
      {children}
    </button>
  );
}

const PLAT_LOGO: Record<KolSource, string> = {
  x: "/platform/x.png",
  youtube: "/platform/youtube.png",
  reddit: "/platform/reddit.png",
  xueqiu: "/platform/xueqiu.png",
  toss: "/platform/toss.svg",
  yahoojp: "/platform/yahoojp.svg",
};

export function PlatformIcon({ src, size = 14 }: { src: KolSource; size?: number }) {
  return (
    <img
      src={PLAT_LOGO[src]}
      alt={SOURCE[src].label}
      width={size}
      height={size}
      style={{ width: size, height: size }}
      className="shrink-0 rounded-[3px] object-contain"
    />
  );
}

export function Dropdown({
  label,
  value,
  children,
}: {
  label: string;
  value: string;
  children: (close: () => void) => React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const [panelPos, setPanelPos] = useState({ left: 12, top: 64, minWidth: 150 });
  const placePanel = () => {
    const rect = buttonRef.current?.getBoundingClientRect();
    if (!rect || typeof window === "undefined") return;
    const minWidth = Math.max(150, rect.width);
    setPanelPos({
      left: Math.min(Math.max(12, rect.left), Math.max(12, window.innerWidth - minWidth - 12)),
      top: Math.min(rect.bottom + 6, Math.max(12, window.innerHeight - 260)),
      minWidth,
    });
  };
  useEffect(() => {
    if (!open) return;
    placePanel();
    const onMove = () => placePanel();
    window.addEventListener("resize", onMove);
    window.addEventListener("scroll", onMove, true);
    return () => {
      window.removeEventListener("resize", onMove);
      window.removeEventListener("scroll", onMove, true);
    };
  }, [open]);
  return (
    <div className="shrink-0">
      <button
        ref={buttonRef}
        type="button"
        onClick={() => {
          placePanel();
          setOpen((o) => !o);
        }}
        className="flex h-11 min-w-[148px] items-center justify-between gap-2 rounded-md px-3.5 text-[13px] text-neutral-300 ring-1 ring-inset ring-line transition hover:text-cream"
      >
        <span className="text-neutral-500">{label}</span>
        <span className="text-cream">{value}</span>
        <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="text-neutral-500" aria-hidden>
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>
      {open && typeof document !== "undefined"
        ? createPortal(
            <>
              <div className="fixed inset-0 z-[80]" onClick={() => setOpen(false)} />
              <div
                className="fixed z-[90] rounded-lg bg-elevated p-1 shadow-xl ring-1 ring-inset ring-line"
                style={{ left: panelPos.left, top: panelPos.top, minWidth: panelPos.minWidth }}
              >
                {children(() => setOpen(false))}
              </div>
            </>,
            document.body
          )
        : null}
    </div>
  );
}

export function MenuItem({
  active,
  disabled,
  onClick,
  children,
}: {
  active?: boolean;
  disabled?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[12px] transition ${
        disabled ? "cursor-default text-neutral-700" : active ? "bg-card text-[#57D7BA]" : "text-neutral-300 hover:bg-card hover:text-cream"
      }`}
    >
      {children}
    </button>
  );
}

function FieldInput({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  return (
    <label className="min-w-0">
      <span className="text-[10px] uppercase tracking-wide text-neutral-500">{label}</span>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        inputMode="decimal"
        placeholder={placeholder}
        className="mt-1 h-9 w-full rounded-md bg-card px-2.5 text-[12px] text-cream outline-none ring-1 ring-inset ring-line placeholder:text-neutral-700 focus:ring-[#57D7BA]/70"
      />
    </label>
  );
}

function ChoiceGroup<T extends string>({
  label,
  value,
  options,
  onChange,
  columns,
}: {
  label: string;
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
  columns: string;
}) {
  return (
    <div className="min-w-0">
      <div className="text-[10px] uppercase tracking-wide text-neutral-500">{label}</div>
      <div className={`mt-1 grid ${columns} gap-1 rounded-lg bg-card/70 p-1 ring-1 ring-inset ring-line`}>
        {options.map((option) => {
          const selected = value === option.value;
          return (
            <button
              key={option.value || "unset"}
              type="button"
              onClick={() => onChange(option.value)}
              aria-pressed={selected}
              className={`h-8 rounded-md px-2 text-[12px] font-semibold transition ${
                selected
                  ? "bg-[#57D7BA]/10 text-cream shadow-[0_0_12px_rgb(87_215_186_/_0.10)] ring-1 ring-inset ring-[#57D7BA]/80"
                  : "text-neutral-500 hover:bg-white/[.035] hover:text-neutral-200"
              }`}
            >
              {option.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function PersonalizeButton({
  zh,
  configured,
  active,
  draft,
  setDraft,
  onSave,
  onClear,
  currentPrice,
}: {
  zh: boolean;
  configured: boolean;
  active: boolean;
  draft: PersonalPrefs;
  setDraft: (value: PersonalPrefs) => void;
  onSave: () => void;
  onClear: () => void;
  currentPrice?: number | null;
}) {
  const [open, setOpen] = useState(false);
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const [panelPos, setPanelPos] = useState({ left: 16, top: 96 });
  const set = <K extends keyof PersonalPrefs>(key: K, value: PersonalPrefs[K]) => setDraft({ ...draft, [key]: value });
  const placePanel = () => {
    const rect = buttonRef.current?.getBoundingClientRect();
    if (!rect || typeof window === "undefined") return;
    const width = 360;
    setPanelPos({
      left: Math.min(Math.max(12, rect.left), Math.max(12, window.innerWidth - width - 12)),
      top: Math.min(rect.bottom + 8, Math.max(12, window.innerHeight - 430)),
    });
  };
  useEffect(() => {
    if (!open) return;
    placePanel();
    const onResize = () => placePanel();
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [open]);
  return (
    <div className="shrink-0">
      <button
        ref={buttonRef}
        type="button"
        onClick={() => {
          placePanel();
          setOpen((v) => !v);
        }}
        className={`flex h-11 min-w-[132px] items-center justify-center gap-2 rounded-md px-3.5 text-[13px] font-semibold ring-1 ring-inset transition ${
          active
            ? "bg-[#57D7BA]/10 text-cream shadow-[0_0_14px_rgb(87_215_186_/_0.10)] ring-[#57D7BA]/80"
            : configured
              ? "text-[#57D7BA] ring-[#57D7BA]/45 hover:ring-[#57D7BA]/80"
              : "text-neutral-300 ring-line hover:text-cream"
        }`}
        aria-pressed={active}
      >
        <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
        </svg>
        {zh ? "个人化" : "For You"}
        {configured && <span className="h-1.5 w-1.5 rounded-full bg-[#57D7BA]" />}
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-[80]" onClick={() => setOpen(false)} />
          <div
            className="fixed z-[90] max-h-[calc(100vh-24px)] w-[360px] overflow-y-auto rounded-xl bg-elevated p-3 shadow-2xl ring-1 ring-inset ring-line"
            style={{ left: panelPos.left, top: panelPos.top }}
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="text-[13px] font-bold text-cream">{zh ? "个性化观点排序" : "Personalized ranking"}</div>
                <p className="mt-0.5 text-[11px] leading-snug text-neutral-500">
                  {zh ? "每项都可留空；填写越多，推荐排序越贴近当前仓位。" : "Every field is optional. More inputs make ranking more position-aware."}
                </p>
              </div>
              {currentPrice != null && (
                <span className="rounded bg-card px-2 py-1 font-mono text-[11px] text-neutral-400">
                  ${currentPrice.toFixed(currentPrice >= 10 ? 2 : 3)}
                </span>
              )}
            </div>

            <div className="mt-3 grid grid-cols-2 gap-2">
              <div className="col-span-2">
                <ChoiceGroup<PersonalDirection>
                  label={zh ? "仓位方向" : "Direction"}
                  value={draft.direction}
                  onChange={(v) => set("direction", v)}
                  columns="grid-cols-4"
                  options={[
                    { value: "", label: zh ? "未设置" : "Unset" },
                    { value: "long", label: zh ? "做多" : "Long" },
                    { value: "short", label: zh ? "做空" : "Short" },
                    { value: "watch", label: zh ? "观望" : "Watch" },
                  ]}
                />
              </div>
              <div className="col-span-2">
                <ChoiceGroup<PersonalStyle>
                  label={zh ? "操作习惯" : "Style"}
                  value={draft.style}
                  onChange={(v) => set("style", v)}
                  columns="grid-cols-5"
                  options={[
                    { value: "", label: zh ? "未设置" : "Unset" },
                    { value: "shortterm", label: zh ? "短线" : "Short" },
                    { value: "swing", label: zh ? "波段" : "Swing" },
                    { value: "longterm", label: zh ? "长线" : "Long" },
                    { value: "dca", label: zh ? "定投" : "DCA" },
                  ]}
                />
              </div>
              <FieldInput label={zh ? "成本价" : "Cost"} value={draft.costLow} onChange={(v) => set("costLow", v)} placeholder={zh ? "单价 / 下限" : "Exact / low"} />
              <FieldInput label={zh ? "成本上限" : "Cost high"} value={draft.costHigh} onChange={(v) => set("costHigh", v)} placeholder={zh ? "区间上限，可空" : "High, optional"} />
              <FieldInput label={zh ? "仓位占比 %" : "Position %"} value={draft.positionLow} onChange={(v) => set("positionLow", v)} placeholder={zh ? "占比 / 下限" : "Exact / low"} />
              <FieldInput label={zh ? "占比上限 %" : "Position high"} value={draft.positionHigh} onChange={(v) => set("positionHigh", v)} placeholder={zh ? "区间上限，可空" : "High, optional"} />
              <FieldInput label={zh ? "目标价" : "Target"} value={draft.targetPrice} onChange={(v) => set("targetPrice", v)} placeholder={zh ? "可空" : "Optional"} />
              <FieldInput label={zh ? "止损价" : "Stop loss"} value={draft.stopLoss} onChange={(v) => set("stopLoss", v)} placeholder={zh ? "可空" : "Optional"} />
            </div>

            <div className="mt-3 flex items-center justify-between gap-2">
              <button
                type="button"
                onClick={() => {
                  onClear();
                  setOpen(false);
                }}
                className="rounded-md px-2.5 py-1.5 text-[12px] font-semibold text-neutral-500 transition hover:text-neutral-300"
              >
                {zh ? "清除个人化" : "Clear"}
              </button>
              <button
                type="button"
                onClick={() => {
                  onSave();
                  setOpen(false);
                }}
                className="rounded-md bg-[#57D7BA] px-3 py-1.5 text-[12px] font-bold text-[#0d0d0d] transition hover:bg-[#75e3cc]"
              >
                {zh ? "应用推荐排序" : "Apply ranking"}
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
