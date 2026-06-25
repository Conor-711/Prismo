// 「标的」是广义的：除个股外，也含 ETF、杠杆/反向、商品、加密、债券等衍生/被动产品。
// 个股来自数据层 gr_ticker；这里补一批常见的非个股标的（静态、固定集合）。
// logo 仍走 parqet CDN，缺图由 <Logo> 回退字母兑底。

export type InstrumentKind = "stock" | "etf" | "leveraged" | "commodity" | "crypto" | "bond";

export interface Instrument {
  ticker: string;
  name_en: string;
  name_zh: string;
  kind: InstrumentKind;
}

// 持仓选择器里类别筛选的展示顺序（"all" 在组件里单独置前）。
export const INSTRUMENT_KINDS: InstrumentKind[] = ["stock", "etf", "leveraged", "commodity", "crypto", "bond"];

// 非个股标的（ETF / 杠杆反向 / 商品 / 加密 / 债券）。
export const EXTRA_INSTRUMENTS: Instrument[] = [
  // —— ETF · 指数 / 宽基 / 行业 / 主题 ——
  { ticker: "SPY", name_en: "S&P 500 ETF", name_zh: "标普500 ETF", kind: "etf" },
  { ticker: "QQQ", name_en: "Nasdaq 100 ETF", name_zh: "纳指100 ETF", kind: "etf" },
  { ticker: "IWM", name_en: "Russell 2000 ETF", name_zh: "罗素2000 ETF", kind: "etf" },
  { ticker: "DIA", name_en: "Dow Jones ETF", name_zh: "道指 ETF", kind: "etf" },
  { ticker: "VOO", name_en: "Vanguard S&P 500", name_zh: "先锋标普500 ETF", kind: "etf" },
  { ticker: "VTI", name_en: "Total US Market", name_zh: "美股全市场 ETF", kind: "etf" },
  { ticker: "SOXX", name_en: "Semiconductor ETF", name_zh: "半导体 ETF", kind: "etf" },
  { ticker: "SMH", name_en: "Semiconductor ETF", name_zh: "半导体 ETF(SMH)", kind: "etf" },
  { ticker: "ARKK", name_en: "ARK Innovation", name_zh: "ARK 创新 ETF", kind: "etf" },
  { ticker: "XLK", name_en: "Technology ETF", name_zh: "科技板块 ETF", kind: "etf" },
  { ticker: "XLF", name_en: "Financials ETF", name_zh: "金融板块 ETF", kind: "etf" },
  { ticker: "XLE", name_en: "Energy ETF", name_zh: "能源板块 ETF", kind: "etf" },
  // —— 杠杆 / 反向 / 波动率（衍生品类） ——
  { ticker: "TQQQ", name_en: "3x Nasdaq Bull", name_zh: "纳指 3 倍做多", kind: "leveraged" },
  { ticker: "SQQQ", name_en: "3x Nasdaq Bear", name_zh: "纳指 3 倍做空", kind: "leveraged" },
  { ticker: "SOXL", name_en: "3x Semis Bull", name_zh: "半导体 3 倍做多", kind: "leveraged" },
  { ticker: "SOXS", name_en: "3x Semis Bear", name_zh: "半导体 3 倍做空", kind: "leveraged" },
  { ticker: "SPXL", name_en: "3x S&P Bull", name_zh: "标普 3 倍做多", kind: "leveraged" },
  { ticker: "TSLL", name_en: "2x Tesla Bull", name_zh: "特斯拉 2 倍做多", kind: "leveraged" },
  { ticker: "NVDL", name_en: "2x Nvidia Bull", name_zh: "英伟达 2 倍做多", kind: "leveraged" },
  { ticker: "UVXY", name_en: "VIX Volatility", name_zh: "VIX 波动率", kind: "leveraged" },
  // —— 商品 ——
  { ticker: "GLD", name_en: "Gold ETF", name_zh: "黄金 ETF", kind: "commodity" },
  { ticker: "SLV", name_en: "Silver ETF", name_zh: "白银 ETF", kind: "commodity" },
  { ticker: "USO", name_en: "Crude Oil ETF", name_zh: "原油 ETF", kind: "commodity" },
  // —— 加密（现货 ETF / 信托） ——
  { ticker: "IBIT", name_en: "iShares Bitcoin", name_zh: "贝莱德比特币 ETF", kind: "crypto" },
  { ticker: "GBTC", name_en: "Grayscale Bitcoin", name_zh: "灰度比特币信托", kind: "crypto" },
  { ticker: "ETHA", name_en: "iShares Ethereum", name_zh: "贝莱德以太坊 ETF", kind: "crypto" },
  // —— 债券 ——
  { ticker: "TLT", name_en: "20Y+ Treasury", name_zh: "20 年期美债 ETF", kind: "bond" },
  { ticker: "HYG", name_en: "High Yield Bond", name_zh: "高收益债 ETF", kind: "bond" },
];
