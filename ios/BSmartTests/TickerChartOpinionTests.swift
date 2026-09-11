import XCTest
@testable import BSmart

final class TickerChartOpinionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPolicyScalesDensityWithoutShrinkingTouchTargets() {
        let short = TickerChartOpinionPolicy(range: .oneHour)
        let long = TickerChartOpinionPolicy(range: .oneMonth)
        XCTAssertLessThan(short.maximumCount, long.maximumCount)
        XCTAssertGreaterThan(short.avatarSize, long.avatarSize)
        for range in HyperliquidChartRange.allCases {
            let policy = TickerChartOpinionPolicy(range: range)
            XCTAssertGreaterThanOrEqual(policy.footprint.width, 44)
            XCTAssertGreaterThanOrEqual(policy.footprint.height, 44)
        }
    }

    func testWindowExcludesOldFutureAndOtherSymbolEvents() {
        let valid = activity("valid", at: now.addingTimeInterval(-1800))
        let old = activity("old", at: now.addingTimeInterval(-4000))
        let future = activity("future", at: now.addingTimeInterval(20))
        let other = activity("other", at: now.addingTimeInterval(-1800), ticker: "MSTR")
        let visible = TickerChartOpinion.visibleActivities([old, valid, future, other], symbol: "NVDA",
            candles: candles, range: .oneHour, now: now)
        XCTAssertEqual(visible.map(\.id), [valid.id])
        XCTAssertTrue(TickerChartOpinion.visibleActivities([valid], symbol: "NVDA",
            candles: [], range: .oneHour, now: now).isEmpty)
    }

    func testRanksLatestPerAuthorWithoutReusingEquityPrices() {
        let best = activity("best", at: now.addingTimeInterval(-1500), percentile: 0.01)
        let middle = activity("middle", at: now.addingTimeInterval(-500), percentile: 0.1)
        let old = activity("best", at: now.addingTimeInterval(-2500), percentile: 0.01)
        let result = TickerChartOpinion.candidates(activities: [old, middle, best], candles: candles)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.id, best.id)
        XCTAssertEqual(result.first?.rankLabel, "Top 1%")
        XCTAssertEqual(result.first?.price, 200)
    }

    func testCollisionLayoutIncludesBadgesAndRespectsBoundsAndLimit() {
        let items = (0..<30).map { activity("a\($0)", at: now.addingTimeInterval(-1200)) }
        let candidates = TickerChartOpinion.candidates(activities: items, candles: candles)
        for width in [CGFloat(240), 320, 600] {
            let bounds = CGRect(x: 10, y: 0, width: width, height: 330)
            let policy = TickerChartOpinionPolicy(range: .oneMonth)
            let placements = TickerChartOpinionPlacement.layout(candidates.map { ($0, CGPoint(x: width, y: 12)) },
                                                                 in: bounds, policy: policy)
            XCTAssertFalse(placements.isEmpty)
            XCTAssertLessThanOrEqual(placements.count, policy.maximumCount)
            for (index, item) in placements.enumerated() {
                XCTAssertTrue(bounds.contains(item.frame))
                for other in placements.dropFirst(index + 1) {
                    XCTAssertFalse(item.frame.insetBy(dx: -4, dy: -4).intersects(other.frame))
                }
            }
        }
    }

    func testMissingCandleIsNotClampedToAnUnrelatedPrice() {
        let item = activity("a", at: now.addingTimeInterval(-8000))
        XCTAssertTrue(TickerChartOpinion.candidates(activities: [item], candles: candles).isEmpty)
    }

    func testCompanyProfilesAreSymbolSpecificAndUnknownIsNotNvidia() {
        XCTAssertEqual(TickerProfile.lookup("mstr")?.name, "Strategy")
        XCTAssertNil(TickerProfile.lookup("UNKNOWN"))
        XCTAssertNotNil(TickerProfile.lookup("PLTR")?.source)
    }

    private var candles: [HyperliquidCandle] {
        [HyperliquidCandle(openTime: now.addingTimeInterval(-3600), closeTime: now,
                          coin: "xyz:NVDA", interval: "1m", open: 190, high: 210, low: 185,
                          close: 200, volume: 1000, tradeCount: 5)]
    }

    private func activity(_ author: String, at date: Date, percentile: Double = 0.1,
                          ticker: String = "NVDA") -> TickerSmartActivityItem {
        TickerSmartActivityItem(payload: .account(SmartAccountUpdate(id: UUID(), ticker: ticker,
            companyName: ticker, authorId: author, authorName: author, platform: "X", score: 80,
            platformPercentile: percentile, direction: .bullish, lifecycle: .new, horizon: "60D",
            targetPrice: nil, thesis: "Demand is growing", invalidation: nil,
            publishedAt: date, evidenceURL: nil)))
    }
}
