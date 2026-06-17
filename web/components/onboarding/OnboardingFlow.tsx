"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang, type Locale, type Dictionary } from "@/lib/i18n";
import {
  INTENTS,
  EXPERIENCES,
  sectorEmoji,
  saveOnboarding,
  type Intent,
  type Experience,
} from "@/lib/onboarding";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";
const TOTAL = 4;

type Sector = { key: string; count: number };
type Ticker = { ticker: string; name: string; sector: string | null };
type OB = Dictionary["onboarding"];

const secLabelOf = (t: OB, key: string) => (t.sectors as Record<string, string>)[key] ?? key;

export function OnboardingFlow({ sectors, tickers }: { sectors: Sector[]; tickers: Ticker[] }) {
  const { lang, dict } = useLocale();
  const t = dict.onboarding;
  const router = useRouter();
  const [step, setStep] = useState(1);
  const [intent, setIntent] = useState<Intent | null>(null);
  const [experience, setExperience] = useState<Experience | null>(null);
  const [selSectors, setSelSectors] = useState<string[]>([]);
  const [selTickers, setSelTickers] = useState<string[]>([]);

  const toggle = (list: string[], set: (v: string[]) => void, v: string) =>
    set(list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);

  const canContinue =
    intent === "find"
      ? selSectors.length > 0
      : intent === "manage"
      ? selTickers.length > 0
      : selSectors.length > 0 || selTickers.length > 0;

  const startGenerate = () => {
    saveOnboarding({ intent, experience, sectors: selSectors, tickers: selTickers });
    setStep(4);
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto theme-canvas">
      <div className="min-h-[100dvh] flex flex-col">
        {/* 顶部：品牌 + 进度 */}
        <header className="flex items-center justify-between gap-4 px-6 sm:px-10 h-20 shrink-0">
          <div className="flex items-center gap-2.5">
            <span className="w-8 h-8 rounded-xl overflow-hidden bg-white shrink-0 ring-1 ring-white/10">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`${BASE}/logo.png`} alt="redditalpha" className="w-full h-full object-contain rounded-xl" />
            </span>
            <span className="font-display font-extrabold text-cream text-[16px] tracking-tight">
              reddit<span className="text-reddit">alpha</span>
            </span>
          </div>
          {step < 4 && (
            <div className="flex items-center gap-3">
              <div className="hidden sm:flex items-center gap-1.5">
                {Array.from({ length: TOTAL }).map((_, i) => (
                  <span
                    key={i}
                    className={`h-1.5 rounded-full transition-all ${
                      i + 1 <= step ? "w-7 bg-reddit" : "w-4 bg-white/12"
                    }`}
                  />
                ))}
              </div>
              <span className="text-[12px] text-neutral-500 tabular">
                {t.stepPre}{step}{t.stepMid}{TOTAL}{t.stepPost}
              </span>
            </div>
          )}
          <LocaleLink href="/" className="text-[13px] text-neutral-500 hover:text-cream transition">
            {t.exit}
          </LocaleLink>
        </header>

        {/* 内容 */}
        <div className="flex-1 flex flex-col justify-center px-6 py-8">
          <div className="mx-auto w-full max-w-3xl">
            {step > 1 && step < 4 && (
              <button
                onClick={() => setStep(step - 1)}
                className="mb-5 inline-flex items-center gap-1.5 text-sm text-neutral-500 hover:text-cream transition"
              >
                {t.prev}
              </button>
            )}

            {step === 1 && (
              <Step eyebrow={t.step1Eyebrow} title={t.step1Title}>
                <div className="grid sm:grid-cols-3 gap-3.5">
                  {INTENTS.map((o) => (
                    <OptionCard
                      key={o.id}
                      emoji={o.emoji}
                      tagline={t.intents[o.id].tagline}
                      label={t.intents[o.id].label}
                      desc={t.intents[o.id].desc}
                      selected={intent === o.id}
                      onClick={() => {
                        setIntent(o.id);
                        setStep(2);
                      }}
                    />
                  ))}
                </div>
              </Step>
            )}

            {step === 2 && (
              <Step eyebrow={t.step2Eyebrow} title={t.step2Title}>
                <div className="grid sm:grid-cols-3 gap-3.5">
                  {EXPERIENCES.map((o) => (
                    <OptionCard
                      key={o.id}
                      emoji={o.emoji}
                      label={t.experiences[o.id].label}
                      desc={t.experiences[o.id].desc}
                      selected={experience === o.id}
                      onClick={() => {
                        setExperience(o.id);
                        setStep(3);
                      }}
                    />
                  ))}
                </div>
              </Step>
            )}

            {step === 3 && (
              <Step
                eyebrow={t.step3Eyebrow}
                title={
                  intent === "find" ? t.step3TitleFind : intent === "manage" ? t.step3TitleManage : t.step3TitleBoth
                }
                subtitle={t.step3Subtitle}
              >
                <div className="space-y-7">
                  {(intent === "find" || intent === "both") && (
                    <Module title={t.moduleSectorsTitle} hint={`${sectors.length}${t.moduleSectorsHintPost}`}>
                      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2.5">
                        {sectors.map((s) => (
                          <SelectTile
                            key={s.key}
                            selected={selSectors.includes(s.key)}
                            onClick={() => toggle(selSectors, setSelSectors, s.key)}
                            emoji={sectorEmoji(s.key)}
                            title={secLabelOf(t, s.key)}
                            sub={`${s.count}${t.tickerCountPost}`}
                          />
                        ))}
                      </div>
                    </Module>
                  )}

                  {(intent === "manage" || intent === "both") && (
                    <Module title={t.moduleTickersTitle} hint={t.moduleTickersHint}>
                      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2.5 max-h-[42vh] overflow-y-auto pr-1">
                        {tickers.map((tk) => (
                          <SelectTile
                            key={tk.ticker}
                            selected={selTickers.includes(tk.ticker)}
                            onClick={() => toggle(selTickers, setSelTickers, tk.ticker)}
                            mono={tk.ticker}
                            title={tk.name || tk.ticker}
                            sub={tk.sector ? secLabelOf(t, tk.sector) : undefined}
                          />
                        ))}
                      </div>
                    </Module>
                  )}
                </div>

                <div className="mt-8 flex items-center justify-between gap-4">
                  <span className="text-[13px] text-neutral-500">
                    {t.selected}
                    {intent !== "manage" && ` ${selSectors.length}${t.sectorsUnit}`}
                    {intent === "both" && " ·"}
                    {intent !== "find" && ` ${selTickers.length}${t.tickersUnit}`}
                  </span>
                  <button
                    disabled={!canContinue}
                    onClick={startGenerate}
                    className="inline-flex items-center gap-2 rounded-xl px-6 py-3 font-display font-bold text-white shadow-lg shadow-reddit/25 hover:brightness-110 transition disabled:opacity-40 disabled:cursor-not-allowed disabled:shadow-none"
                    style={{ backgroundImage: "var(--grad-brand)" }}
                  >
                    {t.generateBtn}
                  </button>
                </div>
              </Step>
            )}

            {step === 4 && (
              <GeneratingStep
                t={t}
                joiner={lang === "zh" ? "、" : ", "}
                intent={intent}
                sectorKeys={selSectors}
                tickerSyms={selTickers}
                onDone={() => router.push(withLang(lang, "/dashboard"))}
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function Step({
  eyebrow,
  title,
  subtitle,
  children,
}: {
  eyebrow: string;
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="eyebrow text-reddit">{eyebrow}</div>
      <h1 className="mt-2 font-display font-extrabold text-cream tracking-tight text-[clamp(24px,3.4vw,36px)] leading-tight">
        {title}
      </h1>
      {subtitle && <p className="mt-2 text-sm text-neutral-500">{subtitle}</p>}
      <div className="mt-7">{children}</div>
    </div>
  );
}

function OptionCard({
  emoji,
  tagline,
  label,
  desc,
  selected,
  onClick,
}: {
  emoji: string;
  tagline?: string;
  label: string;
  desc: string;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`text-left panel rounded-2xl p-5 transition group hover:-translate-y-0.5 ${
        selected ? "ring-2 ring-reddit" : "ring-1 ring-inset ring-white/[.06] hover:ring-reddit/40"
      }`}
    >
      <div className="text-[26px] leading-none">{emoji}</div>
      {tagline && <div className="mt-3 text-[11px] font-semibold uppercase tracking-wider text-reddit">{tagline}</div>}
      <div className="mt-1 font-display font-bold text-cream text-[17px]">{label}</div>
      <p className="mt-1.5 text-[13px] text-neutral-400 leading-relaxed">{desc}</p>
    </button>
  );
}

function Module({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-baseline gap-3 mb-3">
        <span className="w-1 h-3.5 rounded-full bg-reddit" />
        <h2 className="font-display font-bold text-cream text-[15px]">{title}</h2>
        {hint && <span className="text-xs text-neutral-600">{hint}</span>}
      </div>
      {children}
    </div>
  );
}

function SelectTile({
  selected,
  onClick,
  emoji,
  mono,
  title,
  sub,
}: {
  selected: boolean;
  onClick: () => void;
  emoji?: string;
  mono?: string;
  title: string;
  sub?: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`relative text-left rounded-xl p-3 bg-white/[.02] transition ${
        selected ? "ring-2 ring-reddit bg-reddit/[.06]" : "ring-1 ring-inset ring-white/[.07] hover:ring-white/20"
      }`}
    >
      {selected && (
        <span className="absolute top-2 right-2 grid place-items-center w-4 h-4 rounded-full bg-reddit text-white text-[10px]">
          ✓
        </span>
      )}
      <div className="flex items-center gap-2">
        {emoji && <span className="text-lg leading-none">{emoji}</span>}
        {mono && <span className="font-mono font-bold text-cream text-sm">{mono}</span>}
      </div>
      <div className={`mt-1.5 text-[13px] font-medium truncate ${mono ? "text-neutral-400" : "text-cream"}`}>
        {title}
      </div>
      {sub && <div className="text-[11px] text-neutral-600 truncate">{sub}</div>}
    </button>
  );
}

function GeneratingStep({
  t,
  joiner,
  intent,
  sectorKeys,
  tickerSyms,
  onDone,
}: {
  t: OB;
  joiner: string;
  intent: Intent | null;
  sectorKeys: string[];
  tickerSyms: string[];
  onDone: () => void;
}) {
  const lines: string[] = [t.genRead];
  if (intent !== "manage" && sectorKeys.length)
    lines.push(`${t.genMatchPre}${sectorKeys.map((k) => secLabelOf(t, k)).join(joiner)}`);
  if (intent !== "find" && tickerSyms.length)
    lines.push(`${t.genPullPre}${tickerSyms.join(joiner)}`);
  lines.push(t.genMindshare);
  lines.push(t.genAssemble);

  const [stage, setStage] = useState(0);

  useEffect(() => {
    if (stage >= lines.length) {
      saveOnboarding({ completedAt: Date.now() });
      const tm = setTimeout(onDone, 800);
      return () => clearTimeout(tm);
    }
    const tm = setTimeout(() => setStage((s) => s + 1), 760);
    return () => clearTimeout(tm);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage]);

  const pct = Math.min(100, Math.round((stage / lines.length) * 100));
  const done = stage >= lines.length;
  const C = 2 * Math.PI * 52;

  return (
    <div className="flex flex-col items-center text-center py-6">
      <div className="relative w-[150px] h-[150px]">
        <div
          className="absolute inset-0 rounded-full blur-2xl"
          style={{ background: "radial-gradient(circle, rgba(255,69,0,0.35), transparent 70%)" }}
        />
        <svg viewBox="0 0 120 120" className="relative w-full h-full -rotate-90">
          <circle cx="60" cy="60" r="52" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="6" />
          <circle
            cx="60"
            cy="60"
            r="52"
            fill="none"
            stroke="#FF4500"
            strokeWidth="6"
            strokeLinecap="round"
            strokeDasharray={C}
            strokeDashoffset={C * (1 - pct / 100)}
            style={{ transition: "stroke-dashoffset 0.6s ease" }}
          />
        </svg>
        <div className="absolute inset-0 grid place-items-center">
          <span className="font-display font-extrabold text-cream text-2xl tabular">{pct}%</span>
        </div>
      </div>

      <h1 className="mt-7 font-display font-extrabold text-cream text-2xl tracking-tight">
        {done ? t.genTitleDone : t.genTitleActive}
      </h1>

      <ul className="mt-6 w-full max-w-md mx-auto space-y-2.5 text-left">
        {lines.map((l, i) => {
          const state = i < stage ? "done" : i === stage ? "active" : "idle";
          return (
            <li
              key={i}
              className={`flex items-center gap-3 text-sm transition ${
                state === "idle" ? "opacity-35" : "opacity-100"
              }`}
            >
              <span
                className={`grid place-items-center w-5 h-5 rounded-full text-[11px] shrink-0 ${
                  state === "done"
                    ? "bg-bull/20 text-bull"
                    : state === "active"
                    ? "bg-reddit/20 text-reddit animate-pulse"
                    : "bg-white/5 text-neutral-600"
                }`}
              >
                {state === "done" ? "✓" : "•"}
              </span>
              <span className={state === "done" ? "text-neutral-300" : "text-neutral-400"}>{l}</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
