"use client";

import { usePathname, useRouter } from "next/navigation";
import { stripLang, type Locale } from "@/lib/i18n";

const OPTS: { code: Locale; label: string }[] = [
  { code: "zh", label: "中" },
  { code: "en", label: "EN" },
  { code: "ja", label: "日" },
  { code: "ko", label: "한" },
];

export function LanguageSwitcher() {
  const path = usePathname() || "/";
  const router = useRouter();
  const { lang, rest } = stripLang(path);

  const go = (target: Locale) => {
    if (target === lang) return;
    try {
      localStorage.setItem("prismo:lang", target);
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
