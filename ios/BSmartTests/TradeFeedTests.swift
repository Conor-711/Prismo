import XCTest
@testable import BSmart

@MainActor
final class TradeFeedTests: XCTestCase {
    func testExplicitDemoHasSixMarketsAndLocalProfilePagination() throws {
        let demo = try TradeFeedDemoData.load()
        XCTAssertEqual(demo.items.count, 6)
        XCTAssertEqual(Set(demo.items.map { $0.opinion.ticker }), ["NVDA", "MSFT", "META", "TSLA", "AAPL", "AMD"])
        let first = try demo.page(offset: 0)
        try first.validate(offset: 0)
        XCTAssertEqual(first.nextOffset, 3)
        let second = try demo.page(offset: 3)
        try second.validate(offset: 3)
        XCTAssertNil(second.nextOffset)
        XCTAssertEqual(Set((first.items + second.items).map(\.id)).count, 6)
        let profileID = first.items[0].trader.id
        XCTAssertEqual(try demo.profile(id: profileID).nickname, "Casey")
        XCTAssertEqual(try demo.page(offset: 0, profileID: profileID).items.count, 2)
        XCTAssertThrowsError(try demo.profile(id: UUID()))
        XCTAssertThrowsError(try demo.page(offset: -1))
    }

    private func fixture() throws -> TradeFeedPage {
        let url = Bundle.main.url(forResource: "trade-feed", withExtension: "json")!
        return try BSmartJSONCoding.makeDecoder().decode(TradeFeedPage.self, from: Data(contentsOf: url))
    }

    func testFixtureAndSourceIdentity() throws {
        let page = try fixture()
        try page.validate(offset: 0)
        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.items[0].source.feedEventID, page.items[0].id)
        XCTAssertTrue(page.items[0].source.matches(symbol: "NVDA"))
        XCTAssertFalse(page.items[0].source.matches(symbol: "META"))
        XCTAssertEqual(FeedQuickTradeChoice.choices.map(\.id), ["short.100", "short.500", "long.500", "long.100"])
    }

    func testValidationRejectsBrokenPaginationAndChronology() throws {
        let page = try fixture()
        XCTAssertThrowsError(try TradeFeedPage(items: [page.items[0], page.items[0]], nextOffset: nil).validate(offset: 0))
        XCTAssertThrowsError(try TradeFeedPage(items: [], nextOffset: 0).validate(offset: 0))
        XCTAssertThrowsError(try TradeFeedPage(items: Array(page.items.reversed()), nextOffset: nil).validate(offset: 0))
    }

    func testPaginationDeduplicatesAndFailedRefreshClearsPublicIdentity() async throws {
        let page = try fixture()
        let store = TradeFeedStore()
        await store.load(reset: true) { _ in .init(items: Array(page.items.prefix(2)), nextOffset: 2) }
        await store.load(reset: false) { offset in
            XCTAssertEqual(offset, 2)
            return .init(items: Array(page.items.suffix(2)), nextOffset: nil)
        }
        XCTAssertEqual(store.items.count, 3)
        await store.load(reset: true) { _ in throw BSmartAPIError.httpStatus(503) }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.failed)
    }

    func testLeavingFeedRejectsLateResponse() async throws {
        let page = try fixture()
        let store = TradeFeedStore()
        await store.load(reset: true) { _ in
            store.clear()
            return page
        }
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.hasLoaded)
    }

    func testUnavailableIsNotZeroTrades() async {
        do {
            _ = try await BundleBSmartAPIClient().fetchTradeFeed(offset: 0, profileID: nil)
            XCTFail("Historical fixtures cannot represent live public trading")
        } catch BSmartAPIError.tradeStatisticsUnavailable { } catch { XCTFail("\(error)") }
    }

    func testQuickTradeUsesNotionalAtExistingLeverageAndOnlyExecutesOnce() async throws {
        let market = try await DebugTradingMarketClient().fetchMarkets(dex: .init(name: "xyz", displayName: "XYZ"))[0]
        let paper = PaperTradingEngine(storage: FeedTestPaperStorage())
        try paper.placeMarketOrder(side: .long, margin: 100, leverage: 5, market: market)
        let request = FeedQuickTradeRequest(item: try fixture().items[0], choice: .init(side: .long, dollars: 100))
        let executor = FeedQuickTradeExecutor()
        await executor.execute(request, paper: paper) { market }
        await executor.execute(request, paper: paper) { market }
        XCTAssertEqual(paper.account.executions.count, 2)
        let fill = try XCTUnwrap(executor.execution)
        XCTAssertLessThanOrEqual(fill.notional, 100)
        XCTAssertGreaterThan(fill.notional, 99.9)
        XCTAssertEqual(fill.leverage, 5)
    }

    func testCancelledOrMismatchedMarketNeverExecutes() async throws {
        let market = try await DebugTradingMarketClient().fetchMarkets(dex: .init(name: "test", displayName: "Test"))[0]
        let paper = PaperTradingEngine(storage: FeedTestPaperStorage())
        let request = FeedQuickTradeRequest(item: try fixture().items[0], choice: .init(side: .short, dollars: 500))
        let executor = FeedQuickTradeExecutor()
        await executor.execute(request, paper: paper) { market }
        XCTAssertNotNil(executor.errorMessage)
        XCTAssertTrue(paper.account.executions.isEmpty)
        let cancelled = FeedQuickTradeExecutor()
        await cancelled.execute(request, paper: paper) {
            cancelled.cancel()
            return market
        }
        XCTAssertTrue(paper.account.executions.isEmpty)
    }

    func testAssistantVisibilityTokenCannotClearAnotherDetail() {
        let router = AppRouter()
        let assistant = UUID(), detail = UUID()
        router.setTabBarHidden(true, token: assistant)
        router.setTabBarHidden(true, token: detail)
        router.setTabBarHidden(false, token: detail)
        XCTAssertTrue(router.isTabBarHidden)
        router.setTabBarHidden(false, token: assistant)
        XCTAssertFalse(router.isTabBarHidden)
    }
}

private final class FeedTestPaperStorage: PaperTradingPersisting {
    func load() -> PaperTradingAccount? { nil }
    func save(_ account: PaperTradingAccount) { }
    func clear() { }
}
