"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  getOnboarding,
  isGuest,
  ONBOARDING_EVENT,
  intentLabel,
  experienceLabel,
  sectorLabel,
  type OnboardingState,
} from "@/lib/onboarding";
import { fmtInt, sentTextClass } from "@/lib/format";

type TickerLite = {
  ticker: string; name: string; sector: string | null;
  mindshare: number; sentiment: number; mentions: number;
};
type Narrative = {
  id: number; slug: string; name: string; summary: string;
  heat: number; tickers: { ticker: string; weight: number }[];
};
type Bundle = { tickers: TickerLite[]; narratives: Narrative[] };

export function PersonalizedHome({ bundle }: { bundle: Bundle }) {
  const [ob, setOb] = useState<OnboardingState | null>(null);
  const [guest, setGuest] = useState(false);

  useEffect(() => {
    const load = () => {
      setOb(getOnboarding());
      setGuest(isGuest());
    };
    load();
    window.addEventListener(ONBOARDING_EVENT, load);
    return () => window.removeEventListener(ONBOARDING_EVENT, load);
  }, []);

  // 未完成引导 → 轻提示，引导去 /onboarding
  if (!ob || !ob.completedAt) {
    return (
      <Link
        href="/onboarding"
        className="panel rounded-2xl px-5 py-4 flex items-center justify-between gap-4 hover:-translate-y-0.5 transition group"
        style={{ boxShadow: "inset 0 0 0 1px rgba(255,69,0,0.22), 0 6px 22px rgba(0,0,0,0.38)" }}
      >
        <div>
          <div className="font-display font-bold text-cream">想要为你定制的情报？</div>
          <div className="text-sm text-neutral-400 mt-0.5">60 秒引导，redditalpha 只给你看该看的标的与叙事。</div>
        </div>
        <span
          className="inline-flex items-center gap-1.5 rounded-lg px-4 py-2 font-display font-bold text-white text-sm shrink-0 group-hover:brightness-110 transition"
          style={{ backgroundImage: "var(--grad-brand)" }}
        >
          开始 →
        </span>
      </Link>
    );
  }

  const byTicker = new Map(bundle.tickers.map((t) => [t.ticker, t]));
  const held = (ob.tickers || [])
    .map((s) => byTicker.get(s))
    .filter((t): t is TickerLite => Boolean(t));
  const heldSet = new Set(held.map((t) => t.ticker));
  const sectorSet = new Set(ob.sectors || []);
  const recommended = bundle.tickers
    .filter((t) => t.sector && sectorSet.has(t.sector) && !heldSet.has(t.ticker))
    .slice(0, 8);

  const focus = new Set<string>([...heldSet, ...recommended.map((t) => t.ticker)]);
  const relNarr = bundle.narratives.filter((n) => n.tickers.some((x) => focus.has(x.ticker))).slice(0, 3);

  const showHeld = (ob.intent === "manage" || ob.intent === "both") && held.length > 0;
  const showRec = (ob.intent === "find" || ob.intent === "both") && recommended.length > 0;

  const sectorNames = (ob.sectors || []).map(sectorLabel);
  const meta = [
    intentLabel(ob.intent),
    experienceLabel(ob.experience),
    sectorNames.length ? `领域：${sectorNames.join("、")}` : "",
    (ob.tickers || []).length ? `持仓：${ob.tickers.join("、")}` : "",
  ].filter(Boolean);

  return (
    <section
      className="panel rounded-2xl p-5 sm:p-6"
      style={{ boxShadow: "inset 0 0 0 1px rgba(255,69,0,0.20), 0 8px 26px rgba(0,0,0,0.42)" }}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <span className="eyebrow text-reddit">为你定制</span>
            {guest && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-md bg-white/8 text-neutral-400 ring-1 ring-inset ring-white/10">
                游客
              </span>
            )}
          </div>
          <h2 className="mt-1.5 font-display font-extrabold text-cream text-[22px] leading-none tracking-tight">
            这是今天该看的
          </h2>
          <p className="mt-2 text-sm text-neutral-500">{meta.join(" · ")}</p>
        </div>
        <Link href="/onboarding" className="text-xs text-neutral-500 hover:text-reddit transition shrink-0">
          重新设置 →
        </Link>
      </div>

      {ob.experience === "beginner" && (
        <p className="mt-3 text-[12px] text-neutral-500 bg-white/[.02] rounded-lg px-3 py-2 ring-1 ring-inset ring-white/[.06]">
          新手提示：<span className="text-bull">绿色=社区看多</span>、<span className="text-bear">红色=看空</span>；「份额」越高代表讨论越集中。
        </p>
      )}

      <div className="mt-5 space-y-5">
        {showHeld && (
          <Block title="你的持仓" hint="社区当前怎么看">
            <Grid>
              {held.map((t) => (
                <TickerMini key={t.ticker} t={t} />
              ))}
            </Grid>
          </Block>
        )}

        {showRec && (
          <Block title="为你筛选" hint={sectorNames.join(" · ") || "你关注的领域"}>
            <Grid>
              {recommended.map((t) => (
                <TickerMini key={t.ticker} t={t} />
              ))}
            </Grid>
          </Block>
        )}

        {relNarr.length > 0 && (
          <Block title="相关叙事" hint="围绕你关注的标的">
            <div className="grid sm:grid-cols-3 gap-3">
              {relNarr.map((n) => (
                <Link
                  key={n.id}
                  href="/narratives"
                  className="rounded-xl p-3.5 bg-white/[.02] ring-1 ring-inset ring-white/[.07] hover:ring-reddit/40 transition block"
                >
                  <div className="font-display font-semibold text-cream text-sm">{n.name}</div>
                  <p className="mt-1 text-xs text-neutral-500 line-clamp-2 leading-relaxed">{n.summary}</p>
                </Link>
              ))}
            </div>
          </Block>
        )}

        {!showHeld && !showRec && (
          <p className="text-sm text-neutral-500">
            你选择的标的暂无实时讨论——看看下面的全站概览，或
            <Link href="/onboarding" className="text-reddit hover:underline ml-1">
              调整你的关注
            </Link>
            。
          </p>
        )}
      </div>
    </section>
  );
}

function Block({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-baseline gap-3 mb-3">
        <span className="w-1 h-3.5 rounded-full bg-reddit" />
        <h3 className="font-display font-bold text-cream text-[15px]">{title}</h3>
        {hint && <span className="text-xs text-neutral-600 truncate">{hint}</span>}
      </div>
      {children}
    </div>
  );
}

function Grid({ children }: { children: React.ReactNode }) {
  return <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">{children}</div>;
}

function TickerMini({ t }: { t: TickerLite }) {
  return (
    <Link
      href={`/ticker/${t.ticker}`}
      className="rounded-xl p-3 bg-white/[.02] ring-1 ring-inset ring-white/[.07] hover:ring-reddit/40 transition group block"
    >
      <div className="flex items-center justify-between gap-2">
        <span className="font-mono font-bold text-cream group-hover:text-reddit transition">{t.ticker}</span>
        <span className={`font-mono text-xs tabular ${sentTextClass(t.sentiment)}`}>
          {t.sentiment > 0 ? "+" : ""}
          {t.sentiment.toFixed(2)}
        </span>
      </div>
      <div className="mt-1 text-[12px] text-neutral-500 truncate">{t.name}</div>
      <div className="mt-2 flex items-center justify-between text-[11px] text-neutral-600">
        <span>{fmtInt(t.mentions)} 提及</span>
        <span className="tabular">{t.mindshare.toFixed(1)}% 份额</span>
      </div>
    </Link>
  );
}
