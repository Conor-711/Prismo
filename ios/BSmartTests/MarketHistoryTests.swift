import XCTest
@testable import BSmart

final class MarketHistoryTests: XCTestCase {
    func testOpinionPositionsUseMarketSessionAndNeverClampOutsideWindow() async throws {
        let end = Date()
        let source = try await DebugTradingMarketClient().fetchCandles(
            coin: "xyz:SPCX", interval: "1d", start: end.addingTimeInterval(-90 * 86_400), end: end)
        let history = TodayMarketHistory(candles: source)
        let candle = try XCTUnwrap(source.dropLast().last)
        XCTAssertEqual(history.candle(at: candle.openTime.addingTimeInterval(3600), days: 7)?.close, candle.close)
        XCTAssertNil(history.candle(at: source.first!.openTime, days: 7))
        XCTAssertNil(history.candle(at: end.addingTimeInterval(86_400), days: 90))
        XCTAssertNil(history.candle(at: source.first!.openTime.addingTimeInterval(-86_400), days: 90))
        XCTAssertEqual(history.coin, "xyz:SPCX")
    }

    @MainActor
    func testHomeUsesNinetyDayMarketOHLCWithoutOpinionEvidence() async throws {
        let root = HyperliquidTradingStore(client: DebugTradingMarketClient())
        let home = root.makeSession(candleWindow: .dailyHistory)
        let markets = try await DebugTradingMarketClient().fetchMarkets(dex: .init(name: "xyz", displayName: "XYZ"))
        for symbol in ["NVDA", "SPCX", "SNDK"] {
            let market = try XCTUnwrap(markets.first { $0.symbol == symbol })
            await home.selectMarket(market)
            XCTAssertEqual(home.market(for: symbol)?.markPrice, market.markPrice)
            XCTAssertGreaterThanOrEqual(home.candles.count, 90)
            XCTAssertTrue(home.candles.allSatisfy { $0.coin == market.coin && $0.interval == "1d" && $0.hasValidOHLC })
            XCTAssertGreaterThan(home.candles.last!.closeTime, Date())
            XCTAssertEqual(home.candles.last!.openTime.timeIntervalSince(home.candles.dropLast().last!.openTime), 86_400)
        }
        XCTAssertNil(root.activeMarket, "The home session must not change the detail/order session.")
    }

    func testValidationExcludesBadPricesWrongMarketsAndDuplicateTimes() {
        let now = Date()
        func candle(_ offset: Double = -100, coin: String = "xyz:NVDA", interval: String = "1d",
                    open: Double = 10, high: Double = 12, low: Double = 9, close: Double = 11) -> HyperliquidCandle {
            .init(openTime: now.addingTimeInterval(offset), closeTime: now.addingTimeInterval(offset + 86_400),
                  coin: coin, interval: interval, open: open, high: high, low: low, close: close, volume: 1, tradeCount: 1)
        }
        let result = HyperliquidCandle.validated([
            candle(), candle(close: 12), candle(-200, high: 8), candle(-300, low: 11),
            candle(-400, close: .nan), candle(-500, open: 0), candle(-600, high: .infinity),
            candle(100), candle(-700, coin: "test:NVDA"), candle(-800, interval: "1h"),
            candle(-200_000), candle(-1000, open: 10, high: 10, low: 10, close: 10)
        ], coin: "xyz:NVDA", interval: "1d", start: now.addingTimeInterval(-86_400), end: now)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.last?.close, 12)
        XCTAssertEqual(result.first?.open, result.first?.close, "A genuine doji remains valid, without synthetic prices.")
    }

    @MainActor
    func testLateInitialMarketCannotReplaceExplicitSelection() async throws {
        let client = DelayedInitialMarketClient()
        let store = HyperliquidTradingStore(client: client)
        let loading = Task { await store.runLiveMarket(symbol: "NVDA") }
        await client.waitForRequest()
        let other = try await DebugTradingMarketClient().fetchMarkets(dex: .init(name: "test", displayName: "Test"))[0]
        await store.selectMarket(other)
        await client.finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.activeMarket?.coin, "test:MSTR")
        XCTAssertTrue(store.candles.allSatisfy { $0.coin == "test:MSTR" })
        loading.cancel()
        await loading.value
    }

    @MainActor
    func testPreferredVenueFailureStillResolvesOtherVenue() async {
        let store = HyperliquidTradingStore(client: AlternateVenueClient())
        let loading = Task { await store.runLiveMarket(symbol: "MSTR") }
        for _ in 0..<200 {
            if !store.candles.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.activeMarket?.coin, "test:MSTR")
        XCTAssertFalse(store.candles.isEmpty)
        loading.cancel()
        await loading.value
    }
}

private actor DelayedInitialMarketClient: HyperliquidMarketDataClient {
    private var request: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func fetchDexs() async throws -> [HyperliquidDex] { [] }
    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket] {
        await withCheckedContinuation { continuation in
            request = continuation
            observer?.resume()
            observer = nil
        }
        return try await DebugTradingMarketClient().fetchMarkets(dex: dex)
    }
    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() { request?.resume(); request = nil }
    func fetchCandles(coin: String, interval: String, start: Date, end: Date) async throws -> [HyperliquidCandle] {
        try await DebugTradingMarketClient().fetchCandles(coin: coin, interval: interval, start: start, end: end)
    }
}

private struct AlternateVenueClient: HyperliquidMarketDataClient {
    func fetchDexs() async throws -> [HyperliquidDex] { [.init(name: "test", displayName: "Test")] }
    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket] {
        if dex.name == "xyz" { throw HyperliquidMarketDataError.httpStatus(503) }
        return try await DebugTradingMarketClient().fetchMarkets(dex: dex)
    }
    func fetchCandles(coin: String, interval: String, start: Date, end: Date) async throws -> [HyperliquidCandle] {
        try await DebugTradingMarketClient().fetchCandles(coin: coin, interval: interval, start: start, end: end)
    }
}
