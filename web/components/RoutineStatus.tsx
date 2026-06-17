"use client";

// 运维看板：直连 GitHub 公开 API 实时读取「每日 routine」(daily-data.yml) 的运行记录。
// 公开仓库无需认证（浏览器可跨域请求 api.github.com）；展示最近运行的成功/失败/时间。
import { useEffect, useState } from "react";

type Run = {
  id: number;
  status: string; // queued | in_progress | completed
  conclusion: string | null; // success | failure | cancelled | null
  created_at: string;
  run_started_at?: string;
  html_url: string;
  event: string; // schedule | workflow_dispatch | ...
};

const API =
  "https://api.github.com/repos/Conor-711/reddit_alpha/actions/workflows/daily-data.yml/runs?per_page=8";

export function RoutineStatus({ isZh }: { isZh: boolean }) {
  const [runs, setRuns] = useState<Run[] | null>(null);
  const [err, setErr] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    fetch(API, { headers: { Accept: "application/vnd.github+json" } })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((d) => {
        setRuns((d.workflow_runs as Run[]) || []);
        setErr(false);
      })
      .catch(() => setErr(true))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);

  const t = (zh: string, en: string) => (isZh ? zh : en);
  const fmt = (s: string) =>
    new Date(s).toLocaleString(isZh ? "zh-CN" : "en-US", { timeZone: "Asia/Shanghai", hour12: false });

  const last = runs && runs[0];
  let tone: keyof typeof toneClass = "neutral";
  let verdict = t("加载中…", "Loading…");
  if (err) {
    tone = "warn";
    verdict = t("暂时读不到 GitHub（限流或网络），稍后刷新", "Can't reach GitHub (rate-limit/network), retry later");
  } else if (last) {
    const ageH = (Date.now() - new Date(last.run_started_at || last.created_at).getTime()) / 3.6e6;
    if (last.status !== "completed") {
      tone = "run";
      verdict = t("🔄 routine 正在云端运行中…", "🔄 Routine is running now…");
    } else if (last.conclusion === "success" && ageH < 27) {
      tone = "ok";
      verdict = t("✅ 今日 routine 已成功运行", "✅ Routine ran successfully today");
    } else if (last.conclusion === "success") {
      tone = "warn";
      verdict = t(
        `⚠️ 最近一次成功，但在约 ${Math.round(ageH)} 小时前（今日可能尚未运行）`,
        `⚠️ Last success was ~${Math.round(ageH)}h ago (may not have run today)`
      );
    } else {
      tone = "bad";
      verdict = t(`❌ 最近一次运行失败（${last.conclusion || last.status}）`, `❌ Last run failed (${last.conclusion || last.status})`);
    }
  } else if (!loading) {
    tone = "warn";
    verdict = t("还没有任何运行记录（routine 可能未触发过）", "No runs yet");
  }

  return (
    <div>
      <div className={`text-lg font-display font-bold ${toneClass[tone]}`}>{verdict}</div>
      <div className="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-neutral-500">
        <button onClick={load} className="underline hover:text-neutral-300">{t("↻ 刷新", "↻ Refresh")}</button>
        <a
          href="https://github.com/Conor-711/reddit_alpha/actions/workflows/daily-data.yml"
          target="_blank"
          rel="noreferrer"
          className="underline hover:text-neutral-300"
        >
          {t("在 GitHub 查看全部", "View all on GitHub")}
        </a>
        <span>{t("时间为北京时间", "Times in Beijing time")}</span>
      </div>

      <div className="mt-4 space-y-1">
        {runs?.slice(0, 6).map((r) => {
          const running = r.status !== "completed";
          const ok = r.conclusion === "success";
          const dot = running ? "bg-sky-400 animate-pulse" : ok ? "bg-emerald-400" : r.conclusion ? "bg-red-400" : "bg-neutral-500";
          const label = running ? t("运行中", "running") : r.conclusion || r.status;
          return (
            <a
              key={r.id}
              href={r.html_url}
              target="_blank"
              rel="noreferrer"
              className="flex items-center gap-3 text-sm hover:bg-white/[.03] rounded px-2 py-1.5 -mx-2 transition"
            >
              <span className={`w-2 h-2 rounded-full shrink-0 ${dot}`} />
              <span className="w-16 text-neutral-300 shrink-0">{label}</span>
              <span className="text-neutral-500 text-xs flex-1 truncate">{fmt(r.run_started_at || r.created_at)}</span>
              <span className="text-neutral-600 text-[11px] shrink-0">
                {r.event === "schedule" ? t("定时", "scheduled") : r.event === "workflow_dispatch" ? t("手动", "manual") : r.event}
              </span>
            </a>
          );
        })}
        {loading && !runs && <div className="text-sm text-neutral-500">{t("加载中…", "Loading…")}</div>}
      </div>
    </div>
  );
}

const toneClass = {
  ok: "text-emerald-400",
  bad: "text-red-400",
  warn: "text-amber-400",
  run: "text-sky-400",
  neutral: "text-neutral-400",
};
