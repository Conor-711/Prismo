import XCTest
@testable import BSmart

@MainActor
final class AppContentAccessTests: XCTestCase {
    func testTestLoginDoesNotCreateIdentityCredentialsOrWalletAccess() async {
        let storage = RenewalMemoryStorage()
        let store = AccountAccessStore(client: nil, storage: storage)
        store.startTestSession()
        XCTAssertFalse(store.isTestSession)
        await store.load()
        store.startTestSession()
        XCTAssertTrue(store.isTestSession)
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertFalse(store.canAccessAppContent)
        XCTAssertNil(store.walletAccountID)
        do { _ = try await store.walletRegistration(); XCTFail("Test login must not authorize a wallet") }
        catch {}
        do { _ = try await store.withFeedSession { _ in true }; XCTFail("Test login must not authorize cloud requests") }
        catch {}
        let relaunched = AccountAccessStore(client: nil, storage: storage)
        await relaunched.load()
        XCTAssertFalse(relaunched.isTestSession)
        await store.signOut()
        XCTAssertFalse(store.isTestSession)
        XCTAssertNil(store.identity)
    }

    func testTestLoginCannotReplaceVerifiedAccount() async {
        let saved = session()
        let store = AccountAccessStore(client: GateAccountClient(saved), storage: RenewalMemoryStorage(saved))
        await store.load()
        store.startTestSession()
        XCTAssertFalse(store.isTestSession)
        XCTAssertEqual(store.identity, saved.account)
    }

    func testVerifiedSignInEndsTestSession() async {
        let saved = renewalSession()
        let store = AccountAccessStore(client: RenewalTestClient(saved), storage: RenewalMemoryStorage())
        await store.load()
        store.startTestSession()
        XCTAssertTrue(store.isTestSession)
        await store.signIn(.google) { _ in
            .init(idToken: String(repeating: "disposable", count: 8), authorizationCode: nil)
        }
        XCTAssertFalse(store.isTestSession)
        XCTAssertEqual(store.identity, saved.account)
        XCTAssertTrue(store.canAccessAppContent)
    }

    func testNoSessionCannotAccessContent() async {
        let store = AccountAccessStore(client: nil, storage: RenewalMemoryStorage())
        XCTAssertFalse(store.canAccessAppContent)
        await store.load()
        XCTAssertTrue(store.didLoad)
        XCTAssertFalse(store.canAccessAppContent)
    }

    func testCachedIdentityCannotExposeContentBeforeRestoreFinishes() async throws {
        let saved = session()
        let client = GateAccountClient(saved, suspendRestore: true)
        let store = AccountAccessStore(client: client, storage: RenewalMemoryStorage(saved))
        let restore = Task { await store.load() }
        try await client.waitForPending()
        XCTAssertEqual(store.identity, saved.account)
        XCTAssertFalse(store.didLoad)
        XCTAssertFalse(store.canAccessAppContent)
        await client.finish()
        await restore.value
        XCTAssertTrue(store.canAccessAppContent)
    }

    func testExpiredIdentityCannotAccessContent() async {
        let saved = session()
        var now = Date()
        let store = AccountAccessStore(client: GateAccountClient(saved),
            storage: RenewalMemoryStorage(saved), now: { now })
        await store.load()
        XCTAssertTrue(store.canAccessAppContent)
        now = saved.expiresAt.addingTimeInterval(1)
        XCTAssertNotNil(store.identity)
        XCTAssertFalse(store.canAccessAppContent)
    }

    func testLogoutClosesContentBeforeRemoteRevocationAndStaysClosedOffline() async throws {
        let saved = session()
        let storage = RenewalMemoryStorage(saved)
        let client = GateAccountClient(saved, suspendLogout: true)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        XCTAssertTrue(store.canAccessAppContent)
        let logout = Task { await store.signOut() }
        try await client.waitForPending()
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertFalse(store.canAccessAppContent)
        await client.finish(failing: true)
        await logout.value
        XCTAssertFalse(store.canAccessAppContent)
    }

    func testAccountChangeClearsNavigationAndPendingLinks() {
        let router = AppRouter()
        router.openDailyDigest()
        router.openSignal(UUID())
        router.setTabBarHidden(true, token: UUID())
        router.selection = .portfolio
        router.resetForAccountChange()
        XCTAssertEqual(router.selection, .today)
        XCTAssertTrue(router.todayPath.isEmpty)
        XCTAssertNil(router.pendingSignalID)
        XCTAssertFalse(router.isTabBarHidden)
    }

    private func session() -> TradingAccountSession {
        .init(account: .init(id: UUID(), provider: .google), accessToken: String(repeating: "s", count: 64),
              expiresAt: Date().addingTimeInterval(1800), refreshToken: "test-refresh-token",
              refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
    }
}

private actor GateAccountClient: AccountAuthenticating {
    let session: TradingAccountSession
    let suspendRestore: Bool
    let suspendLogout: Bool
    private var pending: CheckedContinuation<Void, Error>?

    init(_ session: TradingAccountSession, suspendRestore: Bool = false, suspendLogout: Bool = false) {
        self.session = session; self.suspendRestore = suspendRestore; self.suspendLogout = suspendLogout
    }
    func configuration() async throws -> AccountAuthConfiguration { .unavailable }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge { throw AccountAccessError.unavailable }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        throw AccountAccessError.unavailable
    }
    func account(token: String) async throws -> TradingAccountIdentity {
        if suspendRestore { try await withCheckedThrowingContinuation { pending = $0 } }
        return session.account
    }
    func signOut(token: String) async throws {
        if suspendLogout { try await withCheckedThrowingContinuation { pending = $0 } }
    }
    func waitForPending() async throws {
        for _ in 0..<1000 {
            if pending != nil { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AccountAccessError.unavailable
    }
    func finish(failing: Bool = false) {
        if failing { pending?.resume(throwing: URLError(.notConnectedToInternet)) }
        else { pending?.resume() }
        pending = nil
    }
}
