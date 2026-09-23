import XCTest
@testable import BSmart

final class SmartAccountDetailPresentationTests: XCTestCase {
    func testTopBadgeUsesPublishedPlatformPercentileWithoutInventingMissingRanks() {
        var account = SmartAccountProfile(id: "author", name: "Investor", handle: "@investor", platform: "X",
            score: 120, scoreChange: 0, specialty: "Tech", horizon: "20D", recentTicker: "MU",
            platformRank: 35, platformPercentile: 0.141026)
        XCTAssertEqual(SmartAccountRankPresentation.label(account), "TOP 15%")
        account.platformPercentile = 0
        XCTAssertEqual(SmartAccountRankPresentation.label(account), "TOP 1%")
        account.platformPercentile = 1
        XCTAssertEqual(SmartAccountRankPresentation.label(account), "TOP 100%")
        for invalid in [Double.nan, .infinity, -0.1, 1.01] {
            account.platformPercentile = invalid
            XCTAssertEqual(SmartAccountRankPresentation.label(account), "#35")
        }
        account.platformPercentile = nil
        XCTAssertNil(SmartAccountRankPresentation.topPercent(account))
        XCTAssertEqual(SmartAccountRankPresentation.label(account), "#35")
        account.platformRank = nil
        XCTAssertNil(SmartAccountRankPresentation.label(account))
    }

    func testPortraitPullRevealsImageAndFadesOnlyTitle() {
        let rest = SmartAccountPortraitLayout(width: 390, offset: 0)
        let half = SmartAccountPortraitLayout(width: 390, offset: 50)
        let full = SmartAccountPortraitLayout(width: 390, offset: 140)
        XCTAssertEqual(rest.titleOpacity, 1)
        XCTAssertEqual(half.titleOpacity, 0.5)
        XCTAssertEqual(full.titleOpacity, 0)
        XCTAssertEqual(full.imageHeight - rest.imageHeight, 140)
        XCTAssertFalse(full.isCollapsed)
    }

    func testPortraitHasBoundedRestHeightAndSeparateCompactNavigation() {
        XCTAssertEqual(SmartAccountPortraitLayout(width: 320, offset: 0).baseHeight, 260)
        XCTAssertEqual(SmartAccountPortraitLayout(width: 1024, offset: 0).baseHeight, 340)
        let scrolled = SmartAccountPortraitLayout(width: 390, offset: -240)
        XCTAssertTrue(scrolled.isCollapsed)
        XCTAssertEqual(scrolled.titleOpacity, 1)
        XCTAssertEqual(scrolled.imageHeight, scrolled.baseHeight)
        XCTAssertEqual(SmartAccountPortraitLayout(width: 390, offset: .nan).pull, 0)
    }

    func testUsesSettledWindowInsteadOfLaterPeak() {
        var update = makeUpdate()
        update.priceEvidence = evidence(percent: 80)
        update.settlement = .init(status: "settled", horizon: "20D", entryDay: "2026-01-02",
            exitDay: "2026-02-02", entryPrice: 100, exitPrice: 120, tickerReturnPercent: 20,
            marketBenchmarkReturnPercent: 4, marketExcessReturnPercent: 16, actualHit: true,
            contribution: 2, industryBenchmarkTicker: nil, industryBenchmarkReturnPercent: nil,
            industryExcessReturnPercent: nil, industryActualHit: nil, settlementVersion: nil)
        let result = RepresentativeWorkPerformance(update: update)
        XCTAssertEqual(result?.percent, 20)
        XCTAssertEqual(result?.endDay, "2026-02-02")
        XCTAssertEqual(result?.endPrice, 120)
    }

    func testBearishExampleRetainsNegativeStockReturnNotFakePositiveROI() {
        var update = makeUpdate()
        update.priceEvidence = evidence(percent: -25)
        XCTAssertEqual(RepresentativeWorkPerformance(update: update)?.percent, -25)
    }

    func testMissingOrNonfiniteResultsNeverBecomeZeroOrScore() {
        var update = makeUpdate()
        XCTAssertNil(RepresentativeWorkPerformance(update: update))
        update.priceEvidence = evidence(percent: .nan)
        XCTAssertNil(RepresentativeWorkPerformance(update: update))
        update.priceEvidence = evidence(percent: 20, latestDay: "2025-01-01")
        XCTAssertNil(RepresentativeWorkPerformance(update: update))
    }

    private func makeUpdate() -> SmartAccountUpdate {
        SmartAccountUpdate(id: UUID(), ticker: "MU", companyName: "Micron", authorId: "author",
            authorName: "Investor", platform: "X", score: 120, platformPercentile: 0.1,
            direction: .bearish, lifecycle: .new, horizon: "20D", targetPrice: nil,
            thesis: "Public view", invalidation: nil, publishedAt: .now, evidenceURL: nil)
    }

    private func evidence(percent: Double, latestDay: String = "2026-03-01") -> SmartAccountPriceEvidence {
        .init(ticker: "MU", viewDay: "2026-01-02", viewPrice: 100, latestDay: latestDay,
              latestPrice: 100 * (1 + percent / 100), responsePercent: percent, source: "fixture", candles: [])
    }
}
