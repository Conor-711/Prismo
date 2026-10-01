import XCTest
@testable import BSmart

@MainActor
final class NativeTraderDetailStoreTests: XCTestCase {
    func testPublicProfileUsesSameNativeIdentityAndNeverInventsPerformance() {
        let profile = FeedPublicProfile(id: UUID(), nickname: "Casey", avatarURL: nil, handle: "casey", bio: "Trader")
        let investor = profile.smartAccount()
        XCTAssertEqual(investor.nativeProfileID, profile.id)
        XCTAssertEqual(investor.nativePublicProfile, profile)
        XCTAssertEqual(investor.platform, "bsmart")
        XCTAssertNil(investor.nativePerformance)
        XCTAssertNil(investor.rank)
        var other = investor
        other.topTickers = ["AAPL"]
        other.effectiveSamples = 12
        other.nativePerformance = .init(closedTrades: 2, wins: 1, realizedReturn: 0.02, netPnlUSD: 1,
                                        rank: nil, percentile: nil, asOf: nil)
        XCTAssertEqual(profile.smartAccount(matching: other).nativePerformance, other.nativePerformance)
        XCTAssertEqual(profile.smartAccount(matching: other).topTickers, ["AAPL"])
        XCTAssertEqual(profile.smartAccount(matching: other).effectiveSamples, 12)
        XCTAssertNil(FeedPublicProfile(id: UUID(), nickname: "Other", avatarURL: nil)
            .smartAccount(matching: other).nativePerformance)
    }

    func testLiveEquityPositionsAndHistoryLoadIndependently() async throws {
        let store = NativeTraderDetailStore(), client = StubTraderClient()
        await store.refresh(profileID: UUID(), viewerID: UUID(), client: client)
        XCTAssertEqual(store.portfolio?.perpsEquityUSD, "123")
        XCTAssertEqual(store.portfolio?.positions.first?.leverage, 3)
        XCTAssertEqual(store.portfolio?.positions.first?.unrealizedPnLUSD, "2")
        XCTAssertNotNil(store.socialSnapshot)
        XCTAssertTrue(store.trades.hasLoaded)
    }

    func testPortfolioFailureNeverBecomesZeroAndDoesNotBlockHistory() async {
        let store = NativeTraderDetailStore(), client = StubTraderClient()
        let profileID = UUID()
        client.failPortfolio = true
        await store.refresh(profileID: profileID, viewerID: UUID(), client: client)
        XCTAssertNil(store.portfolio)
        XCTAssertTrue(store.portfolioFailed)
        XCTAssertTrue(store.trades.hasLoaded)
        client.failPortfolio = false
        await store.retryPortfolio(profileID, client: client)
        XCTAssertEqual(store.portfolio?.perpsEquityUSD, "123")
        XCTAssertFalse(store.portfolioFailed)
    }

    func testClearedPageRejectsLateAccountData() async {
        let store = NativeTraderDetailStore(), client = StubTraderClient()
        client.pausePortfolio = true
        let pending = Task { await store.refresh(profileID: UUID(), viewerID: UUID(), client: client) }
        while client.portfolioContinuation == nil { await Task.yield() }
        store.clear()
        client.portfolioContinuation?.resume()
        await pending.value
        XCTAssertNil(store.portfolio)
        XCTAssertNil(store.socialSnapshot)
        XCTAssertTrue(store.trades.items.isEmpty)
    }

    func testSignedOutNeverLoadsWalletData() async {
        let store = NativeTraderDetailStore(), client = StubTraderClient()
        await store.refresh(profileID: UUID(), viewerID: nil, client: client)
        XCTAssertEqual(client.portfolioReads, 0)
        XCTAssertNil(store.portfolio)
    }

    func testNewViewerRejectsPreviousViewersLateFailure() async {
        let store = NativeTraderDetailStore(), oldClient = StubTraderClient(), newClient = StubTraderClient()
        let profileID = UUID()
        oldClient.pausePortfolio = true
        oldClient.failPortfolio = true
        let pending = Task { await store.refresh(profileID: profileID, viewerID: UUID(), client: oldClient) }
        while oldClient.portfolioContinuation == nil { await Task.yield() }
        await store.refresh(profileID: profileID, viewerID: UUID(), client: newClient)
        oldClient.portfolioContinuation?.resume()
        await pending.value
        XCTAssertEqual(store.portfolio?.perpsEquityUSD, "123")
        XCTAssertFalse(store.portfolioFailed)
    }

    func testRetryFromAnotherProfileCannotReplaceActivePortfolio() async {
        let store = NativeTraderDetailStore(), client = StubTraderClient()
        await store.refresh(profileID: UUID(), viewerID: UUID(), client: client)
        client.failPortfolio = true
        await store.retryPortfolio(UUID(), client: client)
        XCTAssertEqual(client.portfolioReads, 1)
        XCTAssertEqual(store.portfolio?.perpsEquityUSD, "123")
        XCTAssertFalse(store.portfolioFailed)
        store.clear()
        await store.retryPortfolio(UUID(), client: client)
        XCTAssertEqual(client.portfolioReads, 1)
    }
}

@MainActor
private final class StubTraderClient: NativeTraderDetailProviding {
    var failPortfolio = false
    var pausePortfolio = false
    var portfolioReads = 0
    var portfolioContinuation: CheckedContinuation<Void, Never>?

    func portfolio(_ profileID: UUID) async throws -> FeedPublicPortfolio {
        portfolioReads += 1
        if pausePortfolio { await withCheckedContinuation { portfolioContinuation = $0 } }
        if failPortfolio { throw BSmartAPIError.invalidResponse }
        let json = """
        {"status":"ready","perpsEquityUSD":"123","equityAsOf":1800000000000,
         "spotUSDC":"10","accountValueUSD":"123","dayChangeUSD":"2",
         "positions":[{"coin":"xyz:AAPL","side":"long","size":"1","valueUSD":"100",
           "entryPriceUSD":"98","unrealizedPnLUSD":"2","returnOnEquity":"0.06","leverage":3}],
         "history":{"day":[],"week":[],"month":[]}}
        """
        return try JSONDecoder().decode(FeedPublicPortfolio.self, from: Data(json.utf8))
    }
    func social(accountID: UUID) async throws -> SocialSnapshot { .empty }
    func follow(_ profileID: UUID, enabled: Bool, accountID: UUID) async throws -> SocialSnapshot { .empty }
    func trades(profileID: UUID, offset: Int) async throws -> TradeFeedPage {
        .init(items: [], nextOffset: nil)
    }
}
