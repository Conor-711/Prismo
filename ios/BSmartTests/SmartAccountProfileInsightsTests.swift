import XCTest
@testable import BSmart

final class SmartAccountProfileInsightsTests: XCTestCase {
    func testMergesEvidenceAndRecentViewsWithoutDuplicatingCalls() {
        let sharedID = UUID()
        let recent = makeUpdate(id: sharedID, ticker: "NVDA", timestamp: 200, direction: .bullish)
        var evidence = recent
        evidence.originalText = "Full source evidence"
        let second = makeUpdate(ticker: "TSLA", timestamp: 100, direction: .bearish)

        let insights = SmartAccountProfileInsights(
            account: makeAccount(),
            evidenceUpdates: [evidence],
            recentUpdates: [recent, second]
        )

        XCTAssertEqual(insights.latestViews.map(\.ticker), ["NVDA", "TSLA"])
        XCTAssertEqual(insights.latestViews.first?.originalText, "Full source evidence")
    }

    func testCurrentTickerViewsKeepLatestCallPerTickerAndRespectClosedState() {
        let anchor = Date(timeIntervalSince1970: 3_000_000)
        let insights = SmartAccountProfileInsights(
            account: makeAccount(),
            evidenceUpdates: [],
            recentUpdates: [
                makeUpdate(ticker: "NVDA", date: anchor, direction: .bearish),
                makeUpdate(ticker: "NVDA", date: anchor.addingTimeInterval(-300), direction: .bullish),
                makeUpdate(ticker: "TSLA", date: anchor.addingTimeInterval(-600), direction: .bullish),
                makeUpdate(
                    ticker: "MSTR",
                    date: anchor.addingTimeInterval(-900),
                    direction: .bullish,
                    lifecycle: .closed
                ),
                makeUpdate(
                    ticker: "OLD",
                    date: anchor.addingTimeInterval(-40 * 86_400),
                    direction: .bullish
                )
            ]
        )

        XCTAssertEqual(insights.bullishTickerViews.map(\.update.ticker), ["TSLA"])
        XCTAssertEqual(insights.bearishTickerViews.map(\.update.ticker), ["NVDA"])
        XCTAssertFalse(insights.currentTickerViews.contains { $0.update.ticker == "MSTR" })
        XCTAssertFalse(insights.currentTickerViews.contains { $0.update.ticker == "OLD" })
        XCTAssertFalse(insights.latestViews.contains { $0.ticker == "OLD" })
    }

    private func makeAccount() -> SmartAccountProfile {
        SmartAccountProfile(
            id: "author-1",
            name: "Investor",
            handle: "@investor",
            platform: "X",
            score: 112,
            scoreChange: 2,
            specialty: "Semiconductors",
            horizon: "Medium term",
            recentTicker: "NVDA",
            coveredTickers: 12,
            topTickers: ["NVDA", "MU"],
            style: "Fundamental"
        )
    }

    private func makeUpdate(
        id: UUID = UUID(),
        ticker: String,
        timestamp: TimeInterval = 0,
        date: Date? = nil,
        direction: SignalDirection,
        lifecycle: SmartAccountLifecycle = .new
    ) -> SmartAccountUpdate {
        SmartAccountUpdate(
            id: id,
            ticker: ticker,
            companyName: ticker,
            authorId: "author-1",
            authorName: "Investor",
            platform: "X",
            score: 112,
            platformPercentile: 0.08,
            direction: direction,
            lifecycle: lifecycle,
            horizon: "30D",
            targetPrice: nil,
            thesis: "A time-stamped public view",
            invalidation: nil,
            publishedAt: date ?? Date(timeIntervalSince1970: timestamp),
            evidenceURL: URL(string: "https://example.com/evidence")
        )
    }
}
