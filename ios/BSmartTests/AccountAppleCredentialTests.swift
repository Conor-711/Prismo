import XCTest
@testable import BSmart

@MainActor
final class AccountAppleCredentialTests: XCTestCase {
    func testLegacyAppleSessionRequiresNewNativeSignInButGoogleDoesNotQueryApple() async throws {
        for provider in [AccountIdentityProvider.apple, .google] {
            let previous = renewalSession(account: .init(id: UUID(), provider: provider))
            let storage = makeStorage()
            defer { try? storage.clear() }
            try storage.save(previous)
            let client = AppleAccountTestClient(previous)
            let native = NativeAppleCredentialStateClient { _, _ in XCTFail("Legacy reference must not reach Apple") }
            let store = AccountAccessStore(client: client, storage: storage, appleCredentialState: native)
            await store.load()
            if provider == .apple {
                XCTAssertNil(store.identity)
                XCTAssertNil(try storage.load())
                let requests = await client.accountRequests
                let revoked = await client.familyRevocations
                XCTAssertTrue(requests.isEmpty)
                XCTAssertEqual(revoked, [previous.refreshToken!])
            } else {
                XCTAssertEqual(store.identity, previous.account)
                XCTAssertEqual(try storage.load(), previous)
            }
        }
    }

    func testCachedCheckExpiresAndExplicitRevocationStopsWalletAccessAndRevokesOnlyAppFamily() async throws {
        var now = Date()
        let previous = appleSession()
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let client = AppleAccountTestClient(previous)
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: client, storage: storage, now: { now }, appleCredentialState: native)
        await store.load()
        _ = try await store.walletRegistration()
        XCTAssertEqual(native.requests, ["opaque-apple-user"])
        let wallet = summary(previous)
        let lease = try store.fundingSigningLease(wallet: wallet)
        now = now.addingTimeInterval(61)
        XCTAssertNil(store.walletAccountID)
        native.result = .revoked
        do { _ = try await store.walletRegistration(); XCTFail("Revoked wallet access") }
        catch AccountAccessError.expired {} catch { XCTFail("Unexpected error") }
        XCTAssertNil(store.identity)
        XCTAssertNil(try storage.load())
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        let revoked = await client.familyRevocations
        let walletRequests = await client.walletRequests
        XCTAssertEqual(revoked, [previous.refreshToken!])
        XCTAssertEqual(walletRequests, [previous.accessToken])
    }

    func testNotificationImmediatelyStopsLeaseOutageKeepsCredentialsAndRetryRestoresAccess() async throws {
        let previous = appleSession()
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let client = AppleAccountTestClient(previous)
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: client, storage: storage, appleCredentialState: native)
        await store.load()
        let wallet = summary(previous)
        let lease = try store.fundingSigningLease(wallet: wallet)
        native.fails = true
        store.appleCredentialDidChange()
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertNil(store.walletAccountID)
        await store.recheckAppleCredential()
        XCTAssertEqual(try storage.load(), previous)
        XCTAssertEqual(try storage.appleUserID(for: previous), "opaque-apple-user")
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertNil(store.walletAccountID)
        XCTAssertEqual(store.errorMessage, AccountAccessError.credentialUnavailable.localizedDescription)
        native.fails = false
        await store.recheckAppleCredential()
        XCTAssertEqual(store.walletAccountID, previous.account.id)
        XCTAssertNil(store.errorMessage)
        XCTAssertNoThrow(try store.fundingSigningLease(wallet: wallet))
        let revoked = await client.familyRevocations
        XCTAssertTrue(revoked.isEmpty)
    }

    func testRenewalCarriesReferenceButDoesNotExtendTheNativeCheckWindow() async throws {
        var now = Date()
        let previous = appleSession(lifetime: 90)
        let next = renewalSession(account: previous.account, version: "replacement")
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let client = AppleAccountTestClient(previous)
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: client, storage: storage, now: { now }, appleCredentialState: native)
        await store.load()
        await client.replace(next)
        now = now.addingTimeInterval(40)
        _ = try await store.walletRegistration()
        XCTAssertEqual(native.requests.count, 1)
        XCTAssertEqual(try storage.appleUserID(for: next), "opaque-apple-user")
        XCTAssertEqual(try storage.load(), next)
        now = now.addingTimeInterval(21)
        native.fails = true
        do { _ = try await store.walletRegistration(); XCTFail("Renewal extended native authorization") }
        catch AccountAccessError.credentialUnavailable {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(native.requests.count, 2)
        XCTAssertNil(store.walletAccountID)
        XCTAssertEqual(try storage.load(), next)
    }

    func testLateNativeStateAfterGoogleSignInCannotEraseNewSession() async throws {
        let previous = appleSession()
        let next = renewalSession(version: "google-login")
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let client = AppleAccountTestClient(previous)
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: client, storage: storage, appleCredentialState: native)
        await store.load()
        store.appleCredentialDidChange()
        native.suspended = true
        let check = Task { try await store.walletRegistration() }
        try await native.waitForRequest()
        await client.replace(next)
        await store.signIn(.google) { _ in .init(idToken: String(repeating: "disposable", count: 8), authorizationCode: nil) }
        native.finish(.revoked)
        do { _ = try await check.value; XCTFail("Late native check returned wallet") } catch {}
        XCTAssertEqual(try storage.load(), next)
        XCTAssertNil(try storage.appleUserID(for: next))
        XCTAssertEqual(store.identity, next.account)
        XCTAssertNil(store.errorMessage)
        XCTAssertNoThrow(try store.fundingSigningLease(wallet: summary(next)))
    }

    func testNativeReferencePersistsOnlyAfterBackendAndSystemChecks() async throws {
        for rejected in [false, true] {
            let next = appleSession()
            let storage = makeStorage()
            defer { try? storage.clear() }
            let client = AppleAccountTestClient(next)
            await client.rejectSignIn(rejected)
            let native = ControlledAppleCredentialState()
            let store = AccountAccessStore(client: client, storage: storage, appleCredentialState: native)
            await store.load()
            await store.signIn(.apple) { _ in self.assertion() }
            if rejected {
                XCTAssertNil(try storage.load())
                XCTAssertNil(store.identity)
                XCTAssertTrue(native.requests.isEmpty)
            } else {
                XCTAssertEqual(try storage.load(), next)
                XCTAssertEqual(try storage.appleUserID(for: next), "opaque-apple-user")
                XCTAssertEqual(native.requests, ["opaque-apple-user"])
                XCTAssertEqual(store.identity, next.account)
            }
        }
    }

    func testInvalidationDuringSignInDoesNotPersistLateAuthorizationAndCleansUpServerSession() async throws {
        let next = appleSession()
        let storage = makeStorage()
        defer { try? storage.clear() }
        let client = AppleAccountTestClient(next)
        let native = ControlledAppleCredentialState()
        native.suspended = true
        let store = AccountAccessStore(client: client, storage: storage, appleCredentialState: native)
        await store.load()
        let signIn = Task { await store.signIn(.apple) { _ in self.assertion() } }
        try await native.waitForRequest()
        store.appleCredentialDidChange()
        native.finish(.authorized)
        await signIn.value
        XCTAssertNil(try storage.load())
        XCTAssertNil(store.identity)
        let cleanups = await client.accessRevocations
        XCTAssertEqual(cleanups, [next.accessToken])
    }

    func testAuthorizedNativeStateCannotOverrideRejectedBackendIdentity() async throws {
        let previous = appleSession()
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let client = AppleAccountTestClient(previous)
        await client.rejectAccount()
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: client, storage: storage, appleCredentialState: native)
        await store.load()
        XCTAssertNil(store.identity)
        XCTAssertNil(store.walletAccountID)
        XCTAssertNil(try storage.load())
        XCTAssertEqual(native.requests.count, 1)
    }

    func testWallClockRollbackForcesANewCheckWithoutErasingCredentialsOnOutage() async throws {
        var now = Date()
        let previous = appleSession()
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: AppleAccountTestClient(previous), storage: storage,
                                       now: { now }, appleCredentialState: native)
        await store.load()
        now = now.addingTimeInterval(-1)
        XCTAssertNil(store.walletAccountID)
        native.fails = true
        do { _ = try await store.walletRegistration(); XCTFail("Wall-clock rollback reused authorization") }
        catch AccountAccessError.credentialUnavailable {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(native.requests.count, 2)
        XCTAssertEqual(try storage.load(), previous)
    }

    func testLateIssuedLeaseCannotOutliveOriginalNativeCheckWhenWallClockStops() async throws {
        let now = Date()
        let continuous = CredentialMonotonicTestClock()
        let previous = appleSession()
        let storage = makeStorage()
        defer { try? storage.clear() }
        try storage.save(previous, appleUserID: "opaque-apple-user")
        let native = ControlledAppleCredentialState()
        let store = AccountAccessStore(client: AppleAccountTestClient(previous), storage: storage,
            now: { now }, appleCredentialState: native, continuousNow: { continuous.now })
        await store.load()
        continuous.advance(55)
        let wallet = summary(previous)
        let lease = try store.fundingSigningLease(wallet: wallet)
        XCTAssertNoThrow(try lease.check(wallet: wallet))
        continuous.advance(5)
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertNil(store.walletAccountID)
        native.fails = true
        do { _ = try await store.walletRegistration(); XCTFail("Elapsed native authorization reused") }
        catch AccountAccessError.credentialUnavailable {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(native.requests.count, 2)
        XCTAssertEqual(try storage.load(), previous)
    }

    private func makeStorage() -> KeychainAccountSessionStore {
        .init(service: "test.bsmart.apple-lifecycle." + UUID().uuidString)
    }
    private func appleSession(lifetime: TimeInterval = 1800) -> TradingAccountSession {
        renewalSession(account: .init(id: UUID(), provider: .apple), lifetime: lifetime)
    }
    private func summary(_ session: TradingAccountSession) -> DeviceWalletSummary {
        .init(accountID: session.account.id, address: PreflightTestFixture.wallet.address, recoveryVerified: true)
    }
    private func assertion() -> AccountIdentityAssertion {
        .init(idToken: String(repeating: "disposable", count: 8), authorizationCode: String(repeating: "code", count: 16),
              appleUserID: "opaque-apple-user")
    }
}

private actor AppleAccountTestClient: AccountAuthenticating {
    private var session: TradingAccountSession
    private var signInRejected = false
    private var accountRejected = false
    private(set) var accountRequests: [String] = []
    private(set) var walletRequests: [String] = []
    private(set) var familyRevocations: [String] = []
    private(set) var accessRevocations: [String] = []
    init(_ session: TradingAccountSession) { self.session = session }
    func replace(_ session: TradingAccountSession) { self.session = session }
    func rejectSignIn(_ value: Bool) { signInRejected = value }
    func rejectAccount() { accountRejected = true }
    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.apple, .google], depositsEnabled: false, tradingEnabled: false)
    }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        .init(id: UUID(), nonce: String(repeating: "n", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        if signInRejected { throw AccountAccessError.expired }
        return session
    }
    func account(token: String) async throws -> TradingAccountIdentity {
        accountRequests.append(token)
        if accountRejected { throw AccountAccessError.expired }
        return session.account
    }
    func wallet(token: String) async throws -> TradingWalletRegistration {
        walletRequests.append(token)
        return .init(accountId: session.account.id, address: nil)
    }
    func refresh(token: String) async throws -> TradingAccountSession { session }
    func revokeRefresh(token: String) async throws { familyRevocations.append(token) }
    func signOut(token: String) async throws { accessRevocations.append(token) }
}
