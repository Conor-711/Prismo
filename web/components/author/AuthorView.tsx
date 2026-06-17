import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel, Avatar, MiniBar, SubredditChip, ThemeTag } from "@/components/ui";
import { FeedCard } from "@/components/FeedCard";
import { SaveButton } from "@/components/favorites/SaveButton";
import { IconUpvote, IconComment } from "@/components/icons";
import { fmtInt, fmtCompact } from "@/lib/format";
import type { Locale, Dictionary } from "@/lib/i18n";
import type { getAuthorDetail, AuthorTickerStance } from "@/lib/queries";

type AuthorData = ReturnType<typeof getAuthorDetail>;

const TIERS = [
  { zh: "观察中", en: "Watchlist", chip: "bg-white/[.06] text-neutral-400", num: "text-neutral-300" },
  { zh: "潜力股", en: "On the radar", chip: "bg-bull/12 text-bull", num: "text-bull" },
  { zh: "实力派", en: "Sharp operator", chip: "bg-reddit/12 text-reddit", num: "text-reddit" },
  { zh: "准股神", en: "Rising legend", chip: "bg-gold/12 metal-text m-gold", num: "metal-text m-gold" },
];
const FACTORS = [
  { k: "cQuality", zh: "DD 质量", en: "DD quality", color: "bg-gold" },
  { k: "cInfluence", zh: "社区影响", en: "Influence", color: "bg-reddit" },
  { k: "cConviction", zh: "立场鲜明", en: "Conviction", color: "bg-bull" },
  { k: "cOutput", zh: "持续产出", en: "Output", color: "bg-silver" },
] as const;

export function AuthorView({ data, lang, t }: { data: AuthorData; lang: Locale; t: Dictionary["author"] }) {
  const zh = lang === "zh";
  const s = data.stats;
  const tier = TIERS[s.tier] ?? TIERS[0];
  const d0 = s.first?.slice(0, 10);
  const d1 = s.last?.slice(0, 10);
  const range = d0 && d1 ? (d0 === d1 ? d0 : `${d0} → ${d1}`) : null;

  return (
    <div className="space-y-5">
      {/* 顶部资料卡 */}
      <Panel className="p-5 sm:p-6">
        <div className="flex items-start gap-4">
          <Avatar name={data.name} size={64} />
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="font-display font-extrabold text-cream text-2xl truncate">u/{data.name}</h1>
              <span className={`text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full ${tier.chip}`}>
                {zh ? tier.zh : tier.en}
              </span>
              {s.library > 0 && (
                <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-white/[.05] text-neutral-400 ring-1 ring-inset ring-white/10">
                  {s.library} {t.statLibrary}
                </span>
              )}
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-neutral-400">
              <span className="inline-flex items-center gap-1"><IconUpvote className="w-3.5 h-3.5 text-reddit" />{fmtCompact(s.upvotes)}</span>
              <span className="inline-flex items-center gap-1"><IconComment className="w-3.5 h-3.5" />{fmtCompact(s.comments)}</span>
              <span>{fmtInt(s.posts)} {t.posts}</span>
              <span>{s.tickers} {zh ? "标的" : "tickers"}</span>
              {s.karma > 0 && <span>{fmtCompact(s.karma)} karma</span>}
            </div>
            {range && <div className="mt-1 text-xs text-neutral-600">{t.activeRange} · {range}</div>}
          </div>
          <div className="shrink-0">
            <SaveButton kind="author" refId={data.name} variant="follow" size="sm" />
          </div>
        </div>

        {/* 实力分 + 四维分量 */}
        {s.score != null && (
          <div className="mt-5 grid sm:grid-cols-[150px_1fr] gap-4 items-center border-t border-line pt-4">
            <div className="flex items-baseline gap-2">
              <span className={`font-display font-extrabold text-[40px] leading-none tabular ${tier.num}`}>{s.score}</span>
              <span className="text-xs text-neutral-500">{t.alpha}</span>
            </div>
            <div className="space-y-1.5">
              {FACTORS.map((f) => {
                const pct = Math.round((Number(s[f.k]) || 0) * 100);
                return (
                  <div key={f.k} className="flex items-center gap-2">
                    <span className="w-16 shrink-0 text-[10px] text-neutral-500">{zh ? f.zh : f.en}</span>
                    <MiniBar pct={pct} color={f.color} />
                    <span className="w-6 text-right text-[10px] text-neutral-500 tabular">{pct}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </Panel>

      {/* 看好 / 看空 标的 */}
      <div className="grid md:grid-cols-2 gap-4 items-start">
        <StanceCol title={t.bullish} tone="bull" items={data.bullish} empty={t.tickersEmpty} />
        <StanceCol title={t.bearish} tone="bear" items={data.bearish} empty={t.tickersEmpty} />
      </div>

      {/* 代表作 */}
      <section>
        <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[.16em] text-reddit mb-3">
          ⭐ {t.topWorks}
        </div>
        {data.posts.length ? (
          <div className="space-y-3">
            {data.posts.map((p) => <FeedCard key={p.id} p={p} />)}
          </div>
        ) : (
          <Panel className="p-6 text-sm text-neutral-600">{t.topWorksEmpty}</Panel>
        )}
      </section>

      {/* 常驻社区 + 主题 */}
      {(data.communities.length > 0 || data.themes.length > 0) && (
        <div className="grid md:grid-cols-2 gap-4">
          {data.communities.length > 0 && (
            <Panel className="p-4">
              <div className="text-[11px] font-bold uppercase tracking-wide text-neutral-500 mb-2.5">{t.communities}</div>
              <div className="flex flex-wrap items-center gap-2">
                {data.communities.map((c) => (
                  <span key={c.subreddit} className="inline-flex items-center gap-1.5">
                    <SubredditChip name={c.subreddit} />
                    <span className="text-[11px] text-neutral-600 tabular">{c.n}</span>
                  </span>
                ))}
              </div>
            </Panel>
          )}
          {data.themes.length > 0 && (
            <Panel className="p-4">
              <div className="text-[11px] font-bold uppercase tracking-wide text-neutral-500 mb-2.5">{t.themes}</div>
              <div className="flex flex-wrap gap-1.5">
                {data.themes.map((th) => <ThemeTag key={th.name}>{th.name}</ThemeTag>)}
              </div>
            </Panel>
          )}
        </div>
      )}

      <p className="text-[11px] text-neutral-600 leading-relaxed">{t.footnote}</p>
      <LocaleLink href="/leaderboard" className="inline-block text-xs text-neutral-500 hover:text-reddit transition">
        {t.backToLeaderboard}
      </LocaleLink>
    </div>
  );
}

function StanceCol({
  title, tone, items, empty,
}: {
  title: string; tone: "bull" | "bear"; items: AuthorTickerStance[]; empty: string;
}) {
  const accent = tone === "bull" ? "text-bull" : "text-bear";
  const dot = tone === "bull" ? "bg-bull" : "bg-bear";
  // 重点是「作者看好/看空哪些标的」→ 标的代码做大、自动换行成紧凑标签云；次数只做小角标。
  const metric = (it: AuthorTickerStance) => (tone === "bull" ? it.bull : it.bear);
  return (
    <Panel className="p-3.5">
      <div className="flex items-center justify-between gap-2 mb-2.5">
        <div className={`flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wide ${accent}`}>
          <i className={`w-2 h-2 rounded-full ${dot}`} />
          {title}
        </div>
        {items.length > 0 && <span className="text-[10px] text-neutral-500 tabular">{items.length}</span>}
      </div>
      {items.length ? (
        <div className="flex flex-wrap gap-1.5">
          {items.map((it) => (
            <LocaleLink
              key={it.ticker}
              href={`/ticker/${it.ticker}`}
              className="group inline-flex items-baseline gap-1 rounded-md bg-white/[.04] ring-1 ring-inset ring-white/8 px-2 py-1 hover:bg-amber/15 hover:ring-amber/30 transition"
            >
              <span className="font-mono font-bold text-[15px] leading-none text-cream group-hover:text-amber transition">{it.ticker}</span>
              <span className="font-mono text-[10px] tabular text-neutral-500">{metric(it)}</span>
            </LocaleLink>
          ))}
        </div>
      ) : (
        <p className="text-sm text-neutral-600">{empty}</p>
      )}
    </Panel>
  );
}
