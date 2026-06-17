// 标的金融元信息（前端预设）：TradingView 交易所前缀 + logo CDN。
// gr 标的是已知固定集合（pipeline/data/global_targets.yml，40 支）。
// 全称/简写来自数据层 gr_ticker（name_en/name_zh/ticker）——这里只补 exchange 与 logo。

const EXCHANGE: Record<string, string> = {
  // NASDAQ
  NVDA: "NASDAQ", AMD: "NASDAQ", TSLA: "NASDAQ", AAPL: "NASDAQ", MSFT: "NASDAQ",
  GOOGL: "NASDAQ", AMZN: "NASDAQ", META: "NASDAQ", MU: "NASDAQ", INTC: "NASDAQ",
  AVGO: "NASDAQ", QCOM: "NASDAQ", ARM: "NASDAQ", SMCI: "NASDAQ", PLTR: "NASDAQ",
  NFLX: "NASDAQ", ASML: "NASDAQ", COIN: "NASDAQ", MSTR: "NASDAQ", MARA: "NASDAQ",
  RIOT: "NASDAQ", SOFI: "NASDAQ", HOOD: "NASDAQ", RIVN: "NASDAQ", LCID: "NASDAQ",
  PYPL: "NASDAQ", AMAT: "NASDAQ",
  // NYSE
  TSM: "NYSE", GME: "NYSE", AMC: "NYSE", NIO: "NYSE", F: "NYSE", BA: "NYSE",
  DIS: "NYSE", BABA: "NYSE", UBER: "NYSE", ORCL: "NYSE", DELL: "NYSE", PFE: "NYSE", JPM: "NYSE",
};

export function tickerExchange(ticker: string): string | null {
  return EXCHANGE[ticker.toUpperCase()] ?? null;
}

// TradingView symbol：有交易所则 "NASDAQ:NVDA"，否则裸 ticker（大盘股 TradingView 可自解析）。
export function tvSymbol(ticker: string): string {
  const t = ticker.toUpperCase();
  const ex = tickerExchange(t);
  return ex ? `${ex}:${t}` : t;
}

// 股票 logo CDN（单点，易替换）。漏图由 <TickerLogo> 的 onError 回退字母 tile。
export function tickerLogoUrl(ticker: string): string {
  return `https://assets.parqet.com/logos/symbol/${ticker.toUpperCase()}?format=png&size=96`;
}
