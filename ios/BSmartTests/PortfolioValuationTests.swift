import XCTest
@testable import BSmart

final class PortfolioValuationTests: XCTestCase {
    func testHistoryFiltersInvalidFutureAndDuplicatePoints() {
        let now = Date()
        let earlier = now.addingTimeInterval(-60)
        let points = [PortfolioValuePoint(timestamp: earlier, value: 100),
                      .init(timestamp: earlier, value: 110), .init(timestamp: now, value: .nan),
                      .init(timestamp: now.addingTimeInterval(60), value: 300),
                      .init(timestamp: now.addingTimeInterval(-30), value: -1)]
        XCTAssertEqual(PortfolioValuationHistory.normalized(points, now: now), [.init(timestamp: earlier, value: 110)])
    }

    func testSnapshotsCoalesceBurstsButKeepEarlierObservations() {
        let now = Date()
        let points = [PortfolioValuePoint(timestamp: now.addingTimeInterval(-120), value: 100),
                      .init(timestamp: now.addingTimeInterval(-20), value: 105)]
        let recorded = PortfolioValuationHistory.recording(108, at: now, in: points)
        XCTAssertEqual(recorded.map(\.value), [100, 108])
        XCTAssertEqual(recorded.last?.timestamp, now)
        XCTAssertEqual(PortfolioValuationHistory.recording(108, at: now.addingTimeInterval(10), in: recorded), recorded)
    }

    func testPeriodUsesActualClockAndDoesNotRebaseOldHistory() {
        let now = Date()
        let points = [PortfolioValuePoint(timestamp: now.addingTimeInterval(-40 * 86_400), value: 90),
                      .init(timestamp: now.addingTimeInterval(-3 * 86_400), value: 100),
                      .init(timestamp: now, value: 120)]
        XCTAssertEqual(PortfolioChartPeriod.day.points(in: points, now: now).map(\.value), [120])
        XCTAssertEqual(PortfolioChartPeriod.week.points(in: points, now: now).map(\.value), [100, 120])
        XCTAssertEqual(PortfolioChartPeriod.all.points(in: points, now: now).count, 3)
    }

    func testContextIgnoresQuotesAndWatchlistButTracksQuantity() {
        var position = PortfolioPosition(id: UUID(), ticker: "NVDA", companyName: "NVIDIA", shares: 2, averageCost: 100, currentPrice: 120)
        let context = PortfolioValuationHistory.context(for: [position])
        position.currentPrice = 140
        let watch = PortfolioPosition(id: UUID(), ticker: "MU", companyName: "Micron", shares: 0, averageCost: 0, currentPrice: 100, entryKind: .watchlist)
        XCTAssertEqual(context, PortfolioValuationHistory.context(for: [watch, position]))
        position.shares = 3
        XCTAssertNotEqual(context, PortfolioValuationHistory.context(for: [position]))
    }

    @MainActor
    func testExternalHistorySurvivesRelaunchAndRejectsDifferentBasket() async throws {
        let suite = "BSmart.Valuation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: ValuationTestClient(), defaults: defaults)
        await model.load()
        XCTAssertGreaterThan(model.portfolioHistory.count, 1)
        XCTAssertEqual(model.portfolioHistory.last?.value, model.portfolioValue)
        let first = try XCTUnwrap(model.heldPositions.first)
        XCTAssertTrue(model.savePortfolioEntry(id: first.id, ticker: first.ticker, companyName: first.companyName,
            kind: .position, shares: first.shares + 1, averageCost: first.averageCost, portfolioWeight: nil))
        XCTAssertEqual(model.portfolioHistory.count, 1)
        let restored = AppModel(client: ValuationTestClient(), defaults: defaults)
        await restored.load()
        XCTAssertEqual(restored.portfolioHistory.count, 1)
        XCTAssertEqual(restored.portfolioHistory.last?.value, restored.portfolioValue)
        await restored.resetLocalAppData()
        XCTAssertNil(defaults.data(forKey: "bsmart.portfolio-valuations.v1"))
    }

    func testTradingAccountHistoryIsBackwardCompatible() throws {
        let account = PaperTradingAccount.fresh()
        XCTAssertEqual(account.valuationHistory?.first?.value, account.equity)
        let data = try JSONEncoder().encode(account)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "valuationHistory")
        let restored = try JSONDecoder().decode(PaperTradingAccount.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.valuationHistory)
        XCTAssertEqual(restored.equity, account.equity)
    }
}

private struct ValuationTestClient: BSmartAPIClient {
    func fetchPortfolio() async throws -> [PortfolioPosition] {
        [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, ticker: "NVDA", companyName: "NVIDIA",
               shares: 10, averageCost: 100, currentPrice: 120)]
    }
    func fetchPortfolioHistory() async throws -> [PortfolioValuePoint] {
        [.init(timestamp: Date().addingTimeInterval(-86_400), value: 1100)]
    }
    func fetchSignals() async throws -> [PortfolioSignal] { [] }
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }
}
