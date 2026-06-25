"use client";

// 设置页「投资偏好」卡：展示 onboarding 采集的画像（关注赛道/持仓/持有习惯/投资年龄/投资金额），
// 「编辑」→ /onboarding?edit=1（复用同一向导，预填后回设置页）。
import { useEffect, useState } from "react";
import { Panel } from "@/components/ui";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { useAuth } from "@/components/auth/AuthProvider";
import { loadProfile, type UserProfile, type HoldingHabit } from "@/lib/profile";

export function InvestingPrefsCard() {
  const { dict } = useLocale();
  const t = dict.onboarding;
  const { user } = useAuth();
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [busy, setBusy] = useState(true);

  useEffect(() => {
    let active = true;
    if (!user) return;
    loadProfile(user.id).then((p) => {
      if (!active) return;
      setProfile(p);
      setBusy(false);
    });
    return () => {
      active = false;
    };
  }, [user]);

  const interests = profile?.interests ?? [];
  const holdings = profile?.holdings ?? [];
  // 持有习惯排名（兼容旧单值：无 habit_rank 时退回 [holding_habit]）。
  const habitRank: HoldingHabit[] = profile?.habit_rank?.length
    ? profile.habit_rank
    : profile?.holding_habit
    ? [profile.holding_habit]
    : [];
  const exp = profile?.experience ? t.experiences[profile.experience] : null;
  const size = profile?.portfolio_size ? t.sizes[profile.portfolio_size] : null;

  return (
    <Panel className="p-5">
      <div className="flex items-start justify-between gap-3 mb-4">
        <div>
          <h2 className="font-display font-bold text-cream">{t.acctTitle}</h2>
          <p className="text-sm text-neutral-500 mt-0.5">{t.acctDesc}</p>
        </div>
        <LocaleLink
          href="/onboarding?edit=1"
          className="shrink-0 text-xs font-semibold text-reddit hover:underline whitespace-nowrap"
        >
          {t.acctEdit} →
        </LocaleLink>
      </div>

      {busy ? (
        <div className="py-4 text-sm text-neutral-600">···</div>
      ) : (
        <dl className="space-y-3.5">
          <Row label={t.acctInterests}>
            {interests.length ? (
              <div className="flex flex-wrap gap-1.5">
                {interests.map((k) => (
                  <Chip key={k}>{t.interests[k as keyof typeof t.interests] || k}</Chip>
                ))}
              </div>
            ) : (
              <NotSet t={t} />
            )}
          </Row>

          <Row label={t.acctHoldings}>
            {holdings.length ? (
              <div className="flex flex-wrap gap-1.5">
                {holdings.map((h) => (
                  <Chip key={h} mono>
                    {h}
                  </Chip>
                ))}
              </div>
            ) : (
              <NotSet t={t} />
            )}
          </Row>

          <Row label={t.acctHabit}>
            {habitRank.length ? (
              <div className="flex flex-wrap gap-1.5">
                {habitRank.map((k, i) => (
                  <Chip key={k}>
                    {i + 1} · {t.habits[k].label}
                  </Chip>
                ))}
              </div>
            ) : (
              <NotSet t={t} />
            )}
          </Row>

          <Row label={t.acctExperience}>
            {exp ? (
              <span className="text-sm text-neutral-200">
                {exp.label} <span className="text-neutral-500">· {exp.years}</span>
              </span>
            ) : (
              <NotSet t={t} />
            )}
          </Row>

          <Row label={t.acctSize}>
            {size ? <span className="text-sm text-neutral-200">{size}</span> : <NotSet t={t} />}
          </Row>
        </dl>
      )}
    </Panel>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col sm:flex-row sm:items-start gap-1 sm:gap-4">
      <dt className="w-28 shrink-0 text-xs font-medium text-neutral-500 pt-0.5">{label}</dt>
      <dd className="min-w-0 flex-1">{children}</dd>
    </div>
  );
}

function Chip({ children, mono = false }: { children: React.ReactNode; mono?: boolean }) {
  return (
    <span
      className={`text-xs px-2 py-0.5 rounded-full bg-white/5 text-neutral-300 ring-1 ring-inset ring-line ${
        mono ? "font-display font-bold" : ""
      }`}
    >
      {children}
    </span>
  );
}

function NotSet({ t }: { t: ReturnType<typeof useLocale>["dict"]["onboarding"] }) {
  return <span className="text-sm text-neutral-600">{t.acctNotSet}</span>;
}
