"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

export function AuthShell({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}) {
  const { dict } = useLocale();
  const h = dict.authHero;

  return (
    <div className="fixed inset-0 z-50 bg-ink overflow-y-auto">
      <div className="min-h-full grid lg:grid-cols-[1.05fr_1fr]">
        {/* 左：品牌 / 价值主张（桌面端显示） */}
        <aside
          className="relative hidden lg:flex flex-col justify-between overflow-hidden border-r border-line p-10 xl:p-14"
          style={{ background: "linear-gradient(160deg, #0d1b2e 0%, #0b0b0d 62%)" }}
        >
          <div
            className="pointer-events-none absolute -top-28 -left-24 h-[440px] w-[440px] rounded-full"
            style={{ background: "radial-gradient(circle, rgba(255,69,0,.16), transparent 65%)" }}
          />
          <LocaleLink href="/" className="relative z-10 flex items-center gap-2.5">
            <span className="h-9 w-9 overflow-hidden rounded-xl bg-white ring-1 ring-white/10">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`${BASE}/logo.png`} alt="redditalpha" className="h-full w-full rounded-xl object-contain" />
            </span>
            <span className="font-display text-xl font-extrabold text-white">
              reddit<span className="text-reddit">alpha</span>
            </span>
          </LocaleLink>

          <div className="relative z-10 max-w-md">
            <h2 className="font-display text-[28px] font-extrabold leading-tight tracking-tight text-white xl:text-[34px]">
              {h.headline}
            </h2>
            <p className="mt-3 leading-relaxed text-white/70">{h.sub}</p>
            <ul className="mt-9 space-y-5">
              <Feature title={h.f1Title} desc={h.f1Desc} icon={<IconData />} />
              <Feature title={h.f2Title} desc={h.f2Desc} icon={<IconSpark />} />
              <Feature title={h.f3Title} desc={h.f3Desc} icon={<IconBookmark />} />
            </ul>
          </div>

          <div className="relative z-10 flex items-center gap-2 text-xs text-white/45">
            <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-bull" />
            {h.trust}
          </div>
        </aside>

        {/* 右：表单 */}
        <main
          className="grid place-items-center p-4 sm:p-6"
          style={{ backgroundImage: "radial-gradient(70% 50% at 50% 0%, rgba(255,69,0,.06), transparent 70%)" }}
        >
          <div className="w-full max-w-[400px] py-8">
            {/* 移动端 logo（桌面端在左栏） */}
            <LocaleLink href="/" className="mb-6 flex items-center justify-center gap-2 lg:hidden">
              <span className="h-8 w-8 overflow-hidden rounded-xl bg-white ring-1 ring-white/10">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`${BASE}/logo.png`} alt="redditalpha" className="h-full w-full rounded-xl object-contain" />
              </span>
              <span className="font-display text-xl font-extrabold text-cream">
                reddit<span className="text-reddit">alpha</span>
              </span>
            </LocaleLink>

            <div className="panel rounded-2xl p-6 shadow-2xl shadow-black/40 ring-1 ring-inset ring-white/[.06] sm:p-8">
              <h1 className="text-center font-display text-2xl font-extrabold tracking-tight text-cream">{title}</h1>
              {subtitle && <p className="mt-2 text-center text-sm leading-relaxed text-neutral-500">{subtitle}</p>}
              <div className="mt-7">{children}</div>
            </div>

            {footer && <div className="mt-5 text-center text-sm text-neutral-500">{footer}</div>}

            <div className="mt-6 text-center">
              <LocaleLink href="/" className="text-xs text-neutral-600 transition hover:text-neutral-400">
                ← {dict.common.backToDashboard}
              </LocaleLink>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

function Feature({ icon, title, desc }: { icon: React.ReactNode; title: string; desc: string }) {
  return (
    <li className="flex gap-3.5">
      <span className="mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/20">
        {icon}
      </span>
      <div>
        <div className="font-display text-[15px] font-bold text-white">{title}</div>
        <div className="text-sm leading-relaxed text-white/55">{desc}</div>
      </div>
    </li>
  );
}

function IconData() {
  return (
    <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 3v18h18" />
      <rect x="7" y="12" width="3" height="6" rx="1" fill="currentColor" stroke="none" />
      <rect x="12.5" y="8" width="3" height="10" rx="1" fill="currentColor" stroke="none" />
      <rect x="18" y="5" width="3" height="13" rx="1" fill="currentColor" stroke="none" />
    </svg>
  );
}
function IconSpark() {
  return (
    <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="currentColor">
      <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8L12 2z" />
      <path d="M19 14l.9 2.6L22 17.5l-2.1.9L19 21l-.9-2.6L16 17.5l2.1-.9L19 14z" opacity=".7" />
    </svg>
  );
}
function IconBookmark() {
  return (
    <svg viewBox="0 0 24 24" className="h-[18px] w-[18px]" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 4h12a1 1 0 0 1 1 1v15l-7-4-7 4V5a1 1 0 0 1 1-1z" />
    </svg>
  );
}
