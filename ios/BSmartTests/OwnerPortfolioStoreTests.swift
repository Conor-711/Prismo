import XCTest
@testable import BSmart

@MainActor
final class OwnerPortfolioStoreTests: XCTestCase {
    func testVerifiedValueLoadsWithoutHistoryAndRefreshFailureRetainsIt() async throws {
        let account = await signedInAccount()
        var calls = 0
        let store = OwnerPortfolioStore(fetch: { _, _ in
            calls += 1
            if calls > 1 { throw AccountAccessError.unavailable }
            return try Self.portfolio(value: "7.25")
        })
        await store.load(account: account)
        XCTAssertEqual(store.portfolio?.accountValueUSD, "7.25")
        XCTAssertFalse(store.hasUnavailableAccountValue)
        await store.load(account: account)
        XCTAssertEqual(calls, 1)
        await store.load(account: account, force: true)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(store.failed)
        XCTAssertEqual(store.portfolio?.accountValueUSD, "7.25")
        XCTAssertFalse(store.isLoading)
    }

    func testLegacyMissingNetWorthRemainsUnavailableRatherThanBecomingZero() async throws {
        let account = await signedInAccount()
        let store = OwnerPortfolioStore(fetch: { _, _ in try Self.portfolio(value: nil) })
        await store.load(account: account)
        XCTAssertTrue(store.hasUnavailableAccountValue)
        XCTAssertNil(store.portfolio?.accountValueUSD)
        XCTAssertFalse(store.failed)
    }

    func testCoalescedReadSurvivesTabTaskCancellationButCannotSurviveClear() async throws {
        let account = await signedInAccount()
        var continuation: CheckedContinuation<FeedPublicPortfolio, Error>?
        var calls = 0
        let store = OwnerPortfolioStore(fetch: { _, _ in
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        let first = Task { await store.load(account: account) }
        while continuation == nil { await Task.yield() }
        first.cancel()
        let second = Task { await store.load(account: account) }
        await Task.yield()
        continuation!.resume(returning: try Self.portfolio(value: "5"))
        await first.value; await second.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.portfolio?.accountValueUSD, "5")

        continuation = nil
        let third = Task { await store.load(account: account, force: true) }
        while continuation == nil { await Task.yield() }
        store.clear()
        continuation!.resume(returning: try Self.portfolio(value: "8"))
        await third.value
        XCTAssertNil(store.portfolio)
        XCTAssertNil(store.accountID)
        XCTAssertFalse(store.isLoading)
    }

    private static func portfolio(value: String?) throws -> FeedPublicPortfolio {
        let json = """
        {"status":"ready","spotUSDC":"7.25","accountValueUSD":\(value.map { "\"\($0)\"" } ?? "null"),
         "positions":[],"history":{"day":[],"week":[],"month":[]}}
        """
        return try JSONDecoder().decode(FeedPublicPortfolio.self, from: Data(json.utf8))
    }

    private func signedInAccount() async -> AccountAccessStore {
        let client = PortfolioAccountClient()
        let storage = PortfolioAccountStorage(session: .init(account: client.identity,
            accessToken: String(repeating: "test", count: 16), expiresAt: Date().addingTimeInterval(3600)))
        let account = AccountAccessStore(client: client, storage: storage)
        await account.load()
        XCTAssertEqual(account.identity?.id, client.identity.id)
        return account
    }
}

private final class PortfolioAccountStorage: AccountSessionPersisting {
    var session: TradingAccountSession?
    init(session: TradingAccountSession) { self.session = session }
    func load() throws -> TradingAccountSession? { session }
    func save(_ session: TradingAccountSession) throws { self.session = session }
    func clear() throws { session = nil }
}

private struct PortfolioAccountClient: AccountAuthenticating {
    let identity = TradingAccountIdentity(id: UUID(), provider: .google)
    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.google], depositsEnabled: false, tradingEnabled: false)
    }
    func account(token: String) async throws -> TradingAccountIdentity { identity }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge { throw AccountAccessError.unavailable }
    func signIn(provider: AccountIdentityProvider, challenge: UUID,
                assertion: AccountIdentityAssertion) async throws -> TradingAccountSession { throw AccountAccessError.unavailable }
    func signOut(token: String) async throws {}
}
