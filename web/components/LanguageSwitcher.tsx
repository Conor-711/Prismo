"use client";

import { usePathname, useRouter } from "next/navigation";
import { stripLang, type PublishedLocale } from "@/lib/i18n";

const OPTS: { code: PublishedLocale; label: string }[] = [
  { code: "zh", label: "中" },
  { code: "en", label: "EN" },
];

export function LanguageSwitcher() {
  const path = usePathname() || "/";
  const router = useRouter();
  const { lang, rest } = stripLang(path);

  const go = (target: PublishedLocale) => {
    if (target === lang) return;
    try {
      localStorage.setItem("bsmart:lang", target);
    } catch {
      /* ignore */
    }
    const tail = rest === "/" ? "" : rest;
    router.push(`/${target}${tail}`);
  };

  return (
    <div
      className="inline-flex items-center rounded-full border border-line bg-white/[.03] p-0.5"
      role="group"
      aria-label="Language"
    >
      {OPTS.map((o) => {
        const active = o.code === lang;
        return (
          <button
            key={o.code}
            type="button"
            onClick={() => go(o.code)}
            aria-pressed={active}
            className={`px-2.5 py-1 rounded-full text-xs font-semibold transition ${
              active ? "bg-reddit/15 text-reddit" : "text-neutral-400 hover:text-cream"
            }`}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
