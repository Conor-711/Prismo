import XCTest
@testable import BSmart

final class TodayInvestorDiscoveryHighlightTests: XCTestCase {
    private let account = SmartAccountProfile(id: "author", name: "Author", handle: "@author", platform: "X",
        score: 107, scoreChange: 0, specialty: "Semiconductors", horizon: "Medium term", recentTicker: "AAOI")

    func testKeepsRepresentativeOrderRatherThanPickingLargestReturn() {
        let first = work("AAOI", stockReturn: 62.49)
        let result = TodayInvestorDiscoveryHighlight(account: account, representatives: [first, work("AXTI", stockReturn: 326)])
        XCTAssertEqual(result.work?.id, first.id)
        XCTAssertEqual(result.stockReturn, 62.49)
        XCTAssertEqual(result.tradingSessions, 60)
    }

    func testDoesNotFlipStockReturnIntoAuthorPerformanceForBearishView() {
        let result = TodayInvestorDiscoveryHighlight(account: account,
            representatives: [work("MU", direction: .bearish, stockReturn: -28)])
        XCTAssertEqual(result.stockReturn, -28)
        XCTAssertEqual(result.work?.direction, .bearish)
    }

    func testRejectsOtherIdentityUnsettledLatestAndFutureEvidence() {
        let valid = work("NVDA")
        var latest = work("META")
        latest.evidenceRole = "latest"
        let result = TodayInvestorDiscoveryHighlight(account: account, representatives: [
            work("MU", author: "other"), work("MU", platform: "YouTube"),
            work("MU", status: "pending"), latest, work("MU", date: .distantFuture), valid,
        ])
        XCTAssertEqual(result.work?.id, valid.id)
    }

    func testMissingEvidenceAndInvalidNumbersDoNotBecomeZeroOrInventedHorizon() {
        XCTAssertNil(TodayInvestorDiscoveryHighlight(account: account, representatives: []).work)
        let result = TodayInvestorDiscoveryHighlight(account: account,
            representatives: [work("MU", stockReturn: .nan, horizon: "unknown")])
        XCTAssertNil(result.stockReturn)
        XCTAssertNil(result.tradingSessions)
    }

    func testEmbeddedIntroWorksWithoutFetchingFullEvidence() {
        var profile = account
        profile.representativeWork = SmartAccountRepresentativeIntro(evidenceId: UUID(), authorId: account.id,
            platform: account.platform, ticker: "AAOI", direction: .bullish, publishedAt: .distantPast,
            horizon: "60D", stockReturnPercent: 62.49)
        let result = TodayInvestorDiscoveryHighlight(account: profile, representatives: [])
        XCTAssertNil(result.work)
        XCTAssertEqual(result.intro?.ticker, "AAOI")
        XCTAssertEqual(result.stockReturn, 62.49)
    }

    func testWrongIdentityAndFutureOrOppositeFirstOpinionAreRejected() {
        var profile = account
        let first = SmartAccountFirstOpinion(publishedAt: .distantFuture, direction: .bullish,
            priceBasis: "last_completed_daily_close", price: 50, priceDay: "2026-01-01")
        var intro = SmartAccountRepresentativeIntro(evidenceId: UUID(), authorId: account.id,
            platform: account.platform, ticker: "AAOI", direction: .bullish, publishedAt: .distantPast,
            horizon: "60D", firstOpinion: first)
        profile.representativeWork = intro
        XCTAssertNil(TodayInvestorDiscoveryHighlight(account: profile, representatives: []).firstOpinion)
        intro.firstOpinion = SmartAccountFirstOpinion(publishedAt: .distantPast, direction: .bearish,
            priceBasis: "last_completed_daily_close")
        profile.representativeWork = intro
        XCTAssertNil(TodayInvestorDiscoveryHighlight(account: profile, representatives: []).firstOpinion)
        profile.representativeWork = SmartAccountRepresentativeIntro(evidenceId: UUID(), authorId: "other",
            platform: account.platform, ticker: "MU", direction: .bullish, publishedAt: .distantPast, horizon: "5D")
        XCTAssertNil(TodayInvestorDiscoveryHighlight(account: profile, representatives: []).intro)
    }

    func testReferencePriceRequiresKnownBasisDateAndPositiveFiniteValue() {
        for value in [Double.nan, Double.infinity, 0, -10] {
            let first = SmartAccountFirstOpinion(publishedAt: .distantPast, direction: .bullish,
                priceBasis: "last_completed_daily_close", price: value, priceDay: "2026-01-01")
            XCTAssertNil(first.referencePrice)
        }
        let unknown = SmartAccountFirstOpinion(publishedAt: .distantPast, direction: .bullish,
            priceBasis: "unknown", price: 50, priceDay: "2026-01-01")
        XCTAssertNil(unknown.referencePrice)
    }

    func testBundledDiscoveryHasInstantRepresentativeCoverage() async throws {
        let accounts = try await BundleBSmartAPIClient().fetchSmartAccounts()
        let pool = TodayInvestorDiscovery(accounts: accounts).candidates(sector: nil)
        XCTAssertEqual(pool.count, 87)
        XCTAssertTrue(pool.allSatisfy {
            TodayInvestorDiscoveryHighlight(account: $0.account, representatives: []).intro != nil
        })
        let featured = try XCTUnwrap(accounts.first { $0.handle.lowercased() == "@aleabitoreddit" })
        let first = try XCTUnwrap(featured.representativeWork?.firstOpinion)
        XCTAssertEqual(first.referencePrice, 53.69)
        XCTAssertEqual(first.priceDay, "2026-02-26")
    }

    private func work(_ ticker: String, author: String = "author", platform: String = "X",
                      direction: SignalDirection = .bullish, stockReturn: Double = 10,
                      status: String = "settled", horizon: String = "60D", date: Date = .distantPast) -> SmartAccountUpdate {
        SmartAccountUpdate(id: UUID(), ticker: ticker, companyName: ticker, authorId: author, authorName: author,
            platform: platform, score: 107, platformPercentile: 0.14, direction: direction, lifecycle: .new,
            horizon: horizon, targetPrice: nil, thesis: "Source view", invalidation: nil, publishedAt: date,
            evidenceURL: nil, evidenceRole: "representative",
            settlement: SmartAccountSettlementEvidence(status: status, horizon: horizon,
                entryDay: "2026-03-05", exitDay: "2026-05-29", entryPrice: nil, exitPrice: nil,
                tickerReturnPercent: stockReturn, marketBenchmarkReturnPercent: nil,
                marketExcessReturnPercent: nil, actualHit: nil, contribution: 1,
                industryBenchmarkTicker: nil, industryBenchmarkReturnPercent: nil,
                industryExcessReturnPercent: nil, industryActualHit: nil, settlementVersion: nil))
    }
}
