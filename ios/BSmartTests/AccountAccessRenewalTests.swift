import XCTest
@testable import BSmart

@MainActor
final class AccountAccessRenewalTests: XCTestCase {
    func testExpiredAccessRestoresThroughRefreshAndVerifiesNewAccountToken() async {
        let previous = renewalSession(lifetime: -1)
        let replacement = renewalSession(account: previous.account, version: "replacement")
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(replacement)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertEqual(store.walletAccountID, previous.account.id)
        XCTAssertEqual(storage.saved, replacement)
        XCTAssertFalse(storage.pending)
        let requests = await client.accountRequests
        XCTAssertEqual(requests, [replacement.accessToken])
        XCTAssertNil(store.errorMessage)
    }

    func testActiveAccessDoesNotRotateOnRestore() async {
        let previous = renewalSession()
        let client = RenewalTestClient(previous)
        let storage = RenewalMemoryStorage(previous)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertEqual(storage.begins, 0)
        let requests = await client.refreshes
        XCTAssertTrue(requests.isEmpty)
    }

    func testCrashDuringRenewalRequiresInteractiveLoginAndRevokesUncertainFamily() async {
        let previous = renewalSession()
        let storage = RenewalMemoryStorage(previous)
        storage.pending = true
        let client = RenewalTestClient(previous)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        XCTAssertNil(store.identity)
        XCTAssertNil(store.walletAccountID)
        XCTAssertNil(storage.saved)
        XCTAssertNotNil(store.errorMessage)
        let requests = await client.refreshes
        let revoked = await client.familyRevocations
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(revoked, [previous.refreshToken!])
    }

    func testLogoutUsesRefreshCredentialEvenWhenAccessHasExpired() async {
        let previous = renewalSession(lifetime: -1)
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(previous)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.signOut()
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.identity)
        let revoked = await client.familyRevocations
        let accessRevoked = await client.accessRevocations
        XCTAssertEqual(revoked, [previous.refreshToken!])
        XCTAssertTrue(accessRevoked.isEmpty)
    }

    func testFailedLogoutRetainsCredentialsAndReportsFailure() async {
        let previous = renewalSession()
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(previous, failRevocation: true)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        await store.signOut()
        XCTAssertEqual(storage.saved, previous)
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertNotNil(store.errorMessage)
    }

    func testInvalidSignInReceiptIsNeverPersistedAndServerSessionIsRevoked() async {
        let invalid = renewalSession(lifetime: 7200)
        let storage = RenewalMemoryStorage()
        let client = RenewalTestClient(invalid)
        let store = AccountAccessStore(client: client, storage: storage)
        await store.load()
        await store.signIn(.google) { _ in
            .init(idToken: String(repeating: "disposable", count: 8), authorizationCode: nil)
        }
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.identity)
        XCTAssertNotNil(store.errorMessage)
        let revoked = await client.accessRevocations
        XCTAssertEqual(revoked, [invalid.accessToken])
    }

    func testRenewalInvalidatesFundingLeaseAndBlocksNewSigningUntilFinished() async throws {
        var now = Date()
        let previous = renewalSession(lifetime: 90)
        let replacement = renewalSession(account: previous.account, version: "replacement")
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(replacement, suspend: true)
        let store = AccountAccessStore(client: client, storage: storage, now: { now })
        await store.load()
        let wallet = DeviceWalletSummary(accountID: previous.account.id,
            address: PreflightTestFixture.wallet.address, recoveryVerified: true)
        let lease = try store.fundingSigningLease(wallet: wallet)
        XCTAssertNoThrow(try lease.check(wallet: wallet))
        now = now.addingTimeInterval(40)
        let query = Task { try await store.walletRegistration() }
        try await client.waitForRequest()
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertThrowsError(try store.fundingSigningLease(wallet: wallet))
        await client.finish()
        let registration = try await query.value
        XCTAssertEqual(registration.accountId, previous.account.id)
        XCTAssertEqual(store.walletAccountID, previous.account.id)
        let walletRequests = await client.walletRequests
        XCTAssertEqual(walletRequests, [replacement.accessToken])
        XCTAssertNoThrow(try store.fundingSigningLease(wallet: wallet))
    }

    func testLogoutDuringRenewalDoesNotRestoreLateIdentityOrCredentials() async throws {
        var now = Date()
        let previous = renewalSession(lifetime: 90)
        let replacement = renewalSession(account: previous.account, version: "replacement")
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(replacement, suspend: true)
        let store = AccountAccessStore(client: client, storage: storage, now: { now })
        await store.load()
        now = now.addingTimeInterval(40)
        let query = Task { try await store.walletRegistration() }
        try await client.waitForRequest()
        await store.signOut()
        await client.finish()
        do { _ = try await query.value; XCTFail("Late renewal restored logout") } catch {}
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
        let revoked = await client.familyRevocations
        let cleanup = await client.accessRevocations
        XCTAssertEqual(revoked, [previous.refreshToken!])
        XCTAssertEqual(cleanup, [replacement.accessToken])
    }
}
