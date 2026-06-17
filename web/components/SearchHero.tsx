"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { LocaleLink } from "./i18n/LocaleLink";
import { IconSearch, IconArrow } from "./icons";
import { useLocale } from "./i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";

// 首页主入口：查任意个股的 Reddit 情报（直达 /ticker/[symbol]）。
export function SearchHero({ suggestions = [] }: { suggestions?: string[] }) {
  const router = useRouter();
  const { lang, dict } = useLocale();
  const t = dict.searchHero;
  const [v, setV] = useState("");

  const go = (e: React.FormEvent) => {
    e.preventDefault();
    const sym = v.trim().toUpperCase().replace(/^\$/, "");
    if (sym) router.push(withLang(lang, `/ticker/${encodeURIComponent(sym)}`));
  };

  return (
    <section
      className="panel rounded-2xl p-6 sm:p-8"
      style={{ boxShadow: "inset 0 0 0 1px rgba(255,69,0,0.18), var(--panel-shadow)" }}
    >
      <div className="eyebrow text-reddit">{t.eyebrow}</div>
      <h1 className="mt-2 font-display font-extrabold text-cream tracking-tight text-[clamp(22px,3vw,32px)] leading-tight">
        {t.title}
      </h1>
      <p className="mt-2 text-sm text-neutral-500 max-w-2xl leading-relaxed">
        {t.subPre}
        <span className="text-bull font-medium">{t.subBull}</span> ⚔{" "}
        <span className="text-bear font-medium">{t.subBear}</span>
        {t.subPost}
      </p>

      <form onSubmit={go} className="mt-5 relative max-w-xl">
        <IconSearch className="w-5 h-5 absolute left-4 top-1/2 -translate-y-1/2 text-neutral-500" />
        <input
          value={v}
          onChange={(e) => setV(e.target.value)}
          placeholder={t.placeholder}
          className="w-full bg-ink/60 border border-line rounded-xl pl-12 pr-32 py-3.5 text-[15px] text-neutral-100 placeholder:text-neutral-600 focus:outline-none focus:border-reddit/50 focus:ring-2 focus:ring-reddit/15"
        />
        <button
          type="submit"
          className="group absolute right-2 top-1/2 -translate-y-1/2 inline-flex items-center gap-1.5 rounded-lg px-4 py-2 font-display font-bold text-white text-sm hover:brightness-110 transition"
          style={{ backgroundImage: "var(--grad-brand)" }}
        >
          {t.cta}
          <IconArrow className="w-4 h-4 group-hover:translate-x-0.5 transition" />
        </button>
      </form>

      {suggestions.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-2 text-xs text-neutral-500">
          <span>{t.popular}</span>
          {suggestions.map((sym) => (
            <LocaleLink
              key={sym}
              href={`/ticker/${sym}`}
              className="font-mono font-medium px-2 py-0.5 rounded-md bg-white/[.04] text-neutral-300 hover:bg-reddit/15 hover:text-reddit ring-1 ring-inset ring-white/8 transition"
            >
              {sym}
            </LocaleLink>
          ))}
        </div>
      )}
    </section>
  );
}
