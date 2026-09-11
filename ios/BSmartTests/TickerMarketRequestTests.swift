import XCTest
@testable import BSmart

final class TickerMarketRequestTests: XCTestCase {
    @MainActor
    func testLateCandleResponseCannotOverwriteNewRange() async throws {
        let client = SuspendedCandleClient()
        let store = HyperliquidTradingStore(client: client)
        let markets = try await DebugTradingMarketClient()
            .fetchMarkets(dex: HyperliquidDex(name: "xyz", displayName: "XYZ"))
        let market = try XCTUnwrap(markets.first)
        let old = Task { await store.selectMarket(market) }
        await client.waitForRequest("15m")
        store.chartRange = .oneMonth
        let latest = Task { await store.reloadCandles() }
        await client.waitForRequest("4h")
        await client.finish("4h", price: 300)
        await latest.value
        XCTAssertEqual(store.candles.first?.close, 300)
        await client.finish("15m", price: 100)
        await old.value
        XCTAssertEqual(store.candles.first?.close, 300)
        XCTAssertEqual(store.candles.first?.interval, "4h")
        XCTAssertFalse(store.isLoadingCandles)
    }
}

private actor SuspendedCandleClient: HyperliquidMarketDataClient {
    private var requests: [String: CheckedContinuation<[HyperliquidCandle], Never>] = [:]
    private var observers: [String: CheckedContinuation<Void, Never>] = [:]

    func fetchDexs() async throws -> [HyperliquidDex] { [] }
    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket] { [] }
    func fetchCandles(coin: String, interval: String, start: Date, end: Date) async throws -> [HyperliquidCandle] {
        await withCheckedContinuation { continuation in
            requests[interval] = continuation
            observers.removeValue(forKey: interval)?.resume()
        }
    }
    func waitForRequest(_ interval: String) async {
        if requests[interval] != nil { return }
        await withCheckedContinuation { observers[interval] = $0 }
    }
    func finish(_ interval: String, price: Double) {
        let now = Date()
        requests.removeValue(forKey: interval)?.resume(returning: [HyperliquidCandle(
            openTime: now.addingTimeInterval(-100), closeTime: now, coin: "xyz:NVDA", interval: interval,
            open: price, high: price, low: price, close: price, volume: 1, tradeCount: 1)])
    }
}
