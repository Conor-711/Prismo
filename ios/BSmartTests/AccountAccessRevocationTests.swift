import XCTest
@testable import BSmart

@MainActor
final class AccountAccessRevocationTests: XCTestCase {
    func testWalletReadProofAndBindingRevocationClearSessionAndInvalidateFunding() async throws {
        for operation in [RevocationOperation.wallet, .proof, .binding] {
            let original = renewalSession()
            let storage = RenewalMemoryStorage(original)
            let client = RevocationTestClient(original)
            let store = AccountAccessStore(client: client, storage: storage)
            await store.load()
            let wallet = summary(original)
            let lease = try store.fundingSigningLease(wallet: wallet)
            let challenge = try await store.walletChallenge(address: wallet.address)
            await client.reject(operation, error: .expired)
            do {
                switch operation {
                case .wallet: _ = try await store.walletRegistration()
                case .proof: _ = try await store.walletChallenge(address: wallet.address)
                case .binding: _ = try await store.bindWallet(challenge: challenge, signature: "disposable-test-proof")
                default: XCTFail("Unexpected test operation")
                }
                XCTFail("Revoked session accepted")
            } catch AccountAccessError.expired {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertNil(storage.saved)
            XCTAssertNil(store.identity)
            XCTAssertNil(store.walletAccountID)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertThrowsError(try lease.check(wallet: wallet))
            XCTAssertThrowsError(try store.fundingSigningLease(wallet: wallet))
        }
    }

    func testForegroundRevocationClearsSavedCredentialButAnOutageDoesNotEraseIt() async {
        for revoked in [true, false] {
            let original = renewalSession()
            let storage = RenewalMemoryStorage(original)
            let client = RevocationTestClient(original)
            await client.reject(.account, error: revoked ? .expired : .unavailable)
            let store = AccountAccessStore(client: client, storage: storage)
            await store.load()
            XCTAssertNil(store.identity)
            XCTAssertNil(store.walletAccountID)
            XCTAssertEqual(storage.saved, revoked ? nil : original)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testWalletOutageDoesNotMasqueradeAsProviderRevocation() async throws {
        let original = renewalSession()
        let storage = RenewalMemoryStorage(original)
        let client = RevocationTestClient(original)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        await client.reject(.wallet, error: .unavailable)
        do { _ = try await store.walletRegistration(); XCTFail("Outage accepted") }
        catch AccountAccessError.unavailable {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(storage.saved, original)
        XCTAssertEqual(store.identity, original.account)
        XCTAssertNil(store.errorMessage)
    }

    func testLateOldResponseCannotClearNewLoginOrItsFundingLease() async throws {
        for sameAccount in [true, false] {
            for rejected in [true, false] {
                let original = renewalSession()
                let next = renewalSession(account: sameAccount ? original.account : .init(id: UUID(), provider: .google),
                                          version: "replacement")
                let storage = RenewalMemoryStorage(original)
                let client = RevocationTestClient(original)
                let store = AccountAccessStore(client: client, storage: storage)
                await store.load()
                await client.suspend(.wallet)
                let oldRequest = Task { try await store.walletRegistration() }
                try await client.waitFor(.wallet)
                await client.replaceSession(next)
                await store.signIn(.google) { _ in
                    .init(idToken: String(repeating: "disposable", count: 8), authorizationCode: nil)
                }
                let wallet = summary(next)
                let lease = try store.fundingSigningLease(wallet: wallet)
                await client.finish(.wallet, error: rejected ? .expired : nil)
                do { _ = try await oldRequest.value; XCTFail("Late response accepted for new identity") } catch {}
                XCTAssertEqual(storage.saved, next)
                XCTAssertEqual(store.identity, next.account)
                XCTAssertNil(store.errorMessage)
                XCTAssertNoThrow(try lease.check(wallet: wallet))
            }
        }
    }

    func testRevocationDuringRenewalDiscardsLateReplacementAndStopsFunding() async throws {
        var now = Date()
        let original = renewalSession(lifetime: 90)
        let next = renewalSession(account: original.account, version: "replacement")
        let storage = RenewalMemoryStorage(original)
        let client = RevocationTestClient(original)
        let store = AccountAccessStore(client: client, storage: storage, now: { now })
        await store.load()
        await client.suspend(.wallet)
        let oldRequest = Task { try await store.walletRegistration() }
        try await client.waitFor(.wallet)
        await client.replaceSession(next)
        await client.suspend(.refresh)
        now = now.addingTimeInterval(40)
        let renewingRequest = Task { try await store.walletRegistration() }
        try await client.waitFor(.refresh)
        XCTAssertTrue(storage.pending)
        await client.finish(.wallet, error: .expired)
        do { _ = try await oldRequest.value; XCTFail("Revoked read accepted") } catch {}
        await client.finish(.refresh, error: nil)
        do { _ = try await renewingRequest.value; XCTFail("Late renewal restored revoked access") } catch {}
        XCTAssertNil(storage.saved)
        XCTAssertFalse(storage.pending)
        XCTAssertNil(store.identity)
        XCTAssertThrowsError(try store.fundingSigningLease(wallet: summary(next)))
        let cleanups = await client.accessRevocations
        XCTAssertEqual(cleanups, [next.accessToken])
    }

    func testStorageCleanupFailureStillStopsCurrentFundingAccess() async throws {
        let original = renewalSession()
        let storage = RevocationFailingStorage(original)
        let client = RevocationTestClient(original)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        let wallet = summary(original)
        let lease = try store.fundingSigningLease(wallet: wallet)
        await client.reject(.wallet, error: .expired)
        do { _ = try await store.walletRegistration(); XCTFail("Revoked read accepted") } catch {}
        XCTAssertNil(store.identity)
        XCTAssertNil(store.walletAccountID)
        XCTAssertEqual(store.errorMessage, AccountAccessError.storage.localizedDescription)
        XCTAssertThrowsError(try lease.check(wallet: wallet))
    }

    func testForegroundCleanupFailureReportsStorageErrorWithoutRestoringIdentity() async {
        let original = renewalSession()
        let client = RevocationTestClient(original)
        await client.reject(.account, error: .expired)
        let store = AccountAccessStore(client: client, storage: RevocationFailingStorage(original))
        await store.load()
        XCTAssertNil(store.identity)
        XCTAssertNil(store.walletAccountID)
        XCTAssertEqual(store.errorMessage, AccountAccessError.storage.localizedDescription)
    }

    private func summary(_ session: TradingAccountSession) -> DeviceWalletSummary {
        .init(accountID: session.account.id, address: PreflightTestFixture.wallet.address, recoveryVerified: true)
    }
}

private enum RevocationOperation: Hashable { case account, wallet, proof, binding, refresh }

private actor RevocationTestClient: AccountAuthenticating {
    private var session: TradingAccountSession
    private var failures: [RevocationOperation: AccountAccessError] = [:]
    private var suspended: Set<RevocationOperation> = []
    private var pending: [RevocationOperation: CheckedContinuation<Void, Error>] = [:]
    private(set) var accessRevocations: [String] = []
    init(_ session: TradingAccountSession) { self.session = session }
    func replaceSession(_ next: TradingAccountSession) { session = next }
    func reject(_ operation: RevocationOperation, error: AccountAccessError) { failures[operation] = error }
    func suspend(_ operation: RevocationOperation) { suspended.insert(operation) }
    func waitFor(_ operation: RevocationOperation) async throws {
        for _ in 0..<1000 {
            if pending[operation] != nil { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AccountAccessError.unavailable
    }
    func finish(_ operation: RevocationOperation, error: AccountAccessError?) {
        guard let continuation = pending.removeValue(forKey: operation) else { XCTFail("No pending request"); return }
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
    private func perform(_ operation: RevocationOperation) async throws {
        if let error = failures[operation] { throw error }
        if suspended.contains(operation) {
            try await withCheckedThrowingContinuation { pending[operation] = $0 }
        }
    }
    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.google, .apple], depositsEnabled: false, tradingEnabled: false)
    }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        .init(id: UUID(), nonce: String(repeating: "n", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func signIn(provider: AccountIdentityProvider, challenge: UUID,
                assertion: AccountIdentityAssertion) async throws -> TradingAccountSession { session }
    func account(token: String) async throws -> TradingAccountIdentity {
        let result = session.account
        try await perform(.account)
        return result
    }
    func wallet(token: String) async throws -> TradingWalletRegistration {
        let result = TradingWalletRegistration(accountId: session.account.id, address: nil)
        try await perform(.wallet)
        return result
    }
    func walletChallenge(address: String, token: String) async throws -> TradingWalletChallenge {
        try await perform(.proof)
        let issued = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return .init(id: UUID(), accountId: session.account.id, address: address, nonce: String(repeating: "a", count: 64),
                     issuedAt: issued, expiresAt: issued.addingTimeInterval(300))
    }
    func bindWallet(challenge: UUID, signature: String, token: String) async throws -> TradingWalletRegistration {
        try await perform(.binding)
        return .init(accountId: session.account.id, address: PreflightTestFixture.wallet.address)
    }
    func refresh(token: String) async throws -> TradingAccountSession {
        let result = session
        try await perform(.refresh)
        return result
    }
    func signOut(token: String) async throws { accessRevocations.append(token) }
}

private final class RevocationFailingStorage: AccountSessionPersisting {
    private let saved: TradingAccountSession
    init(_ session: TradingAccountSession) { saved = session }
    func load() throws -> TradingAccountSession? { saved }
    func save(_ session: TradingAccountSession) throws { throw AccountAccessError.storage }
    func clear() throws { throw AccountAccessError.storage }
}
