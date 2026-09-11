import XCTest
@testable import BSmart

@MainActor
final class AccountDeletionAccessTests: XCTestCase {
    func testPendingOrUnreadableJournalStopsRestorationLoginAndSigning() async throws {
        for unreadable in [false, true] {
            let fixture = DeletionFixture()
            let storage = RenewalMemoryStorage(fixture.session)
            let pending = DeletionMemoryStorage(try fixture.record()); pending.failsLoad = unreadable
            let client = DeletionAuthClient(fixture.session)
            let store = AccountAccessStore(client: client, storage: storage, deletionStorage: pending)
            await store.load()
            await store.signIn(.google) { _ in XCTFail("Pending deletion authorized login"); return self.assertion }
            XCTAssertNil(store.identity)
            XCTAssertNil(store.walletAccountID)
            XCTAssertEqual(client.accountReads, 0)
            XCTAssertEqual(client.signIns, 0)
            XCTAssertThrowsError(try store.fundingSigningLease(wallet: summary(fixture.session)))
            XCTAssertEqual(storage.saved, fixture.session)
        }
    }

    func testStorageReadAndClearFailuresStillInvalidateAlreadyIssuedFundingLease() async throws {
        for failRead in [true, false] {
            let fixture = DeletionFixture()
            let storage = DeletionFailingSessionStorage(fixture.session)
            let pending = DeletionMemoryStorage()
            let store = AccountAccessStore(client: DeletionAuthClient(fixture.session), storage: storage, deletionStorage: pending)
            await store.load()
            let wallet = summary(fixture.session)
            let lease = try store.fundingSigningLease(wallet: wallet)
            pending.saved = try fixture.record()
            storage.failRead = failRead; storage.failClear = !failRead
            XCTAssertThrowsError(try store.suspendForAccountDeletion(fixture.session.account))
            XCTAssertThrowsError(try lease.check(wallet: wallet))
            XCTAssertNil(store.identity)
            XCTAssertNil(store.walletAccountID)
        }
    }

    func testJournalReadFailureRevokesPriorLeaseWhenWalletAccessIsChecked() async throws {
        let fixture = DeletionFixture()
        let pending = DeletionMemoryStorage()
        let store = AccountAccessStore(client: DeletionAuthClient(fixture.session), storage: RenewalMemoryStorage(fixture.session), deletionStorage: pending)
        await store.load()
        let wallet = summary(fixture.session)
        let lease = try store.fundingSigningLease(wallet: wallet)
        pending.failsLoad = true
        XCTAssertNil(store.walletAccountID)
        XCTAssertThrowsError(try lease.check(wallet: wallet))
    }

    func testLateAccountReadCannotRestoreSuspendedIdentity() async throws {
        let fixture = DeletionFixture()
        let storage = RenewalMemoryStorage(fixture.session)
        let client = DeletionAuthClient(fixture.session)
        var continuation: CheckedContinuation<TradingAccountIdentity, Error>?
        client.onAccount = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let pending = DeletionMemoryStorage()
        let store = AccountAccessStore(client: client, storage: storage, deletionStorage: pending)
        let task = Task { await store.load() }
        for _ in 0..<1000 {
            if continuation != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let reply = try XCTUnwrap(continuation)
        pending.saved = try fixture.record()
        try store.suspendForAccountDeletion(fixture.session.account)
        reply.resume(returning: fixture.session.account)
        await task.value
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.walletAccountID)
    }

    func testDeletionReauthenticationDoesNotPersistOrPublishTemporaryCredentials() async throws {
        let fixture = DeletionFixture()
        let fresh = renewalSession(account: fixture.session.account, version: "deletion")
        let storage = RenewalMemoryStorage(fixture.session)
        let client = DeletionAuthClient(fresh)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        let wallet = summary(fixture.session)
        let lease = try store.fundingSigningLease(wallet: wallet)
        let result = try await store.reauthenticateForDeletion(expected: fixture.session.account) { _ in self.assertion }
        XCTAssertEqual(result.session, fresh)
        XCTAssertEqual(result.googleUserID, "disposable-google-id")
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.identity)
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        await store.revokeTemporaryDeletionSession(result.session)
        XCTAssertEqual(client.revokedFamilies, [fresh.refreshToken!])
    }

    func testFreshAuthRejectsWrongAccountOrMissingGoogleIDAndRevokesIssuedSession() async throws {
        let fixture = DeletionFixture()
        for sameAccount in [true, false] {
            let session = sameAccount ? fixture.session : renewalSession()
            let client = DeletionAuthClient(session)
            let authorizer = AccountDeletionReauthentication(client: client)
            do {
                _ = try await authorizer.authorize(expected: fixture.session.account) { _ in
                    .init(idToken: String(repeating: "test-identity", count: 8), authorizationCode: nil)
                }
                XCTFail()
            } catch {}
            XCTAssertEqual(client.revokedFamilies, [session.refreshToken!])
        }
    }

    func testUncertainFreshAuthAlsoClearsOldSessionAndStopsNewSigningPermissions() async throws {
        let fixture = DeletionFixture()
        let storage = RenewalMemoryStorage(fixture.session)
        let client = DeletionAuthClient(fixture.session)
        client.onSignIn = { throw URLError(.networkConnectionLost) }
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        let wallet = summary(fixture.session)
        let lease = try store.fundingSigningLease(wallet: wallet)
        do {
            _ = try await store.reauthenticateForDeletion(expected: fixture.session.account) { _ in self.assertion }
            XCTFail()
        } catch {}
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertThrowsError(try store.fundingSigningLease(wallet: wallet))
    }

    func testCancellationAfterFreshAuthCleansUpAndAppleMustBeCurrentlyAuthorized() async throws {
        let fixture = DeletionFixture()
        let client = DeletionAuthClient(fixture.session)
        client.onSignIn = { withUnsafeCurrentTask { $0?.cancel() }; return fixture.session }
        let task = Task {
            try await AccountDeletionReauthentication(client: client).authorize(expected: fixture.session.account) { _ in self.assertion }
        }
        do { _ = try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail() }
        XCTAssertEqual(client.revokedFamilies, [fixture.session.refreshToken!])
        let apple = DeletionFixture(provider: .apple)
        let appleClient = DeletionAuthClient(apple.session)
        let check = DeletionAppleCheck()
        let reauth = AccountDeletionReauthentication(client: appleClient, apple: check)
        do {
            _ = try await reauth.authorize(expected: apple.session.account) { _ in
                .init(idToken: String(repeating: "apple-test", count: 8), authorizationCode: String(repeating: "test-code", count: 8), appleUserID: "original-apple")
            }
            XCTFail()
        } catch {}
        XCTAssertEqual(check.users, ["original-apple"])
        XCTAssertEqual(appleClient.revokedFamilies, [apple.session.refreshToken!])
    }

    private var assertion: AccountIdentityAssertion {
        .init(idToken: String(repeating: "test-identity", count: 8), authorizationCode: nil, googleUserID: "disposable-google-id")
    }
    private func summary(_ session: TradingAccountSession) -> DeviceWalletSummary {
        .init(accountID: session.account.id, address: PreflightTestFixture.wallet.address, recoveryVerified: true)
    }
}

@MainActor
private final class DeletionAppleCheck: AppleCredentialStateChecking {
    var users: [String?] = []
    func check(userID: String?) async throws -> AppleCredentialStatus { users.append(userID); return .revoked }
}

@MainActor
final class DeletionAuthClient: AccountAuthenticating {
    let session: TradingAccountSession
    var accountReads = 0
    var signIns = 0
    var revokedFamilies: [String] = []
    var onAccount: (() async throws -> TradingAccountIdentity)?
    var onSignIn: (() async throws -> TradingAccountSession)?
    init(_ session: TradingAccountSession) { self.session = session }
    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.google, .apple], depositsEnabled: false, tradingEnabled: false)
    }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        .init(id: UUID(), nonce: String(repeating: "n", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        signIns += 1
        if let onSignIn { return try await onSignIn() }
        return session
    }
    func reauthenticate(account: TradingAccountIdentity, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        try await signIn(provider: account.provider, challenge: challenge, assertion: assertion)
    }
    func account(token: String) async throws -> TradingAccountIdentity {
        accountReads += 1
        if let onAccount { return try await onAccount() }
        return session.account
    }
    func wallet(token: String) async throws -> TradingWalletRegistration { .init(accountId: session.account.id, address: nil) }
    func signOut(token: String) async throws {}
    func revokeRefresh(token: String) async throws { revokedFamilies.append(token) }
}

private final class DeletionFailingSessionStorage: AccountSessionPersisting {
    var saved: TradingAccountSession?
    var failRead = false
    var failClear = false
    init(_ session: TradingAccountSession) { saved = session }
    func load() throws -> TradingAccountSession? { if failRead { throw AccountAccessError.storage }; return saved }
    func save(_ session: TradingAccountSession) throws { saved = session }
    func clear() throws { if failClear { throw AccountAccessError.storage }; saved = nil }
}
