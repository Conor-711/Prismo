import XCTest
import SwiftUI
import WebKit
@testable import BSmart

final class TickerMarketRequestTests: XCTestCase {
    func testTradingViewFallbackRequiresKnownExchange() {
        XCTAssertEqual(TradingViewChartSymbol.forTicker("oust"), "NASDAQ:OUST")
        XCTAssertEqual(TradingViewChartSymbol.forTicker("PLTR"), "NASDAQ:PLTR")
        XCTAssertEqual(TradingViewChartSymbol.forTicker("UBER"), "NYSE:UBER")
        XCTAssertNil(TradingViewChartSymbol.forTicker("UNVERIFIED"))
        XCTAssertNil(TradingViewChartSymbol.forTicker("../OUST"))
    }

    func testTradingViewBlankSnapshotIsNotMarkedLoaded() {
        let size = CGSize(width: 390, height: 445)
        let blank = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 17 / 255, green: 22 / 255, blue: 21 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        XCTAssertFalse(TradingViewChartPixelCheck.hasVisibleContent(blank))
        let lightBlank = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        XCTAssertFalse(TradingViewChartPixelCheck.hasVisibleContent(lightBlank))

        let chart = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 17 / 255, green: 22 / 255, blue: 21 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 20, y: 30, width: 100, height: 20))
        }
        XCTAssertTrue(TradingViewChartPixelCheck.hasVisibleContent(chart))
    }

    @MainActor
    func testTradingViewFallbackHasVisibleWebViewWidth() async {
        let store = HyperliquidTradingStore(client: MissingMarketClient(failDex: nil))
        await store.runLiveMarket(symbol: "OUST")

        let controller = UIHostingController(rootView:
            HyperliquidTradingView(symbol: "OUST").environmentObject(store))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try? await Task.sleep(for: .milliseconds(200))
        controller.view.layoutIfNeeded()

        func findWebView(in view: UIView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            return view.subviews.lazy.compactMap { findWebView(in: $0) }.first
        }
        let webView = findWebView(in: controller.view)
        XCTAssertNotNil(webView)
        XCTAssertGreaterThan(webView?.bounds.width ?? 0, 300)
        if let webView {
            var origin: String?
            for _ in 0..<15 {
                origin = try? await webView.evaluateJavaScript("window.location.origin") as? String
                if origin == "https://bsmart.today" { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(origin, "https://bsmart.today")
        }
    }

    @MainActor
    func testMissingPerpMarketOffersOnlyVerifiedExternalDestinations() async {
        let store = HyperliquidTradingStore(client: MissingMarketClient(failDex: nil))
        await store.runLiveMarket(symbol: "LULU")
        XCTAssertNil(store.activeMarket)
        XCTAssertEqual(store.verifiedNoMarketSymbol, "LULU")
        XCTAssertEqual(ExternalTradeLinks.destinations(for: "LULU").map(\.name),
                       ["Robinhood", "eToro", "moomoo"])
        for destination in ExternalTradeLinks.destinations(for: "LULU") {
            XCTAssertNotNil(UIImage(named: destination.logoAssetName), destination.name)
        }
        XCTAssertEqual(ExternalTradeLinks.destinations(for: "LULU").first?.url.absoluteString,
                       "https://robinhood.com/us/en/stocks/LULU/")
    }

    @MainActor
    func testConnectionOrIncompleteCatalogDoesNotClaimNoMarket() async {
        for dex in ["xyz", ""] {
            let store = HyperliquidTradingStore(client: MissingMarketClient(failDex: dex))
            await store.runLiveMarket(symbol: "LULU")
            XCTAssertNil(store.verifiedNoMarketSymbol)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testExternalLinksAreRestrictedToTickerOnly() {
        XCTAssertTrue(ExternalTradeLinks.destinations(for: "../LULU?buy=1").isEmpty)
        XCTAssertEqual(ExternalTradeLinks.destinations(for: " sol ").map(\.name), ["Coinbase", "Kraken"])
        XCTAssertEqual(ExternalTradeLinks.destinations(for: "sol").first?.url.absoluteString,
                       "https://www.coinbase.com/price/solana")
        for destination in ExternalTradeLinks.destinations(for: "SOL") {
            XCTAssertNotNil(UIImage(named: destination.logoAssetName), destination.name)
        }
    }

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

private actor MissingMarketClient: HyperliquidMarketDataClient {
    let failDex: String?

    init(failDex: String?) { self.failDex = failDex }

    func fetchDexs() async throws -> [HyperliquidDex] {
        [.init(name: "", displayName: "Hyperliquid"), .init(name: "xyz", displayName: "XYZ")]
    }

    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket] {
        if dex.name == failDex { throw URLError(.secureConnectionFailed) }
        return []
    }

    func fetchCandles(coin: String, interval: String, start: Date, end: Date) async throws -> [HyperliquidCandle] {
        []
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
