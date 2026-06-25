import { OnboardingFlow, type OnbTicker } from "@/components/onboarding/OnboardingFlow";
import { getGrTickers } from "@/lib/globalQueries";
import { TICKER_UNIVERSE } from "@/lib/tickerMeta";
import { EXTRA_INSTRUMENTS } from "@/lib/instruments";

// 首登引导页。薄壳：构建期取标的全集（持仓选择器用），交给客户端向导 OnboardingFlow。
// 「标的」是广义的：个股（gr_ticker）+ ETF / 杠杆反向 / 商品 / 加密 / 债券（lib/instruments.ts）。
// [lang] 的 generateStaticParams 由 layout 提供；门禁逻辑在 OnboardingGate / 向导内部。
export default function OnboardingPage() {
  const rows = getGrTickers();
  const stocks: OnbTicker[] =
    rows.length > 0
      ? rows
          .sort((a, b) => b.total_posts - a.total_posts)
          .map((r) => ({ ticker: r.ticker, name_en: r.name_en || r.ticker, name_zh: r.name_zh || r.ticker, kind: "stock" as const }))
      : // 云端快照未含 gr_* 时的兜底（仅代码，无全称）
        TICKER_UNIVERSE.map((t) => ({ ticker: t, name_en: t, name_zh: t, kind: "stock" as const }));

  // 合并非个股标的，去重（个股优先，避免某 ETF 已在 gr 里时重复）。
  const have = new Set(stocks.map((s) => s.ticker));
  const extras = EXTRA_INSTRUMENTS.filter((i) => !have.has(i.ticker));
  const tickers: OnbTicker[] = [...stocks, ...extras];

  return <OnboardingFlow tickers={tickers} />;
}
