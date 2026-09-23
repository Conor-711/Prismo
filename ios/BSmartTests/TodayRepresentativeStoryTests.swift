import XCTest
@testable import BSmart

final class TodayRepresentativeStoryTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-14T12:00:00Z")!

    func testChartPricesRoundToWholeDollarsWithoutChangingDetailPrecision() {
        XCTAssertEqual(TodayRepresentativeStoryCopy.chartPrice(53.69), "$54")
        XCTAssertEqual(TodayRepresentativeStoryCopy.chartPrice(128.96), "$129")
        XCTAssertEqual(TodayRepresentativeStoryCopy.chartPrice(53.21), "$53")
        XCTAssertEqual(TodayRepresentativeStoryCopy.price(53.69), "$53.69")
    }

    func testMUUsesEarliestThreeCallsAndLaterHighNotSettlementReturn() async throws {
        let story = try await fixture("1707559719215489024", ticker: "MU",
                                      evidenceID: "3e286673-9b81-5d9b-b2a7-7d233c88df6f")
        XCTAssertEqual(story.earliestCalls.map(\.day), ["2025-12-05", "2026-01-02", "2026-02-06"])
        XCTAssertEqual(story.earliestCalls.map(\.price), [237.22, 315.42, 394.69])
        XCTAssertEqual(story.peak.value, 1255, accuracy: 0.01)
        XCTAssertEqual(story.peakChange, 429.0447, accuracy: 0.01)
        XCTAssertGreaterThan(story.bullishCount, 3)
        let text = localizedCopy(story, .simplifiedChinese)
        XCTAssertFalse(text.contains("2025.12.05"))
        XCTAssertTrue(text.hasPrefix("作者在 $237.22 看多 MU。"))
        XCTAssertTrue(text.contains("涨到 $315.42、$394.69"), text)
        XCTAssertFalse(text.contains("就"))
        XCTAssertFalse(text.contains("Wey How"))
        XCTAssertTrue(text.contains("429%"))
        XCTAssertFalse(text.contains("参考价"))
        XCTAssertFalse(text.contains("买入"))
    }

    func testLITEKeepsThreeEarlyBullishCallsWithoutChangingSelectedRepresentative() async throws {
        let story = try await fixture("1940360837547565056", ticker: "LITE",
                                      evidenceID: "dfd5ce60-4ce1-5df6-9c4c-0cda7c6ed915")
        XCTAssertEqual(story.earliestCalls.map(\.day), ["2025-12-22", "2026-03-13", "2026-04-16"])
        XCTAssertEqual(story.earliestCalls.map(\.price), [371.43, 622.50, 824.01])
        XCTAssertEqual(story.peak.value, 1085.68, accuracy: 0.01)
        XCTAssertEqual(story.account.representativeWork?.ticker, "AAOI")
        XCTAssertTrue(localizedCopy(story, .english).contains("two more bullish views"))
    }

    func testNVDADoesNotCreditPostPeakCallsForEarlierHigh() async throws {
        let story = try await fixture("1080667206902411265", ticker: "NVDA",
                                      evidenceID: "0eb40732-4955-5b13-9581-130a4447fa34")
        XCTAssertEqual(story.earliestCalls.map(\.day), ["2026-03-30", "2026-06-30", "2026-07-01"])
        XCTAssertEqual(story.earliestCalls.map(\.price), [167.52, 200.09, 197.58])
        XCTAssertEqual(story.peak.day, "2026-05-14")
        XCTAssertEqual(story.peakChange, 41.201, accuracy: 0.01)
        let text = localizedCopy(story, .simplifiedChinese)
        XCTAssertTrue(text.contains("后来回落到 $200.09、$197.58 时，作者又两次看多。"), text)
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "41%")?.lowerBound),
                          try XCTUnwrap(text.range(of: "后来回落")?.lowerBound))
    }

    func testFirstThreeChronologicalDeduplicatedNotLargestContribution() throws {
        var update = record()
        update.priceEvidence?.opinionMarkers = [
            marker(6, contribution: 100), marker(3, contribution: 1),
            marker(5, contribution: 200), marker(4, contribution: 0.1), marker(3, contribution: 50),
        ]
        let story = try XCTUnwrap(project([update]))
        XCTAssertEqual(story.earliestCalls.map(\.day), ["2026-01-02", "2026-01-03", "2026-01-04"])
        XCTAssertEqual(story.earliestCalls.map(\.price), [100, 100, 100])
        XCTAssertEqual(story.bullishCount, 5)
        XCTAssertEqual(story.peak.value, 150)
        XCTAssertFalse(story.prices.contains { $0.value == 9999 })
    }

    func testRejectsMismatchedIdentityFutureUnknownPriceAndUnsafeSource() {
        var intro = introduction()
        intro.firstOpinion?.price = .nan
        XCTAssertNil(project([record()], intro: intro))
        intro = introduction()
        intro.firstOpinion?.priceDay = "2026-01-05"
        XCTAssertNil(project([record()], intro: intro))
        intro.firstOpinion?.priceDay = "2025-12-01"
        XCTAssertNil(project([record()], intro: intro))
        intro = introduction()
        intro.firstOpinion?.evidenceURL = URL(string: "https://x.com/other/status/1")
        XCTAssertNil(project([record()], intro: intro))
        intro.firstOpinion?.evidenceURL = URL(string: "javascript:alert(1)")
        XCTAssertNil(project([record()], intro: intro))
        XCTAssertNil(project([record(author: "other")]))
        XCTAssertNil(project([]))
    }

    func testNeverUsesFutureCandlesOrPublicationDayHigh() throws {
        let story = try XCTUnwrap(project([record()], now: date("2026-01-06T15:00:00Z")))
        XCTAssertEqual(story.cutoff, "2026-01-05")
        XCTAssertLessThan(story.peak.value, 9999)
        XCTAssertTrue(story.calls.allSatisfy { $0.publishedAt <= date("2026-01-06T15:00:00Z") })
    }

    func testNonXStableSourceIDsAreAccepted() throws {
        let profile = SmartAccountProfile(id: "author", name: "Author", handle: "@author", platform: "YouTube",
            score: 100, scoreChange: 0, specialty: "Tech", horizon: "Medium term", recentTicker: "MU")
        let update = record(platform: "YouTube")
        var intro = introduction(platform: "YouTube")
        intro.firstOpinion?.evidenceURL = URL(string: "https://www.youtube.com/watch?v=video1")
        intro.firstOpinion?.sourcePostId = "video1"
        XCTAssertNotNil(TodayRepresentativeStory(account: profile, intro: intro, evidence: [update], now: now))
    }

    func testClusteredThreeTargetsStayApartAndInsideChart() {
        for width in [240.0, 300, 390] {
            let size = CGSize(width: width, height: 144)
            let result = BSmartChartMarkerLayout.positions(anchors: [.zero, .zero, .zero], size: size)
            XCTAssertEqual(result.count, 3)
            for (index, point) in result.enumerated() {
                XCTAssertTrue((22...(width - 22)).contains(point.x))
                XCTAssertTrue((22...122).contains(point.y))
                for other in result.dropFirst(index + 1) {
                    XCTAssertGreaterThanOrEqual(hypot(point.x - other.x, point.y - other.y), 44)
                }
            }
        }
    }

    private func fixture(_ authorID: String, ticker: String, evidenceID: String) async throws -> TodayRepresentativeStory {
        let client = BundleBSmartAPIClient()
        let accounts = try await client.fetchSmartAccounts()
        let account = try XCTUnwrap(accounts.first { $0.id == authorID && $0.platform.lowercased() == "x" })
        let evidence = try await client.fetchSmartAccountEvidence(accountID: authorID)
        let update = try XCTUnwrap(evidence.first { $0.id.uuidString.lowercased() == evidenceID })
        let intro = SmartAccountRepresentativeIntro(evidenceId: update.id, authorId: authorID,
            platform: update.platform, ticker: ticker, direction: update.direction, publishedAt: update.publishedAt,
            horizon: update.horizon, firstOpinion: update.firstOpinion)
        let updates = try await client.fetchSmartAccountUpdates()
        return try XCTUnwrap(TodayRepresentativeStory(account: account, intro: intro, evidence: evidence + updates, now: now))
    }

    private func localizedCopy(_ story: TodayRepresentativeStory, _ language: AppLanguage) -> String {
        let previous = BSmartLocalization.language
        defer { BSmartLocalization.configure(previous) }
        BSmartLocalization.configure(language)
        return TodayRepresentativeStoryCopy.text(story)
    }
    private var account: SmartAccountProfile {
        SmartAccountProfile(id: "author", name: "Author", handle: "@author", platform: "X",
            score: 100, scoreChange: 0, specialty: "Tech", horizon: "Medium term", recentTicker: "MU")
    }
    private func project(_ records: [SmartAccountUpdate], intro: SmartAccountRepresentativeIntro? = nil,
                         now: Date? = nil) -> TodayRepresentativeStory? {
        TodayRepresentativeStory(account: account, intro: intro ?? introduction(), evidence: records, now: now ?? self.now)
    }
    private func introduction(platform: String = "X") -> SmartAccountRepresentativeIntro {
        SmartAccountRepresentativeIntro(evidenceId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            authorId: "author", platform: platform, ticker: "MU", direction: .bullish,
            publishedAt: date("2026-01-02T22:00:00Z"), horizon: "20D",
            firstOpinion: SmartAccountFirstOpinion(publishedAt: date("2026-01-02T22:00:00Z"), direction: .bullish,
                priceBasis: "last_completed_daily_close", price: 100, priceDay: "2026-01-02",
                sourcePostId: "1", evidenceURL: URL(string: "https://x.com/author/status/1")))
    }
    private func record(author: String = "author", platform: String = "X") -> SmartAccountUpdate {
        SmartAccountUpdate(id: introduction().evidenceId, ticker: "MU", companyName: "Micron", authorId: author,
            authorName: "Author", platform: platform, score: 100, platformPercentile: 0.1, direction: .bullish,
            lifecycle: .new, horizon: "20D", targetPrice: nil, thesis: "Bullish", invalidation: nil,
            publishedAt: introduction().publishedAt, evidenceURL: URL(string: "https://x.com/author/status/1"),
            priceEvidence: SmartAccountPriceEvidence(ticker: "MU", viewDay: "2026-01-02", viewPrice: 9999,
                latestDay: "2026-01-08", latestPrice: 150, responsePercent: 50, source: "NASDAQ",
                candles: [2, 5, 6, 7, 8].map { day in
                    PriceCandle(day: String(format: "2026-01-%02d", day), open: 100,
                                high: day == 2 ? 9999 : 150, low: 90, close: 100, volume: 0)
                }))
    }
    private func marker(_ day: Int, contribution: Double) -> SmartAccountOpinionMarker {
        SmartAccountOpinionMarker(id: UUID(), publishedAt: date(String(format: "2026-01-%02dT15:00:00Z", day)),
            viewDay: String(format: "2026-01-%02d", day), viewPrice: 9999, direction: .bullish,
            contribution: contribution, horizon: "20D", thesis: "Bullish",
            evidenceURL: URL(string: "https://twitter.com/author/status/\(day)"))
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
