import { Panel, Avatar, MiniBar, TickerChip } from "@/components/ui";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { IconUpvote, IconComment, IconArrow } from "@/components/icons";
import { fmtInt, fmtCompact } from "@/lib/format";
import { getLeaderboard, type AuthorRow } from "@/lib/queries";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

const TIERS = [
  { zh: "观察中", en: "Watchlist", chip: "bg-white/[.06] text-neutral-400", num: "text-neutral-300" },
  { zh: "潜力股", en: "On the radar", chip: "bg-bull/12 text-bull", num: "text-bull" },
  { zh: "实力派", en: "Sharp operator", chip: "bg-reddit/12 text-reddit", num: "text-reddit" },
  { zh: "准股神", en: "Rising legend", chip: "bg-gold/12 metal-text m-gold", num: "metal-text m-gold" },
];

const COMPS: { k: keyof AuthorRow; zh: string; en: string; color: string }[] = [
  { k: "cQuality", zh: "DD 质量", en: "DD quality", color: "bg-gold" },
  { k: "cInfluence", zh: "社区影响", en: "Influence", color: "bg-reddit" },
  { k: "cConviction", zh: "立场鲜明", en: "Conviction", color: "bg-bull" },
  { k: "cOutput", zh: "持续产出", en: "Output", color: "bg-silver" },
];

export default function LeaderboardPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const rows = getLeaderboard(24);
  const top3 = rows.slice(0, 3);
  const rest = rows.slice(3);

  return (
    <div className="space-y-5">
      {/* 头部 · 叙事 */}
      <div className="pb-4 border-b border-line">
        <div className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-[.16em] text-reddit">
          🏆 {zh ? "下一个股神 · 实力榜" : "Next legend · power ranking"}
        </div>
        <h1 className="mt-2 font-display font-extrabold text-cream tracking-tight text-[clamp(22px,3.4vw,30px)] leading-tight">
          {zh ? "发掘下一个来自 Reddit 的" : "Find the next "}
          <span className="metal-text m-gold">{zh ? "股神" : "Reddit legend"}</span>
        </h1>
        <p className="mt-2 text-sm text-neutral-500 max-w-3xl leading-relaxed">
          {zh
            ? "Alpha 实力分综合每位作者的「DD 质量 × 社区影响力 × 立场鲜明度 × 持续产出」——在他们成名之前，先一步发现下一个 DeepFuckingValue。"
            : "The Alpha Score blends each author's DD quality × community influence × conviction × consistency — to spot the next DeepFuckingValue before the crowd does."}
        </p>
        {/* 方法论 */}
        <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[11px] text-neutral-500">
          {COMPS.map((c, i) => (
            <span key={c.k} className="inline-flex items-center gap-1.5">
              <i className={`w-2 h-2 rounded-sm ${c.color}`} />
              {zh ? c.zh : c.en}
              <span className="text-neutral-600">{[30, 30, 20, 20][i]}%</span>
            </span>
          ))}
        </div>
      </div>

      {/* 领奖台 · Top 3 */}
      <div className="grid md:grid-cols-3 gap-4">
        {top3.map((r, i) => (
          <article
            key={r.author}
            className={`relative group cursor-pointer panel rounded-2xl p-5 flex flex-col panel-hover ${
              i === 0 ? "ring-1 ring-inset ring-gold/40" : ""
            }`}
          >
            {/* 整卡可点 → 作者主页（拉伸式链接，标的 chip 用 z-10 保持单独可点） */}
            <LocaleLink
              href={`/author/${encodeURIComponent(r.author)}`}
              aria-label={zh ? `查看 u/${r.author} 主页` : `View u/${r.author}`}
              className="absolute inset-0 z-0 rounded-2xl"
            />

            <div className="flex items-center justify-between">
              <span className={`grid place-items-center w-7 h-7 rounded-full text-[12px] font-extrabold metal-fill ${i === 0 ? "m-gold" : i === 1 ? "m-silver" : "m-bronze"}`}>
                {i + 1}
              </span>
              <span className={`text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full ${TIERS[r.tier].chip}`}>
                {zh ? TIERS[r.tier].zh : TIERS[r.tier].en}
              </span>
            </div>

            <div className="mt-3 flex items-center gap-3">
              <span className="shrink-0 inline-flex rounded-full ring-2 ring-transparent group-hover:ring-reddit/50 transition">
                <Avatar name={r.author} size={48} />
              </span>
              <div className="min-w-0">
                <span className="flex items-center gap-1 font-display font-bold text-cream group-hover:text-reddit transition">
                  <span className="truncate">u/{r.author}</span>
                  <IconArrow className="w-3.5 h-3.5 shrink-0 text-neutral-500 group-hover:text-reddit group-hover:translate-x-0.5 transition" />
                </span>
                <div className="flex items-baseline gap-1.5">
                  <span className={`font-display font-extrabold text-[28px] leading-none tabular ${TIERS[r.tier].num}`}>{r.score}</span>
                  <span className="text-[11px] text-neutral-500">{zh ? "实力分" : "Alpha"}</span>
                </div>
              </div>
            </div>

            <div className="mt-4">
              <Bars r={r} zh={zh} />
            </div>

            <div className="mt-4 pt-3 border-t border-line flex items-center gap-x-3 gap-y-1 flex-wrap text-xs text-neutral-500">
              <span className="inline-flex items-center gap-1"><IconUpvote className="w-3.5 h-3.5 text-reddit" />{fmtCompact(r.upvotes)}</span>
              <span className="inline-flex items-center gap-1"><IconComment className="w-3.5 h-3.5" />{fmtCompact(r.comments)}</span>
              <span>{fmtInt(r.posts)} {zh ? "帖" : "posts"}</span>
              <span>{r.tickers} {zh ? "标的" : "tickers"}</span>
            </div>

            {r.topTickers.length > 0 && (
              <div className="relative z-10 mt-3 flex flex-wrap items-center gap-1.5">
                {r.topTickers.slice(0, 3).map((tk) => (
                  <TickerChip key={tk} ticker={tk} size="xs" />
                ))}
              </div>
            )}
          </article>
        ))}
      </div>

      {/* 完整榜单 */}
      <Panel className="p-2 sm:p-4">
        <div className="hidden sm:grid grid-cols-[40px_1fr_120px_1.3fr_150px_88px] items-center gap-3 px-3 py-2 text-[11px] text-neutral-500 uppercase tracking-wide">
          <span className="text-right">#</span>
          <span>{zh ? "作者" : "Author"}</span>
          <span>{zh ? "实力分" : "Alpha"}</span>
          <span>{zh ? "四维分量" : "Factors"}</span>
          <span>{zh ? "标的" : "Tickers"}</span>
          <span className="text-right">{zh ? "赞" : "Upvotes"}</span>
        </div>
        <div className="space-y-0.5">
          {rest.map((r, i) => (
            <div
              key={r.author}
              className="relative group grid grid-cols-[28px_1fr_auto] sm:grid-cols-[40px_1fr_120px_1.3fr_150px_88px] items-center gap-3 px-3 py-2.5 rounded-lg cursor-pointer hover:bg-white/[.03] transition"
            >
              <LocaleLink
                href={`/author/${encodeURIComponent(r.author)}`}
                aria-label={zh ? `查看 u/${r.author} 主页` : `View u/${r.author}`}
                className="absolute inset-0 z-0 rounded-lg"
              />
              <span className="text-right text-xs text-neutral-600 tabular">{i + 4}</span>
              <span className="flex items-center gap-2 min-w-0">
                <span className="shrink-0 inline-flex rounded-full ring-2 ring-transparent group-hover:ring-reddit/50 transition">
                  <Avatar name={r.author} size={26} />
                </span>
                <span className="min-w-0">
                  <span className="flex items-center gap-1 font-medium text-cream group-hover:text-reddit transition">
                    <span className="truncate">u/{r.author}</span>
                    <IconArrow className="w-3 h-3 shrink-0 text-neutral-500 opacity-0 group-hover:opacity-100 group-hover:text-reddit transition" />
                  </span>
                  <span className={`text-[10px] ${TIERS[r.tier].num}`}>{zh ? TIERS[r.tier].zh : TIERS[r.tier].en}</span>
                </span>
              </span>
              <span className="flex items-baseline gap-1">
                <span className={`font-display font-extrabold text-lg tabular ${TIERS[r.tier].num}`}>{r.score}</span>
              </span>
              <span className="hidden sm:block">
                <Bars r={r} zh={zh} compact />
              </span>
              <span className="relative z-10 hidden sm:flex flex-wrap items-center gap-1">
                {r.topTickers.slice(0, 3).map((tk) => (
                  <TickerChip key={tk} ticker={tk} size="xs" />
                ))}
              </span>
              <span className="hidden sm:inline-flex items-center justify-end gap-1 text-sm text-neutral-400 tabular">
                <IconUpvote className="w-3.5 h-3.5 text-reddit" />{fmtCompact(r.upvotes)}
              </span>
            </div>
          ))}
          {rows.length === 0 && (
            <div className="px-3 py-6 text-sm text-neutral-600">{zh ? "暂无数据。" : "No data yet."}</div>
          )}
        </div>
      </Panel>

      <p className="text-[11px] text-neutral-600 leading-relaxed">
        {zh
          ? "* 实力分基于公开内容质量与社区互动（赞、评论、立场、产出）计算，反映「潜力」而非真实盈亏（无价格回测）。仅供研究，非投资建议。"
          : "* The Alpha Score is computed from public content quality and community engagement (upvotes, comments, conviction, output). It reflects potential, not realized P&L (no price backtest). Research only, not investment advice."}
      </p>
    </div>
  );
}

function Bars({ r, zh, compact = false }: { r: AuthorRow; zh: boolean; compact?: boolean }) {
  return (
    <div className={compact ? "space-y-1" : "space-y-1.5"}>
      {COMPS.map((c) => {
        const pct = Math.round((Number(r[c.k]) || 0) * 100);
        return (
          <div key={c.k} className="flex items-center gap-2">
            {!compact && <span className="w-14 text-[10px] text-neutral-500 shrink-0">{zh ? c.zh : c.en}</span>}
            <MiniBar pct={pct} color={c.color} />
            <span className="w-6 text-right text-[10px] text-neutral-500 tabular">{pct}</span>
          </div>
        );
      })}
    </div>
  );
}
