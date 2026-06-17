"use client";

import { useCallback, useEffect, useRef, useState } from "react";

export type LegendView = {
  handle: string;
  name: string;
  era: string;
  story: string;
  stat: string;
  statClass: string;
  tickers: string[];
  source: string;
  href: string;
  img: string; // 来自 X 的真实头像
  fallback: string; // 取不到时回退 Snoo
  flair: string;
  year: string;
};

// 真实头像（X），加载失败回退到 Snoo；真实头像居中裁切、Snoo 取头部。
function LegendAvatar({ img, fallback, flair }: { img: string; fallback: string; flair: string }) {
  const [err, setErr] = useState(false);
  return (
    <div className="relative shrink-0">
      <span className="grid place-items-center w-14 h-14 rounded-full overflow-hidden ring-2 ring-reddit/35 bg-white/[.04]">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={err ? fallback : img}
          alt=""
          onError={() => setErr(true)}
          className={`w-full h-full object-cover ${err ? "object-top" : "object-center"}`}
        />
      </span>
      <span className="absolute -bottom-1 -right-1 grid place-items-center w-6 h-6 rounded-full bg-surface ring-1 ring-line text-[13px]">
        {flair}
      </span>
    </div>
  );
}

// 横向「时间线」轮播：从过去到现在的 Reddit 股神，居中的那张被聚光灯打亮，其余压暗。
// 左右滑动 / 拖动 / 箭头 / 圆点 都能切换。
export function LegendsCarousel({
  legends,
  hint,
  spotlight,
}: {
  legends: LegendView[];
  hint: string;
  spotlight: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const raf = useRef(0);
  const [active, setActive] = useState(Math.floor(legends.length / 2));

  const centerOf = (el: HTMLDivElement, card: HTMLElement) =>
    card.offsetLeft - (el.clientWidth - card.offsetWidth) / 2;

  const recompute = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    cancelAnimationFrame(raf.current);
    raf.current = requestAnimationFrame(() => {
      const center = el.scrollLeft + el.clientWidth / 2;
      const cards = Array.from(el.querySelectorAll<HTMLElement>("[data-card]"));
      let best = 0;
      let bestD = Infinity;
      cards.forEach((c, i) => {
        const d = Math.abs(c.offsetLeft + c.offsetWidth / 2 - center);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      });
      setActive(best);
    });
  }, []);

  const go = useCallback((i: number) => {
    const el = ref.current;
    if (!el) return;
    const card = el.querySelectorAll<HTMLElement>("[data-card]")[i] as HTMLElement | undefined;
    if (card) el.scrollTo({ left: centerOf(el, card), behavior: "smooth" });
  }, []);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const mid = Math.floor(legends.length / 2);
    const card = el.querySelectorAll<HTMLElement>("[data-card]")[mid] as HTMLElement | undefined;
    if (card) el.scrollLeft = centerOf(el, card);
    setActive(mid);
    const onResize = () => recompute();
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="relative">
      {/* ===================== 舞台聚光灯 ===================== */}
      {/* 固定在正中：灯头灯芯 + 内外双层光锥 + 落地光池，照亮被居中的那张卡。 */}
      <div className="relative">
        {/* 灯头：顶部一颗高亮灯芯（外晕 + 暖白内核）*/}
        <div className="pointer-events-none absolute left-1/2 -translate-x-1/2 -top-2 z-0 h-2 w-24 rounded-full bg-reddit blur-[6px] opacity-70" aria-hidden />
        <div className="pointer-events-none absolute left-1/2 -translate-x-1/2 -top-[7px] z-0 h-1.5 w-9 rounded-full bg-amber-200 blur-[3px] opacity-90" aria-hidden />
        {/* 外光锥：柔和扩散的梯形光束 */}
        <div
          className="pointer-events-none absolute left-1/2 top-[-5%] -translate-x-1/2 z-0 h-[120%] w-[360px] sm:w-[460px]"
          style={{
            background: "linear-gradient(180deg, rgba(255,99,40,.24), rgba(255,69,0,.07) 50%, transparent 84%)",
            clipPath: "polygon(45% 0, 55% 0, 94% 100%, 6% 100%)",
            filter: "blur(16px)",
          }}
          aria-hidden
        />
        {/* 内光锥：更亮更窄的「热核」*/}
        <div
          className="pointer-events-none absolute left-1/2 top-[-5%] -translate-x-1/2 z-0 h-[120%] w-[180px] sm:w-[230px]"
          style={{
            background: "linear-gradient(180deg, rgba(255,160,100,.30), rgba(255,69,0,.06) 56%, transparent 80%)",
            clipPath: "polygon(46% 0, 54% 0, 82% 100%, 18% 100%)",
            filter: "blur(10px)",
          }}
          aria-hidden
        />
        {/* 落地光池：光束打到「舞台地面」的椭圆光晕，落在居中卡底部 */}
        <div
          className="pointer-events-none absolute left-1/2 -translate-x-1/2 bottom-5 z-0 h-20 w-[280px] sm:w-[360px]"
          style={{
            background: "radial-gradient(50% 60% at 50% 50%, rgba(255,69,0,.20), rgba(255,69,0,.04) 62%, transparent 76%)",
            filter: "blur(9px)",
          }}
          aria-hidden
        />

      {/* 左右箭头 */}
      <button
        type="button"
        onClick={() => go(Math.max(0, active - 1))}
        disabled={active === 0}
        aria-label="previous"
        className="absolute left-0 sm:left-1 top-1/2 -translate-y-1/2 z-20 grid place-items-center w-9 h-9 rounded-full panel ring-1 ring-inset ring-line text-neutral-400 hover:text-reddit transition disabled:opacity-25"
      >
        <Chevron dir="left" />
      </button>
      <button
        type="button"
        onClick={() => go(Math.min(legends.length - 1, active + 1))}
        disabled={active === legends.length - 1}
        aria-label="next"
        className="absolute right-0 sm:right-1 top-1/2 -translate-y-1/2 z-20 grid place-items-center w-9 h-9 rounded-full panel ring-1 ring-inset ring-line text-neutral-400 hover:text-reddit transition disabled:opacity-25"
      >
        <Chevron dir="right" />
      </button>

      {/* 滑动轨道 */}
      <div
        ref={ref}
        onScroll={recompute}
        className="relative z-10 flex items-stretch gap-5 overflow-x-auto snap-x snap-mandatory scroll-smooth py-6 px-[calc(50%-160px)] [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        style={{
          WebkitMaskImage: "linear-gradient(90deg, transparent 0, #000 13%, #000 87%, transparent 100%)",
          maskImage: "linear-gradient(90deg, transparent 0, #000 13%, #000 87%, transparent 100%)",
        }}
      >
        {legends.map((L, i) => {
          const on = i === active;
          return (
            <article
              key={L.handle}
              data-card
              className={`snap-center shrink-0 w-[320px] rounded-2xl p-5 flex flex-col panel transition-all duration-300 ease-out ${
                on
                  ? "opacity-100 scale-100 ring-1 ring-reddit/55 shadow-[0_28px_64px_-18px_rgba(255,69,0,.6),inset_0_1px_0_rgba(255,255,255,.12),inset_0_20px_44px_-22px_rgba(255,120,60,.55)]"
                  : "opacity-45 scale-[0.85] saturate-[.6] brightness-[.85]"
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="font-mono text-[11px] font-bold px-2 py-0.5 rounded-full bg-white/[.05] text-neutral-400 ring-1 ring-inset ring-white/10">
                  {L.year}
                </span>
                <span
                  className={`inline-flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider rounded-full px-2 py-0.5 transition-all duration-300 ${
                    on ? "opacity-100 text-reddit bg-reddit/[.12] ring-1 ring-inset ring-reddit/30" : "opacity-0"
                  }`}
                >
                  ★ {spotlight}
                </span>
              </div>

              <div className="mt-3 flex items-center gap-3">
                <LegendAvatar img={L.img} fallback={L.fallback} flair={L.flair} />
                <div className="min-w-0">
                  <div className="font-display font-bold text-cream text-[15px] leading-tight">{L.name}</div>
                  <div className="font-mono text-[12px] text-reddit truncate">{L.handle}</div>
                </div>
              </div>

              <div className={`mt-4 font-display font-extrabold text-[26px] leading-none tracking-tight ${L.statClass}`}>
                {L.stat}
              </div>
              <div className="mt-1 text-[11px] uppercase tracking-wider text-neutral-500">{L.era}</div>

              <p className="mt-3 text-[13px] text-neutral-400 leading-relaxed flex-1">{L.story}</p>

              <div className="mt-4 flex items-center justify-between gap-2 pt-3 border-t border-line">
                <div className="flex flex-wrap items-center gap-1.5">
                  {L.tickers.map((tk) => (
                    <span
                      key={tk}
                      className="font-mono text-[11px] px-1.5 py-0.5 rounded-md bg-reddit/10 text-reddit ring-1 ring-inset ring-reddit/20"
                    >
                      {tk}
                    </span>
                  ))}
                </div>
                <a href={L.href} target="_blank" rel="noreferrer" className="text-[11px] text-neutral-500 hover:text-reddit transition shrink-0">
                  {L.source} ↗
                </a>
              </div>
            </article>
          );
        })}
      </div>
      </div>
      {/* =================== /舞台聚光灯 =================== */}

      {/* 圆点导航 */}
      <div className="mt-1 flex items-center justify-center gap-1.5">
        {legends.map((L, i) => (
          <button
            key={L.handle}
            type="button"
            onClick={() => go(i)}
            aria-label={`go to ${i + 1}`}
            className={`h-1.5 rounded-full transition-all ${i === active ? "w-6 bg-reddit" : "w-1.5 bg-neutral-600 hover:bg-neutral-400"}`}
          />
        ))}
      </div>
      <p className="mt-2 text-center text-[11px] text-neutral-600">{hint}</p>
    </div>
  );
}

function Chevron({ dir }: { dir: "left" | "right" }) {
  return (
    <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      {dir === "left" ? <path d="M15 18l-6-6 6-6" /> : <path d="M9 18l6-6-6-6" />}
    </svg>
  );
}
