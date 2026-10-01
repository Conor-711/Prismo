// Discovery scope only. Live issuer/HL evidence is required; no execution approval.
export const V1_TICKERS: ReadonlySet<string> = new Set(
  "SPY QQQ ASTS IWM ONDS SLV GLD MARA NVO OPEN AMC CLSK OKLO APP SOXX WULF APLD CRM XOM SNOW PYPL ALAB UBER UNH ADBE POET PL GDX HUT VRT RIOT NEM WMT UUUU JPM PATH NKE CVNA PANW VOO MP DDOG CORZ GS FCX FLY SMR QURE CAT LULU".split(" "),
);
export const EXECUTION_NETWORKS = ["Ethereum", "Ink"] as const;
