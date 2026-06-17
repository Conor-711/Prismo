import type { Metadata } from "next";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import { getDataStats, getDailyBrief } from "@/lib/queries";
import { RoutineStatus } from "@/components/RoutineStatus";

// 运维看板：无导航入口、noindex（仅 URL 直达，给运营自查 routine 是否正常）。
export const metadata: Metadata = {
  title: "Routine 状态 · Prismo",
  robots: { index: false, follow: false },
};

// 构建时刻 —— 在静态导出时求值并烤进页面，用于显示「这份线上是什么时候构建/部署的」。
const BUILT_AT = new Date().toISOString();

export default function StatusPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const isZh = lang === "zh";
  const t = (zh: string, en: string) => (isZh ? zh : en);

  const stats = getDataStats();
  const brief = getDailyBrief();
  const briefDate = brief?.brief_date ?? null;
  const fmt = (s: string | null) =>
    s ? new Date(s).toLocaleString(isZh ? "zh-CN" : "en-US", { timeZone: "Asia/Shanghai", hour12: false }) : "—";

  return (
    <div className="max-w-3xl mx-auto px-4 py-10 space-y-8">
      <header>
        <div className="text-xs uppercase tracking-wider text-neutral-500">{t("内部 · 运维看板", "Internal · Ops")}</div>
        <h1 className="mt-1 font-display font-extrabold text-cream text-2xl">{t("每日 Routine 状态", "Daily Routine Status")}</h1>
        <p className="mt-1.5 text-sm text-neutral-400">
          {t("一眼确认每天的自动数据分析 + 部署是否正常运行。", "At-a-glance: is the daily auto analysis + deploy healthy?")}
        </p>
      </header>

      {/* ① GitHub 云端 routine 运行状态（实时，前端直连 GitHub 公开 API） */}
      <section className="rounded-xl ring-1 ring-inset ring-white/8 bg-white/[.02] p-5">
        <div className="text-sm font-semibold text-neutral-300 mb-3">
          ① {t("GitHub 云端 routine（实时）", "GitHub cloud routine (live)")}
        </div>
        <RoutineStatus isZh={isZh} />
      </section>

      {/* ② 当前线上构建的数据新鲜度（构建期烤入） */}
      <section className="rounded-xl ring-1 ring-inset ring-white/8 bg-white/[.02] p-5">
        <div className="text-sm font-semibold text-neutral-300 mb-3">
          ② {t("当前线上数据（这份构建）", "Current live data (this build)")}
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-4 gap-y-5 text-sm">
          <Stat label={t("最新简报日期", "Latest brief")} value={briefDate ?? "—"} accent />
          <Stat label={t("数据更新于", "Data updated")} value={fmt(stats.lastUpdated)} />
          <Stat label={t("线上构建于", "Built / deployed at")} value={fmt(BUILT_AT)} />
          <Stat label={t("帖子", "Posts")} value={String(stats.posts)} />
          <Stat label={t("已分析", "Analyzed")} value={String(stats.analyzedPosts)} />
          <Stat label={t("评论", "Comments")} value={String(stats.comments)} />
        </div>
        <p className="mt-4 text-xs text-neutral-500 leading-relaxed">
          {t(
            "「最新简报日期」= 这份线上构建所含的数据日期。若它＝今天，说明 routine 跑完且已成功部署到线上。",
            "“Latest brief” is the data date baked into this live build. If it equals today, the routine ran and deployed."
          )}
        </p>
      </section>

      {/* 判断口径 */}
      <div className="rounded-xl ring-1 ring-inset ring-white/6 bg-white/[.015] p-4 text-xs text-neutral-400 leading-relaxed">
        <span className="text-neutral-300 font-semibold">{t("怎么判断「今天正常」：", "“Healthy today” means:")}</span>
        {t(
          " ① 上方有今天的「success」绿色运行；② 「最新简报日期」＝今天。两者都满足，即数据分析与上线都正常。若①成功但②不是今天，多半是部署没触发；若①失败，点进去看日志。",
          " ① a green “success” run dated today above; ② “Latest brief” equals today. Both ⇒ all good. ① ok but ② stale ⇒ deploy didn’t trigger; ① failed ⇒ click into the run logs."
        )}
      </div>
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div>
      <div className={`font-display font-bold tabular ${accent ? "text-reddit text-base" : "text-cream"}`}>{value}</div>
      <div className="mt-0.5 text-[11px] text-neutral-500">{label}</div>
    </div>
  );
}
