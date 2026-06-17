"use client";

import { createContext, useContext, useEffect } from "react";
import { getDictionary, defaultLocale, type Locale, type Dictionary } from "@/lib/i18n";

type Ctx = { lang: Locale; dict: Dictionary };

const LocaleCtx = createContext<Ctx | null>(null);

export function LocaleProvider({
  lang,
  dict,
  children,
}: {
  lang: Locale;
  dict: Dictionary;
  children: React.ReactNode;
}) {
  useEffect(() => {
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
  }, [lang]);
  return <LocaleCtx.Provider value={{ lang, dict }}>{children}</LocaleCtx.Provider>;
}

export function useLocale(): Ctx {
  const c = useContext(LocaleCtx);
  if (c) return c;
  // 兜底：未包裹 Provider 时回退默认语言，避免崩溃。
  return { lang: defaultLocale, dict: getDictionary(defaultLocale) };
}
