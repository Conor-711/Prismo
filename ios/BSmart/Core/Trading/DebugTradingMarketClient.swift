#if DEBUG
import Foundation

struct DebugTradingMarketClient: HyperliquidMarketDataClient {
    func fetchDexs() async throws -> [HyperliquidDex] {
        if ProcessInfo.processInfo.arguments.contains("--ui-search-market-error") { throw URLError(.notConnectedToInternet) }
        var dexs = [HyperliquidDex(name: "xyz", displayName: "XYZ"), HyperliquidDex(name: "test", displayName: "Test venue")]
        if ProcessInfo.processInfo.arguments.contains("--ui-search-fixture") {
            dexs.append(HyperliquidDex(name: "", displayName: "Hyperliquid"))
        }
        return dexs
    }

    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket] {
        if ProcessInfo.processInfo.arguments.contains("--ui-trading-delayed-market") {
            try await Task.sleep(for: .seconds(2))
        }
        let symbols = dex.name.isEmpty ? ["BTC"] : dex.name == "xyz" ? ["NVDA", "SPCX", "SNDK"] : ["MSTR"]
        return symbols.map { symbol in
            let price: Double = symbol == "SPCX" ? 149.45 : symbol == "SNDK" ? 1765.4 : 200
            return HyperliquidPerpMarket(
                coin: dex.name.isEmpty ? symbol : "\(dex.name):\(symbol)", symbol: symbol, dex: dex.name, dexDisplayName: dex.displayName,
                sizeDecimals: 4, maxLeverage: 20, marginTableID: nil, isIsolatedOnly: true,
                isDelisted: false, markPrice: price, midPrice: price, oraclePrice: price,
                previousDayPrice: price * 0.975, dayNotionalVolume: 10_000_000, openInterest: 5_000,
                fundingRate: 0.00001, impactBidPrice: price - 0.01, impactAskPrice: price + 0.01,
                updatedAt: Date()
            )
        }
    }

    func fetchCandles(coin: String, interval: String, start: Date, end: Date) async throws -> [HyperliquidCandle] {
        let step: TimeInterval = ["1m": 60, "5m": 300, "15m": 900, "1h": 3600,
                                  "4h": 14_400, "1d": 86_400][interval] ?? 900
        let first = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 / step) * step)
        let count = Int(end.timeIntervalSince(first) / step) + 1
        let base: Double = coin.hasSuffix("SPCX") ? 149.45 : coin.hasSuffix("SNDK") ? 1765.4 : 200
        return (0..<count).map { index in
            let previous = base * (0.975 + Double(index - 1) / Double(count) * 0.025 + sin(Double(index - 1) / 4) * 0.006)
            let price = base * (0.975 + Double(index) / Double(count) * 0.025 + sin(Double(index) / 4) * 0.006)
            return HyperliquidCandle(
                openTime: first.addingTimeInterval(Double(index) * step),
                closeTime: first.addingTimeInterval(Double(index + 1) * step - 0.001),
                coin: coin, interval: interval, open: previous, high: max(previous, price) + base * 0.001,
                low: min(previous, price) - base * 0.001, close: price, volume: 1000, tradeCount: 20
            )
        }
    }
}
#endif
