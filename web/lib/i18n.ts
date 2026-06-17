import { zh, type Dictionary } from "./dictionaries/zh";
import { en } from "./dictionaries/en";
import { ja } from "./dictionaries/ja";
import { ko } from "./dictionaries/ko";

export const locales = ["zh", "en", "ja", "ko"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "zh";

export function isLocale(x: unknown): x is Locale {
  return x === "zh" || x === "en" || x === "ja" || x === "ko";
}

const DICTS: Record<Locale, Dictionary> = { zh, en, ja, ko };

export function getDictionary(lang: string | undefined): Dictionary {
  return isLocale(lang) ? DICTS[lang] : DICTS[defaultLocale];
}

export type { Dictionary };

// 给内部路径加语言前缀；外链 / 锚点 / mailto / 已带前缀的不动。
export function withLang(lang: Locale, href: string): string {
  if (!href || !href.startsWith("/")) return href;
  if (href === "/") return `/${lang}`;
  const seg = href.split("/")[1];
  if (isLocale(seg)) return href;
  return `/${lang}${href}`;
}

// 从路径里剥离语言前缀，返回 { lang, rest }。
export function stripLang(path: string): { lang: Locale; rest: string } {
  const parts = path.split("/");
  if (isLocale(parts[1])) {
    return { lang: parts[1] as Locale, rest: "/" + parts.slice(2).join("/") };
  }
  return { lang: defaultLocale, rest: path || "/" };
}
