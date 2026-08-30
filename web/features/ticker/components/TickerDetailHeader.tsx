import { SaveButton } from "@/components/favorites/SaveButton";
import { PriceSparkline } from "@/shared/charts/PriceSparkline";
import { TickerLogo } from "@/shared/market/TickerLogo";
import { Consensus, PriceTag } from "@/shared/ui/bsmartBits";
import { StageBadge } from "@/shared/ui/detailBits";
import { fmtCompact } from "@/shared/formatting/format";
import type { GrQuoteRow, GrTickerRow } from "@/server/queries/globalQueries";
import type { Locale } from "@/lib/i18n";
import type { getKolFlow, getTickerMock } from "@/shared/market/mockDetail";
import { tickerExchange } from "@/shared/market/tickerMeta";

type TickerMock = ReturnType<typeof getTickerMock>;
type KolFlow = ReturnType<typeof getKolFlow>;
type AnomalyDim = TickerMock["anomaly"]["dims"][number];

export function TickerDetailHeader({
  ticker,
  name,
  lang,
  quote,
  flowDays,
  mock,
  topDim,
}: {
  ticker: GrTickerRow;
  name: string;
  lang: Locale;
  quote: GrQuoteRow | null;
  flowDays: KolFlow["days"];
  mock: TickerMock;
  topDim?: AnomalyDim;
}) {
  const zh = lang === "zh";
  const topSigma = topDim?.sigma ?? 0;
  const stats = [
    { label: zh ? "平均情绪" : "Sentiment", value: (ticker.avg_sentiment > 0 ? "+" : "") + ticker.avg_sentiment.toFixed(2), tone: ticker.avg_sentiment >= 0 ? "text-bull" : "text-bear" },
    { label: zh ? "风险温度" : "Risk temp", value: String(mock.risk.temp), tone: mock.risk.temp > 66 ? "text-bear" : mock.risk.temp > 40 ? "text-amber" : "text-bull" },
    { label: zh ? "多空比" : "Bull/bear", value: `${mock.bullBear.bullPct}%`, tone: mock.bullBear.bullPct >= 50 ? "text-bull" : "text-bear" },
    { label: zh ? "共识强度" : "Consensus", value: String(mock.bullBear.consensus), tone: "text-cream" },
    { label: zh ? "最强异动" : "Top anomaly", value: `${topSigma}σ`, tone: topSigma >= 4 ? "text-bear" : topSigma >= 2.5 ? "text-amber" : "text-cream" },
    { label: zh ? "讨论帖" : "Posts", value: fmtCompact(ticker.total_posts), tone: "text-cream" },
  ];

  return (
    <div className="px-1 py-1">
      <div className="flex items-center gap-x-5 gap-y-3">
        <div className="flex min-w-[220px] shrink-0 items-center gap-3">
          <TickerLogo ticker={ticker.ticker} size={44} />
          <div className="min-w-0">
            <h1 className="truncate font-display text-2xl font-extrabold leading-none tracking-tight text-cream">{name}</h1>
            <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[12.5px]">
              <span className="font-mono font-semibold text-neutral-300">{ticker.ticker}</span>
              {tickerExchange(ticker.ticker) && <span className="text-neutral-600">· {tickerExchange(ticker.ticker)}</span>}
              <Consensus value={ticker.consensus} lang={lang} />
              <StageBadge stage={mock.risk.stage} lang={lang} />
              <SaveButton kind="ticker" refId={ticker.ticker} variant="follow" size="xs" />
            </div>
          </div>
        </div>

        <div className="grid min-w-0 flex-1 grid-cols-6 divide-x divide-line overflow-hidden rounded-lg bg-white/[.012] ring-1 ring-inset ring-white/[.06]">
          {stats.map((s) => (
            <div key={s.label} className="min-w-0 px-3 py-2">
              <div className="truncate text-[10px] uppercase tracking-wide text-neutral-500">{s.label}</div>
              <div className={`mt-0.5 truncate font-display text-[17px] font-bold leading-none tabular ${s.tone}`}>{s.value}</div>
            </div>
          ))}
        </div>

        <div className="flex shrink-0 items-center gap-3">
          <div className="w-[116px]"><PriceSparkline days={flowDays} height={34} /></div>
          {quote && (
            <div className="text-right">
              <PriceTag price={quote.price} change={quote.price - quote.prev_close} changePct={quote.change_pct} />
              {quote.asof && <div className="mt-0.5 text-[10px] text-neutral-600">{zh ? "截至 " : "As of "}{quote.asof}</div>}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
