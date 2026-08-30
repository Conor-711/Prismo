"use client";

import { useEffect, useRef, useState } from "react";
import type { FilterOption } from "../leaderboardModel";

export function SmartVoiceFilterSelect<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
  active = false,
  className = "",
}: {
  value: T;
  options: FilterOption<T>[];
  onChange: (value: T) => void;
  ariaLabel: string;
  active?: boolean;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const selected = options.find((option) => option.value === value) ?? options[0];

  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);

  return (
    <div ref={rootRef} className={`relative ${className}`}>
      <button
        type="button"
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
        className={`flex h-8 w-full items-center justify-between gap-2 rounded-lg px-2.5 text-[11.5px] font-medium outline-none ring-1 ring-inset transition ${
          active
            ? "bg-reddit/10 text-reddit ring-reddit/35"
            : "bg-transparent text-neutral-400 ring-line hover:text-cream hover:ring-neutral-600"
        }`}
      >
        <span className="truncate">{selected?.label}</span>
        <span aria-hidden className={`text-[10px] transition-transform ${open ? "rotate-180" : ""}`}>⌄</span>
      </button>
      {open ? (
        <div
          role="listbox"
          className="absolute left-0 top-[calc(100%+6px)] z-40 min-w-full overflow-hidden rounded-lg border border-line bg-[#181a1d] p-1 shadow-2xl shadow-black/45"
        >
          {options.map((option) => {
            const checked = option.value === value;
            return (
              <button
                key={option.value}
                type="button"
                role="option"
                aria-selected={checked}
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                }}
                className={`flex w-full items-center justify-between gap-4 rounded-md px-2.5 py-2 text-left text-[11.5px] transition ${
                  checked ? "bg-reddit/10 text-reddit" : "text-neutral-400 hover:bg-white/[.04] hover:text-cream"
                }`}
              >
                <span className="whitespace-nowrap">{option.label}</span>
                {option.hint ? <span className="whitespace-nowrap font-mono text-[9.5px] text-neutral-600">{option.hint}</span> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
