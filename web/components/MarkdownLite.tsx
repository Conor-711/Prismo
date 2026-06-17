"use client";

// 极简 markdown 渲染 + 投资者友好排版（配合 globals.css 的 .prose-post）：
// - 首段=lead(更大) / ## ### 标题(加粗带分隔线) / > 引用 / **粗体** / 列表 / --- 分隔线
// - $TICKER 现金标 → 可点的橙色 ticker 链接；金额/百分比/倍数 → 等宽着色
import { useLocale } from "./i18n/LocaleProvider";
import { withLang, type Locale } from "@/lib/i18n";

function esc(s: string): string {
  // 同时转义引号：链接 URL 会被放进 href="..."，不转义引号则不可信内容可突破属性（XSS）。
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function fmtInline(s: string, lang: Locale): string {
  let h = esc(s);
  const tokens: string[] = [];
  const stash = (html: string) => String.fromCharCode(0xe000 + tokens.push(html) - 1);

  h = h.replace(/`([^`]+)`/g, (_m, c) => stash(`<code class="px-1 py-0.5 rounded bg-white/8 text-amber text-[0.9em] font-mono">${c}</code>`));
  h = h.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, (_m, t, u) => stash(`<a href="${u}" target="_blank" rel="noreferrer" class="text-amber hover:underline">${t}</a>`));
  h = h.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  h = h.replace(/~~([^~]+)~~/g, "<del>$1</del>");
  h = h.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, "$1<em>$2</em>");
  h = h.replace(/(^|[^\w$])\$([A-Za-z]{1,5})\b/g, (_m, pre, t) =>
    pre + stash(`<a href="${withLang(lang, `/ticker/${t.toUpperCase()}/`)}" class="font-mono font-semibold text-reddit hover:underline">$${t.toUpperCase()}</a>`));
  h = h.replace(/(^|[^\w])([+\-]\d[\d,]*(?:\.\d+)?\s?%)/g, (_m, pre, num) => {
    const cls = num.trim().startsWith("-") ? "text-bear" : "text-bull";
    return pre + `<span class="font-mono tabular font-medium ${cls}">${num}</span>`;
  });
  h = h.replace(
    /(^|[^\w$])(\$\d[\d,]*(?:\.\d+)?[kKmMbB]?|\d[\d,]*(?:\.\d+)?\s?%|\d[\d,]*(?:\.\d+)?[kKmMbBxX])\b/g,
    (_m, pre, num) => pre + `<span class="font-mono tabular text-cream font-medium">${num}</span>`
  );

  h = h.replace(/[-]/g, (m) => tokens[m.charCodeAt(0) - 0xe000] ?? m);
  return h;
}

export function MarkdownLite({ md, size = "sm" }: { md: string; size?: "sm" | "base" }) {
  const { lang } = useLocale();
  const cleaned = (md || "").replace(/[​‌‍]/g, "").replace(/&#x200[bB];/g, "");
  const lines = cleaned.split("\n");
  const out: React.ReactNode[] = [];
  let buf: string[] = [];
  let bufType: "ul" | "ol" | null = null;
  let key = 0;
  let firstPara = true;

  const fmt = (s: string) => fmtInline(s, lang);

  const flush = () => {
    if (!buf.length) return;
    if (bufType === "ol") {
      out.push(
        <ol key={key++} className="pl-5 list-decimal marker:text-reddit/70 marker:font-semibold">
          {buf.map((l, i) => (
            <li key={i} className="pl-1" dangerouslySetInnerHTML={{ __html: fmt(l) }} />
          ))}
        </ol>
      );
    } else {
      out.push(
        <ul key={key++} className="pl-1">
          {buf.map((l, i) => (
            <li key={i} className="flex gap-2.5">
              <span className="mt-[0.62em] w-1.5 h-1.5 rounded-full bg-reddit/70 shrink-0" />
              <span dangerouslySetInnerHTML={{ __html: fmt(l) }} />
            </li>
          ))}
        </ul>
      );
    }
    buf = [];
    bufType = null;
  };

  for (const raw of lines) {
    const line = raw.trimEnd();
    if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
      flush();
      out.push(<hr key={key++} />);
    } else if (/^###\s+/.test(line)) {
      flush();
      out.push(<h3 key={key++} dangerouslySetInnerHTML={{ __html: fmt(line.replace(/^###\s+/, "")) }} />);
    } else if (/^##\s+/.test(line)) {
      flush();
      out.push(<h2 key={key++} dangerouslySetInnerHTML={{ __html: fmt(line.replace(/^##\s+/, "")) }} />);
    } else if (/^#\s+/.test(line)) {
      flush();
      out.push(<h2 key={key++} dangerouslySetInnerHTML={{ __html: fmt(line.replace(/^#\s+/, "")) }} />);
    } else if (/^>\s?/.test(line)) {
      flush();
      out.push(<blockquote key={key++} dangerouslySetInnerHTML={{ __html: fmt(line.replace(/^>\s?/, "")) }} />);
    } else if (/^\d+\.\s+/.test(line)) {
      if (bufType !== "ol") flush();
      bufType = "ol";
      buf.push(line.replace(/^\d+\.\s+/, ""));
    } else if (/^[-*]\s+/.test(line)) {
      if (bufType !== "ul") flush();
      bufType = "ul";
      buf.push(line.replace(/^[-*]\s+/, ""));
    } else if (line.trim() === "") {
      flush();
    } else {
      flush();
      const cls = size === "base" && firstPara ? "lead" : undefined;
      firstPara = false;
      out.push(<p key={key++} className={cls} dangerouslySetInnerHTML={{ __html: fmt(line) }} />);
    }
  }
  flush();
  return <div className={`prose-post ${size === "base" ? "text-[15.5px] sm:text-base" : "text-[13.5px]"}`}>{out}</div>;
}
