import XCTest
@testable import BSmart

@MainActor
final class TodayHoldingsActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMatchesOnlyHeldTickersIncludingWeightOnlyAndBothSources() {
        var watched = position("HOOD")
        watched.entryKind = .watchlist
        var weightOnly = position(" nvda ", weight: 0.35)
        weightOnly.shares = 0
        weightOnly.currentPrice = 0
        let snapshot = make([weightOnly, watched], [update("NvDa"), update("HOOD")], [movement("NVDA")])
        XCTAssertEqual(snapshot.tickers, ["NVDA"])
        XCTAssertEqual(snapshot.activities.count, 2)
        XCTAssertEqual(snapshot.weights["NVDA"], 0.35)
        XCTAssertEqual(snapshot.filtered(source: .accounts, ticker: "NVDA").count, 1)
        XCTAssertEqual(snapshot.filtered(source: .money, ticker: "nvda").count, 1)
        XCTAssertTrue(snapshot.filtered(source: .all, ticker: "HOOD").isEmpty)
    }

    func testWindowRejectsFutureAndExpiredEvidenceButIncludesBoundary() {
        let snapshot = make([position("NVDA")], [
            update("NVDA", author: "boundary", age: 30 * 86_400),
            update("NVDA", author: "expired", age: 30 * 86_400 + 1),
            update("NVDA", author: "future", age: -1)
        ], [movement("NVDA", age: 30 * 86_400 + 1)])
        XCTAssertEqual(snapshot.activities.map(\.actorKey), ["account:boundary"])
    }

    func testLatestPerSourceAndTickerKeepsReversalAndIndependentMarkets() {
        let old = update("NVDA", author: "author", age: 900)
        let latest = update("NVDA", author: "author", age: 100, direction: .bearish)
        let youtube = update("NVDA", author: "author", age: 200, platform: "YouTube")
        let other = update("MU", author: "author", age: 200)
        let money = movement("NVDA", age: 100)
        let otherMarket = movement("NVDA", age: 200, market: "other:NVDA")
        let snapshot = make([position("NVDA"), position("MU")], [old, latest, youtube, other, latest], [
            movement("NVDA", age: 900), money, otherMarket
        ])
        XCTAssertEqual(snapshot.activities.count, 5)
        XCTAssertFalse(snapshot.activities.contains { $0.id == old.id })
        XCTAssertTrue(snapshot.activities.contains { $0.id == latest.id && $0.direction == .bearish })
        XCTAssertEqual(snapshot.filtered(source: .money, ticker: nil).count, 2)
    }

    func testRecencyFirstThenPositionWeightWithoutComparingSmartScores() {
        let recent = update("MU", age: 100)
        let sameBand = update("NVDA", age: 2_000)
        let older = update("PLTR", age: 4 * 86_400)
        let snapshot = make([position("MU", weight: 0.1), position("NVDA", weight: 0.3),
                             position("PLTR", weight: 0.6)], [older, recent, sameBand])
        XCTAssertEqual(snapshot.activities.map(\.ticker), ["NVDA", "MU", "PLTR"])
    }

    func testWeightsUseAllHoldingsNotOnlyTickersWithEvidence() throws {
        let snapshot = make([position("NVDA"), position("MU"), position("UNKNOWN")], [update("NVDA")])
        XCTAssertEqual(try XCTUnwrap(snapshot.weights["NVDA"]), 1.0 / 3, accuracy: 0.0001)
        var unvalued = position("MU")
        unvalued.currentPrice = 0
        XCTAssertNil(make([position("NVDA"), unvalued], [update("NVDA")]).weights["NVDA"])
    }

    func testDuplicateLotsAggregateWeightsAndInvalidWeightsDoNotLeak() {
        let snapshot = make([position("NVDA", weight: 0.2), position("nvda", weight: 0.15)], [update("NVDA")])
        XCTAssertEqual(snapshot.weights["NVDA"], 0.35)
        var invalid = position("NVDA", weight: .nan)
        invalid.currentPrice = 0
        XCTAssertTrue(make([invalid], [update("NVDA")]).weights.isEmpty)
    }

    func testPreviewCoversHoldingsBeforeRepeatedTickersAndNeverExceedsThree() {
        let snapshot = make([position("NVDA"), position("MU"), position("MSTR")], [
            update("NVDA", author: "a", age: 1), update("NVDA", author: "b", age: 2),
            update("NVDA", author: "c", age: 3), update("MU", age: 4), update("MSTR", age: 5)
        ])
        XCTAssertEqual(snapshot.preview.map(\.ticker), ["NVDA", "MU", "MSTR"])
        XCTAssertEqual(make([position("NVDA")], [update("NVDA")]).preview.count, 1)
        XCTAssertTrue(make([], [update("NVDA")]).activities.isEmpty)
        XCTAssertTrue(make([position("MU")], [update("NVDA")]).activities.isEmpty)
    }

    func testSelectionIsDeterministicWhenInputOrderChanges() {
        let updates = [update("NVDA"), update("NVDA"), update("MU")]
        let holdings = [position("NVDA"), position("MU")]
        XCTAssertEqual(make(holdings, updates), make(holdings, Array(updates.reversed())))
    }

    func testPreviewFiltersBeforeSelectingThreeAndPreservesEvidenceOrder() {
        let snapshot = make([position("NVDA"), position("MU"), position("MSTR")], [
            update("NVDA", age: 1), update("MU", age: 2), update("MSTR", age: 3)
        ], [movement("NVDA", age: 50), movement("MU", age: 60)])
        XCTAssertTrue(snapshot.preview.allSatisfy(\.isSmartAccount))
        let money = snapshot.preview(source: .money)
        XCTAssertEqual(money.map(\.id), snapshot.filtered(source: .money, ticker: nil).map(\.id))
        XCTAssertEqual(money.count, 2, "Money evidence must not disappear behind the all-source preview cap")
        XCTAssertFalse(money.contains(where: \.isSmartAccount))
        XCTAssertEqual(snapshot.preview(source: .all), snapshot.preview)
        XCTAssertLessThanOrEqual(snapshot.preview(source: .accounts).count, 3)
    }

    private func make(_ positions: [PortfolioPosition], _ accounts: [SmartAccountUpdate],
                      _ money: [SmartMoneyMovement] = []) -> TodayHoldingsActivity {
        .make(positions: positions, accountUpdates: accounts, moneyMovements: money, now: now)
    }

    private func position(_ ticker: String, weight: Double? = nil) -> PortfolioPosition {
        PortfolioPosition(id: UUID(), ticker: ticker, companyName: ticker, shares: 10, averageCost: 90,
                          currentPrice: 100, entryKind: .position, portfolioWeight: weight)
    }

    private func update(_ ticker: String, author: String = "author", age: TimeInterval = 100,
                        direction: SignalDirection = .bullish, platform: String = "X") -> SmartAccountUpdate {
        SmartAccountUpdate(id: UUID(), ticker: ticker, companyName: ticker, authorId: author,
                           authorName: author, platform: platform, score: 120, platformPercentile: 0.1,
                           direction: direction, lifecycle: .new, horizon: "20D", targetPrice: nil,
                           thesis: "A source view", invalidation: nil, publishedAt: now.addingTimeInterval(-age),
                           evidenceURL: nil)
    }

    private func movement(_ ticker: String, age: TimeInterval = 100,
                          market: String? = nil) -> SmartMoneyMovement {
        SmartMoneyMovement(id: UUID(), ticker: ticker, companyName: ticker, accountId: "wallet",
                           accountLabel: "wallet", accountScore: 80, market: market ?? "xyz:\(ticker)",
                           action: .reduced, direction: .bullish, notionalBefore: 1_000, notionalAfter: 800,
                           notionalChange: -200, leverage: nil, observedAt: now.addingTimeInterval(-age),
                           evidenceURL: nil)
    }
}
