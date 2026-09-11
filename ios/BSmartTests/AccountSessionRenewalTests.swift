import XCTest
@testable import BSmart

@MainActor
final class AccountSessionRenewalTests: XCTestCase {
    func testConcurrentRenewalsShareOneRequestAndJournalPrecedesIO() async throws {
        let previous = renewalSession()
        let replacement = renewalSession(account: previous.account, version: "replacement")
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(replacement, suspend: true)
        let renewal = AccountSessionRenewal(client: client, storage: storage)
        let first = Task { try await renewal.renew(previous) }
        try await client.waitForRequest()
        XCTAssertTrue(storage.pending)
        XCTAssertEqual(storage.saved, previous)
        let second = Task { try await renewal.renew(previous) }
        await client.finish()
        let results = try await [first.value, second.value]
        XCTAssertEqual(results, [replacement, replacement])
        XCTAssertEqual(storage.saved, replacement)
        XCTAssertFalse(storage.pending)
        XCTAssertEqual(storage.begins, 1)
        let requests = await client.refreshes
        XCTAssertEqual(requests, [previous.refreshToken!])
    }

    func testLostResponseIsNeverRetriedAndLeavesDurablePendingState() async throws {
        let previous = renewalSession()
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(renewalSession(account: previous.account, version: "replacement"), suspend: true)
        let renewal = AccountSessionRenewal(client: client, storage: storage)
        let task = Task { try await renewal.renew(previous) }
        try await client.waitForRequest()
        await client.finish(failing: true)
        do { _ = try await task.value; XCTFail("Lost response accepted") } catch {}
        for _ in 0..<2 {
            do { _ = try await renewal.renew(previous); XCTFail("Uncertain refresh retried") } catch {}
        }
        XCTAssertTrue(storage.pending)
        XCTAssertEqual(storage.saved, previous)
        let requests = await client.refreshes
        XCTAssertEqual(requests.count, 1)
    }

    func testNoRequestIfJournalCannotBePersisted() async {
        let previous = renewalSession()
        let storage = RenewalMemoryStorage(previous)
        storage.rejectsBegin = true
        let client = RenewalTestClient(renewalSession(account: previous.account, version: "replacement"))
        let renewal = AccountSessionRenewal(client: client, storage: storage)
        do { _ = try await renewal.renew(previous); XCTFail("Missing journal accepted") } catch {}
        let requests = await client.refreshes
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(storage.pending)
    }

    func testStorageFailureRevokesReturnedAccessAndRetainsPendingOriginal() async {
        let previous = renewalSession()
        let replacement = renewalSession(account: previous.account, version: "replacement")
        let storage = RenewalMemoryStorage(previous)
        storage.rejectsSave = true
        let client = RenewalTestClient(replacement)
        let renewal = AccountSessionRenewal(client: client, storage: storage)
        do { _ = try await renewal.renew(previous); XCTFail("Unstored credentials accepted") } catch {}
        XCTAssertEqual(storage.saved, previous)
        XCTAssertTrue(storage.pending)
        let revoked = await client.accessRevocations
        XCTAssertEqual(revoked, [replacement.accessToken])
    }

    func testCancelledRenewalCannotOverwriteFreshLoginEvenIfResponseArrivesLate() async throws {
        let previous = renewalSession()
        let replacement = renewalSession(account: previous.account, version: "replacement")
        let storage = RenewalMemoryStorage(previous)
        let client = RenewalTestClient(replacement, suspend: true)
        let renewal = AccountSessionRenewal(client: client, storage: storage)
        let task = Task { try await renewal.renew(previous) }
        try await client.waitForRequest()
        renewal.cancel()
        let fresh = renewalSession(version: "interactive")
        try storage.save(fresh)
        await client.finish()
        do { _ = try await task.value; XCTFail("Cancelled renewal accepted") } catch {}
        XCTAssertEqual(storage.saved, fresh)
        XCTAssertFalse(storage.pending)
        let revoked = await client.accessRevocations
        XCTAssertEqual(revoked, [replacement.accessToken])
    }

    func testRenewalRejectsIdentityChangesReplayAndMalformedLifetimes() async {
        let previous = renewalSession()
        let valid = renewalSession(account: previous.account, version: "replacement")
        let invalid = [renewalSession(version: "wrong-account"), previous,
            TradingAccountSession(account: previous.account, accessToken: valid.accessToken, expiresAt: valid.expiresAt),
            .init(account: previous.account, accessToken: valid.accessToken, expiresAt: valid.expiresAt,
                  refreshToken: previous.refreshToken, refreshExpiresAt: valid.refreshExpiresAt),
            .init(account: previous.account, accessToken: valid.accessToken, expiresAt: .distantPast,
                  refreshToken: valid.refreshToken, refreshExpiresAt: valid.refreshExpiresAt),
            .init(account: previous.account, accessToken: valid.accessToken, expiresAt: .distantFuture,
                  refreshToken: valid.refreshToken, refreshExpiresAt: .distantFuture)]
        for value in invalid {
            let storage = RenewalMemoryStorage(previous)
            let client = RenewalTestClient(value)
            let renewal = AccountSessionRenewal(client: client, storage: storage)
            do { _ = try await renewal.renew(previous); XCTFail("Invalid session accepted") } catch {}
            XCTAssertEqual(storage.saved, previous)
            XCTAssertTrue(storage.pending)
        }
    }

    func testPendingEnvelopeAndLegacySessionDecodeWithoutLeakingCredentials() throws {
        let session = renewalSession()
        let encoder = BSmartJSONCoding.makeEncoder()
        let legacy = try AccountSessionEnvelope.decode(encoder.encode(session))
        XCTAssertEqual(legacy.session.accessToken, session.accessToken)
        XCTAssertFalse(legacy.renewalPending)
        let pending = try AccountSessionEnvelope.decode(encoder.encode(AccountSessionEnvelope(session: session, renewalPending: true)))
        XCTAssertEqual(pending.session.refreshToken, session.refreshToken)
        XCTAssertTrue(pending.renewalPending)
        XCTAssertThrowsError(try AccountSessionEnvelope.decode(Data("{\"version\":3}".utf8)))
        XCTAssertThrowsError(try AccountSessionEnvelope.decode(Data("{\"version\":2}".utf8)))
        XCTAssertEqual(String(describing: session), "TradingAccountSession(redacted)")
        XCTAssertEqual(String(reflecting: session), "TradingAccountSession(redacted)")
    }

    func testDeviceKeychainRecordsPendingAndAcceptsOnlyMatchingCurrentSession() throws {
        let service = "test.bsmart.renewal." + UUID().uuidString
        let storage = KeychainAccountSessionStore(service: service)
        defer { try? storage.clear() }
        let previous = renewalSession()
        try storage.save(previous)
        XCTAssertThrowsError(try storage.beginRenewal(renewalSession()))
        XCTAssertFalse(try storage.isRenewalPending())
        try storage.beginRenewal(previous)
        let restored = KeychainAccountSessionStore(service: service)
        XCTAssertTrue(try restored.isRenewalPending())
        XCTAssertThrowsError(try restored.beginRenewal(previous))
        let replacement = renewalSession(account: previous.account, version: "replacement")
        try restored.save(replacement)
        XCTAssertFalse(try storage.isRenewalPending())
        XCTAssertEqual(try storage.load()?.refreshToken, replacement.refreshToken)
        try storage.clear()
        XCTAssertNil(try restored.load())
    }
}
