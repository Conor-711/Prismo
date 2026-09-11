import XCTest
@testable import BSmart

@MainActor
final class AccountAccessStoreTests: XCTestCase {
    func testRejectsUnsafeAuthenticationEndpointsBeforeSending() async {
        for raw in ["http://localhost:8081", "https://user:password@example.invalid", "https://example.invalid?key=value",
                    "https://example.invalid#fragment"] {
            let client = HTTPAccountAuthClient(baseURL: URL(string: raw)!, authorization: NoAccountAuthorization())
            do {
                _ = try await client.configuration()
                XCTFail("Unsafe authentication endpoint: \(raw)")
            } catch AccountAccessError.unavailable {
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    func testSecureStorageFailureDoesNotPublishIdentity() async {
        let storage = MemoryAccountSessionStore()
        storage.rejectsSave = true
        let store = testStore(client: TestAccountClient(), storage: storage)
        await store.load()
        await store.signIn(.apple) { _ in testAppleAssertion() }
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertNotNil(store.errorMessage)
    }

    func testNoClientDoesNotInventAnIdentity() async {
        let storage = MemoryAccountSessionStore()
        let store = testStore(client: nil, storage: storage)
        await store.load()
        await store.signIn(.apple) { _ in XCTFail("Must not authorize"); return testAppleAssertion() }
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertTrue(store.configuration.providers.isEmpty)
    }

    func testVerifiedSessionIsSavedOnlyAfterBackendVerification() async {
        let storage = MemoryAccountSessionStore()
        let client = TestAccountClient()
        let store = testStore(client: client, storage: storage)
        await store.load()
        await store.signIn(.apple) { _ in testAppleAssertion() }
        XCTAssertEqual(store.identity?.id, client.identity.id)
        XCTAssertEqual(storage.saved?.account.id, client.identity.id)
        XCTAssertFalse(store.configuration.depositsEnabled)
        XCTAssertFalse(store.configuration.tradingEnabled)
    }

    func testRejectedTokenCannotCreateLocalAccount() async {
        let storage = MemoryAccountSessionStore()
        let store = testStore(client: TestAccountClient(rejectsSignIn: true), storage: storage)
        await store.load()
        await store.signIn(.apple) { _ in testAppleAssertion() }
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertNotNil(store.errorMessage)
    }

    func testCancellationDoesNotBecomeAUserErrorOrAccount() async {
        let store = testStore(client: TestAccountClient(), storage: MemoryAccountSessionStore())
        await store.load()
        await store.signIn(.apple) { _ in throw AccountAccessError.cancelled }
        XCTAssertNil(store.identity)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isBusy)
    }

    func testMissingAppleAuthorizationCodeNeverCreatesLocalSession() async {
        let storage = MemoryAccountSessionStore()
        let store = testStore(client: TestAccountClient(), storage: storage)
        await store.load()
        await store.signIn(.apple) { _ in
            AccountIdentityAssertion(idToken: testAppleAssertion().idToken, authorizationCode: nil)
        }
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.isBusy)
    }

    func testCancelledSignInDiscardsLateServerResponseAndRevokesIt() async {
        let client = SuspendedAccountClient()
        let storage = MemoryAccountSessionStore()
        let store = testStore(client: client, storage: storage)
        await store.load()
        let operation = Task { await store.signIn(.apple) { _ in testAppleAssertion() } }
        await client.waitForSignIn()
        operation.cancel()
        await client.finishSignIn()
        await operation.value
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isBusy)
        let revocations = await client.revocations
        XCTAssertEqual(revocations, [String(repeating: "s", count: 64)])
    }

    func testCancelledTransportKeepsExistingAccountWithoutAnErrorAlert() async throws {
        let client = SuspendedAccountClient()
        let storage = MemoryAccountSessionStore()
        let original = TradingAccountSession(account: try await client.account(token: "original"),
            accessToken: String(repeating: "o", count: 64), expiresAt: Date().addingTimeInterval(1800))
        storage.saved = original
        let store = testStore(client: client, storage: storage)
        await store.load()
        let operation = Task { await store.signIn(.apple) { _ in testAppleAssertion() } }
        await client.waitForSignIn()
        operation.cancel()
        await client.failSignIn()
        await operation.value
        XCTAssertEqual(store.identity, original.account)
        XCTAssertEqual(storage.saved?.accessToken, original.accessToken)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isBusy)
        let revocations = await client.revocations
        XCTAssertTrue(revocations.isEmpty)
    }

    func testExpiredLocalSessionIsCleared() async {
        let storage = MemoryAccountSessionStore()
        let client = TestAccountClient()
        storage.saved = TradingAccountSession(account: client.identity, accessToken: String(repeating: "x", count: 64),
                                             expiresAt: .distantPast)
        let store = testStore(client: client, storage: storage)
        await store.load()
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
    }

    func testRemoteRevocationDoesNotTrapLocalSignOut() async {
        let storage = MemoryAccountSessionStore()
        let store = testStore(client: TestAccountClient(expiredOnLogout: true), storage: storage)
        await store.load()
        await store.signIn(.apple) { _ in testAppleAssertion() }
        await store.signOut()
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.errorMessage)
    }

    func testFundingLeaseRequiresVerifiedSessionAndIsRevokedOnSignOut() async throws {
        let client = TestAccountClient()
        let store = testStore(client: client, storage: MemoryAccountSessionStore())
        let wallet = DeviceWalletSummary(accountID: client.identity.id, address: PreflightTestFixture.wallet.address, recoveryVerified: true)
        XCTAssertThrowsError(try store.fundingSigningLease(wallet: wallet))
        await store.load()
        await store.signIn(.apple) { _ in testAppleAssertion() }
        let lease = try store.fundingSigningLease(wallet: wallet)
        XCTAssertNoThrow(try lease.check(wallet: wallet))
        XCTAssertEqual(store.walletAccountID, client.identity.id)
        await store.signOut()
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertNil(store.walletAccountID)
    }

    func testUnbackedInternalWalletStillRequiresSignedInAccountAndRevokesOnLogout() async throws {
        let client = TestAccountClient(identity: .init(id: UUID(), provider: .google))
        let store = testStore(client: client, storage: MemoryAccountSessionStore())
        let wallet = DeviceWalletSummary(accountID: client.identity.id, address: PreflightTestFixture.wallet.address, recoveryVerified: false)
        XCTAssertThrowsError(try store.fundingSigningLease(wallet: wallet))
        await store.load()
        await store.signIn(.google) { _ in .init(idToken: String(repeating: "test-google-id-token", count: 4), authorizationCode: nil) }
        let lease = try store.fundingSigningLease(wallet: wallet)
        XCTAssertNoThrow(try lease.check(wallet: wallet))
        await store.signOut()
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertFalse(wallet.recoveryVerified)
    }

    func testReplacingScopeAndReloadingIdentityRevokeEarlierFundingLeases() async throws {
        let client = TestAccountClient()
        let store = testStore(client: client, storage: MemoryAccountSessionStore())
        await store.load()
        await store.signIn(.apple) { _ in testAppleAssertion() }
        let wallet = DeviceWalletSummary(accountID: client.identity.id, address: PreflightTestFixture.wallet.address, recoveryVerified: true)
        let old = try store.fundingSigningLease(wallet: wallet)
        let current = try store.fundingSigningLease(wallet: wallet)
        XCTAssertThrowsError(try old.check(wallet: wallet))
        let wrong = DeviceWalletSummary(accountID: UUID(), address: wallet.address, recoveryVerified: true)
        XCTAssertThrowsError(try store.fundingSigningLease(wallet: wrong))
        XCTAssertNoThrow(try current.check(wallet: wallet))
        await store.load()
        XCTAssertThrowsError(try current.check(wallet: wallet))
    }
}

private final class MemoryAccountSessionStore: AccountSessionPersisting {
    var saved: TradingAccountSession?
    var rejectsSave = false
    func load() throws -> TradingAccountSession? { saved }
    func save(_ session: TradingAccountSession) throws {
        if rejectsSave { throw AccountAccessError.storage }
        saved = session
    }
    func clear() throws { saved = nil }
}

private struct NoAccountAuthorization: BSmartAuthorizationProviding {
    func accessToken() async throws -> String { throw AccountAccessError.unavailable }
    func invalidate() async {}
}

private struct TestAccountClient: AccountAuthenticating {
    var identity = TradingAccountIdentity(id: UUID(), provider: .apple)
    var rejectsSignIn = false
    var expiredOnLogout = false
    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.apple, .google], depositsEnabled: false, tradingEnabled: false)
    }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        .init(id: UUID(), nonce: String(repeating: "n", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        if rejectsSignIn { throw AccountAccessError.invalidResponse }
        return .init(account: identity, accessToken: String(repeating: "s", count: 64),
                     expiresAt: Date().addingTimeInterval(1800))
    }
    func account(token: String) async throws -> TradingAccountIdentity { identity }
    func signOut(token: String) async throws {
        if expiredOnLogout { throw AccountAccessError.expired }
    }
}

private func testAppleAssertion() -> AccountIdentityAssertion {
    .init(idToken: String(repeating: "test-id-token", count: 4), authorizationCode: String(repeating: "test-code", count: 4))
}

@MainActor
private func testStore(client: AccountAuthenticating?, storage: AccountSessionPersisting) -> AccountAccessStore {
    AccountAccessStore(client: client, storage: storage, appleCredentialState: AllowedTestAppleCredentialState())
}

@MainActor
private struct AllowedTestAppleCredentialState: AppleCredentialStateChecking {
    func check(userID: String?) async throws -> AppleCredentialStatus { .authorized }
}

private actor SuspendedAccountClient: AccountAuthenticating {
    let identity = TradingAccountIdentity(id: UUID(), provider: .apple)
    private var pending: CheckedContinuation<TradingAccountSession, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var revocations: [String] = []

    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.apple], depositsEnabled: false, tradingEnabled: false)
    }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        .init(id: UUID(), nonce: String(repeating: "n", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        try await withCheckedThrowingContinuation { pending in
            self.pending = pending
            started?.resume(); started = nil
        }
    }
    func waitForSignIn() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishSignIn() {
        pending?.resume(returning: .init(account: identity, accessToken: String(repeating: "s", count: 64),
                                        expiresAt: Date().addingTimeInterval(1800)))
        pending = nil
    }
    func failSignIn() {
        pending?.resume(throwing: URLError(.cancelled))
        pending = nil
    }
    func account(token: String) async throws -> TradingAccountIdentity { identity }
    func signOut(token: String) async throws {
        try Task.checkCancellation()
        revocations.append(token)
    }
}
