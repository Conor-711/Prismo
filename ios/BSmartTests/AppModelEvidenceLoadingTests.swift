import XCTest
@testable import BSmart

final class AppModelEvidenceLoadingTests: XCTestCase {
    @MainActor
    func testDailyRefreshUpdatesRankingsAndEvidenceWithoutReplacingPortfolioOrFollows() async throws {
        let name = "DailyRefresh.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let client = DailyEvidenceClient()
        let model = AppModel(client: client, defaults: defaults)
        await model.load()
        let first = try XCTUnwrap(model.smartAccounts.first)
        await model.loadSmartAccountEvidence(for: first)
        model.addPosition(ticker: "NVDA", companyName: "NVIDIA", shares: 4, averageCost: 123)
        model.toggleSmartAccountFollow(first.id)
        model.toggleSmartMoneyFollow("wallet")
        await client.advance()
        await model.refreshLiveIntelligence()
        XCTAssertEqual(model.smartAccounts.first?.score, 125)
        XCTAssertEqual(model.smartAccountUpdates.first?.thesis, "Day 2")
        XCTAssertEqual(model.smartAccountEvidenceByAuthor[first.id]?.first?.thesis, "Day 2")
        XCTAssertEqual(model.positions.first?.averageCost, 123)
        XCTAssertEqual(model.positions.first?.shares, 4)
        XCTAssertTrue(model.isFollowingSmartAccount(first.id))
        XCTAssertTrue(model.isFollowingSmartMoney("wallet"))
    }

    @MainActor
    func testFailedDailyRefreshRetainsLastSuccessfulSnapshot() async throws {
        let name = "OfflineRefresh.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let client = DailyEvidenceClient()
        let model = AppModel(client: client, defaults: defaults)
        await model.load()
        let prior = model.smartAccountUpdates
        await client.advance(fail: true)
        await model.refreshLiveIntelligence()
        XCTAssertEqual(model.smartAccountUpdates, prior)
        XCTAssertEqual(model.smartAccounts.first?.score, 110)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testSuccessfulEvidenceDeletionReplacesCachedHistory() async throws {
        let name = "DeletedEvidence.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let client = DailyEvidenceClient()
        let model = AppModel(client: client, defaults: defaults)
        await model.load()
        let account = try XCTUnwrap(model.smartAccounts.first)
        await model.loadSmartAccountEvidence(for: account)
        await client.advance(deleteEvidence: true)
        await model.refreshLiveIntelligence()
        XCTAssertEqual(model.smartAccountEvidenceByAuthor[account.id], [])
    }

    @MainActor
    func testFailedEvidenceRequestCanRetryAndSuccessfulEmptyResponseIsCached() async throws {
        let name = "EvidenceRetry.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let client = RetryingEvidenceClient()
        let model = AppModel(client: client, defaults: defaults)
        let account = SmartAccountProfile(id: "test", name: "Test", handle: "@test", platform: "X",
            score: 107, scoreChange: 0, specialty: "Mixed", horizon: "Medium term", recentTicker: nil)
        await model.loadSmartAccountEvidence(for: account)
        XCTAssertFalse(model.isLoadingAccountEvidence(account))
        await model.loadSmartAccountEvidence(for: account)
        await model.loadSmartAccountEvidence(for: account)
        let requests = await client.requests
        XCTAssertEqual(requests, 2)
    }
}

private actor DailyEvidenceClient: BSmartAPIClient {
    private var day = 1
    private var fail = false
    private var deleteEvidence = false
    func advance(fail: Bool = false, deleteEvidence: Bool = false) {
        day += 1
        self.fail = fail
        self.deleteEvidence = deleteEvidence
    }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] {
        if fail { throw URLError(.notConnectedToInternet) }
        return [SmartAccountProfile(id: "x:author", name: "Author", handle: "@author", platform: "X",
            score: day == 1 ? 110 : 125, scoreChange: 0, specialty: "Mixed", horizon: "Medium term", recentTicker: "NVDA")]
    }
    private func view() -> SmartAccountUpdate {
        SmartAccountUpdate(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, ticker: "NVDA",
            companyName: "NVIDIA", authorId: "x:author", authorName: "Author", platform: "X", score: 110,
            platformPercentile: 0.1, direction: .bullish, lifecycle: .new, horizon: "20D",
            targetPrice: nil, thesis: "Day \(day)", invalidation: nil,
            publishedAt: Date(timeIntervalSince1970: Double(day) * 86400), evidenceURL: nil)
    }
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [view()] }
    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] { deleteEvidence ? [] : [view()] }
    func fetchPortfolio() async throws -> [PortfolioPosition] { [] }
    func fetchSignals() async throws -> [PortfolioSignal] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }
}

private actor RetryingEvidenceClient: BSmartAPIClient {
    private(set) var requests = 0
    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] {
        requests += 1
        if requests == 1 { throw URLError(.notConnectedToInternet) }
        return []
    }
    func fetchPortfolio() async throws -> [PortfolioPosition] { [] }
    func fetchSignals() async throws -> [PortfolioSignal] { [] }
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { [] }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { [] }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { [] }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { [] }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { [] }
}
