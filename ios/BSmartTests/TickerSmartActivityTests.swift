import XCTest
@testable import BSmart

final class TickerSmartActivityTests: XCTestCase {
    func testSmartActivityCombinesSourcesInReverseChronologicalOrder() throws {
        let account = makeAccountUpdate(day: "2026-08-10", score: 82)
        let money = makeMoneyMovement(day: "2026-08-12", score: 74)
        let otherTicker = makeAccountUpdate(ticker: "TSLA", day: "2026-08-13", score: 99)

        let items = TickerSmartActivityItem.items(
            ticker: "NVDA",
            accountUpdates: [account, otherTicker],
            moneyMovements: [money]
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.source), [.smartMoney, .smartAccount])
        XCTAssertFalse(items[0].actorName.isEmpty)
        XCTAssertEqual(items[1].actorName, "Author")
    }

    func testPriceActivityModelMergesEvidenceAndMapsBothSourcesToPriceLine() throws {
        var first = makeAccountUpdate(day: "2026-08-02", score: 80)
        first.priceEvidence = makeEvidence(
            viewDay: "2026-08-02",
            viewPrice: 102,
            days: ["2026-08-01", "2026-08-02", "2026-08-03"]
        )
        var second = makeAccountUpdate(day: "2026-08-04", score: 90)
        second.priceEvidence = makeEvidence(
            viewDay: "2026-08-04",
            viewPrice: 106,
            days: ["2026-08-03", "2026-08-04", "2026-08-05"]
        )
        let money = makeMoneyMovement(day: "2026-08-05", score: 88, price: 108)

        let model = TickerPriceActivityModel(
            currentPrice: 110,
            dataAsOf: date("2026-08-06"),
            accountUpdates: [first, second],
            moneyMovements: [money]
        )

        XCTAssertEqual(model.points.count, 6)
        XCTAssertEqual(model.markers.count, 3)
        XCTAssertEqual(model.markers(in: .oneMonth, source: .smartAccount).count, 2)
        XCTAssertEqual(model.markers(in: .oneMonth, source: .smartMoney).count, 1)
        XCTAssertEqual(model.markers(in: .oneMonth, source: .all).count, 3)
        XCTAssertEqual(model.points.last?.close, 110)
    }

    func testPriceRangeKeepsOnlyRequestedWindowWhenEnoughHistoryExists() throws {
        var update = makeAccountUpdate(day: "2026-08-10", score: 80)
        let calendar = Calendar(identifier: .gregorian)
        let start = date("2026-01-01")
        let days = (0..<220).compactMap { offset -> String? in
            calendar.date(byAdding: .day, value: offset, to: start).map { dayFormatter.string(from: $0) }
        }
        update.priceEvidence = makeEvidence(
            viewDay: "2026-08-08",
            viewPrice: 300,
            days: days
        )

        let model = TickerPriceActivityModel(
            currentPrice: 320,
            dataAsOf: date("2026-08-10"),
            accountUpdates: [update],
            moneyMovements: []
        )

        XCTAssertLessThan(model.points(in: .oneMonth).count, model.points(in: .sixMonths).count)
        XCTAssertGreaterThanOrEqual(model.points(in: .oneMonth).count, 28)
    }

    func testSnapshotBuildsUnifiedFeedAndPriceProjectionTogether() throws {
        var account = makeAccountUpdate(day: "2026-08-10", score: 82)
        account.authorAvatarURL = URL(string: "https://example.com/avatar.jpg")
        account.priceEvidence = makeEvidence(
            viewDay: "2026-08-10",
            viewPrice: 120,
            days: ["2026-08-09", "2026-08-10"]
        )
        let money = makeMoneyMovement(day: "2026-08-10", score: 76, price: 121)
        let intelligence = TickerIntelligence(
            ticker: "NVDA",
            companyName: "NVIDIA",
            currentPrice: 122,
            dayChangePercent: 0.01,
            dataAsOf: date("2026-08-11"),
            relationship: .confirmation,
            direction: .bullish,
            conclusion: "Supported",
            latestSignalId: nil,
            smartAccount: SmartAccountSnapshot(
                direction: .bullish,
                headline: "Bullish",
                detail: "Account detail",
                qualifiedAuthorCount: 1,
                latestUpdateAt: account.publishedAt
            ),
            smartMoney: SmartMoneySnapshot(
                coverage: .available,
                direction: .bullish,
                headline: "Buying",
                detail: "Money detail",
                qualifiedAccountCount: 1,
                latestMovementAt: money.observedAt
            )
        )

        let snapshot = TickerSmartActivitySnapshot(
            ticker: intelligence,
            accountUpdates: [account],
            moneyMovements: [money]
        )

        XCTAssertEqual(snapshot.activities.count, 2)
        XCTAssertEqual(snapshot.priceModel.markers.count, 2)
        guard let snapshotAccount = snapshot.activities.compactMap({ activity -> SmartAccountUpdate? in
            guard case let .account(update) = activity.payload else { return nil }
            return update
        }).first else {
            return XCTFail("Expected the Smart Account activity to remain available")
        }
        XCTAssertEqual(snapshotAccount.authorAvatarURL, account.authorAvatarURL)
    }

    private func makeAccountUpdate(
        ticker: String = "NVDA",
        day: String,
        score: Double
    ) -> SmartAccountUpdate {
        SmartAccountUpdate(
            id: UUID(),
            ticker: ticker,
            companyName: ticker,
            authorId: "author-\(day)",
            authorName: "Author",
            platform: "X",
            score: score,
            platformPercentile: 0.1,
            direction: .bullish,
            lifecycle: .new,
            horizon: "30D",
            targetPrice: 150,
            thesis: "Demand is improving.",
            invalidation: "Demand weakens.",
            publishedAt: date(day),
            evidenceURL: URL(string: "https://example.com/view")
        )
    }

    private func makeMoneyMovement(
        day: String,
        score: Double,
        price: Double? = nil
    ) -> SmartMoneyMovement {
        SmartMoneyMovement(
            id: UUID(),
            ticker: "NVDA",
            companyName: "NVIDIA",
            accountId: "capital",
            accountLabel: "Capital",
            accountScore: score,
            market: "xyz:NVDA",
            action: .increased,
            direction: .bullish,
            notionalBefore: 100_000,
            notionalAfter: 150_000,
            notionalChange: 50_000,
            leverage: 2,
            observedAt: date(day),
            evidenceURL: URL(string: "https://example.com/capital"),
            price: price
        )
    }

    private func makeEvidence(
        viewDay: String,
        viewPrice: Double,
        days: [String]
    ) -> SmartAccountPriceEvidence {
        SmartAccountPriceEvidence(
            ticker: "NVDA",
            viewDay: viewDay,
            viewPrice: viewPrice,
            latestDay: days.last ?? viewDay,
            latestPrice: Double(100 + max(days.count - 1, 0)),
            responsePercent: nil,
            source: "test",
            candles: days.enumerated().map { index, day in
                let close = Double(100 + index)
                return PriceCandle(
                    day: day,
                    open: close - 1,
                    high: close + 1,
                    low: close - 2,
                    close: close,
                    volume: 1_000
                )
            }
        )
    }

    private func date(_ day: String) -> Date {
        dayFormatter.date(from: day)!
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
