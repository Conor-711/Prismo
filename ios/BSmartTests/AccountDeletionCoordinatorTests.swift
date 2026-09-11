import XCTest
@testable import BSmart

@MainActor
final class AccountDeletionCoordinatorTests: XCTestCase {
    func testDurableSubmissionPrecedesIOAndRelaunchQueriesSameTicketWithBackoff() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        let cleanup = DeletionTestCleanup()
        var now = fixture.now
        client.onRequest = {
            XCTAssertEqual(storage.saved?.stage, .submitted)
            XCTAssertEqual(cleanup.suspensions, [fixture.session.account])
            return try fixture.receipt()
        }
        let store = deletionCoordinator(fixture, storage: storage, client: client, cleanup: cleanup, now: { now })
        try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true)
        XCTAssertEqual(storage.saved?.stage, .accepted)
        let google = DeletionTestGoogle()
        let restarted = deletionCoordinator(fixture, storage: storage, client: client, cleanup: cleanup, google: google, now: { now })
        try await restarted.resume()
        XCTAssertTrue(client.queries.isEmpty)
        now = now.addingTimeInterval(30)
        try await restarted.resume()
        XCTAssertEqual(client.requests.map(\.ticket), [fixture.ticket])
        XCTAssertEqual(client.queries, [fixture.ticket])
        XCTAssertEqual(google.users, ["disposable-google-id"])
        XCTAssertEqual(cleanup.removals, [fixture.session.account])
        XCTAssertEqual(storage.saved?.stage, .completed)
        try restarted.acknowledgeOrDiscardPrepared(ticket: fixture.ticket)
        XCTAssertNil(storage.saved)
    }

    func testAppleAndUnlinkedWalletCanCompleteWithoutGoogleDisconnect() async throws {
        let fixture = DeletionFixture(provider: .apple)
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        client.requestResult = .success(try fixture.receipt(completed: true))
        let google = DeletionTestGoogle()
        let store = deletionCoordinator(fixture, storage: storage, client: client, google: google)
        try await store.submit(fixture.record(wallet: false), session: fixture.session, confirmed: true, recoveryConfirmed: true)
        XCTAssertEqual(storage.saved?.stage, .completed)
        XCTAssertNil(storage.saved?.walletAddress)
        XCTAssertTrue(google.users.isEmpty)
    }

    func testAllConfirmationsAndIdentityAreRequiredBeforePersistence() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        let store = deletionCoordinator(fixture, storage: storage, client: client)
        for (confirmed, recovery) in [(false, false), (false, true), (true, false)] {
            do { try await store.submit(fixture.record(), session: fixture.session, confirmed: confirmed, recoveryConfirmed: recovery); XCTFail() }
            catch { XCTAssertEqual(error as? AccountDeletionError, .confirmationRequired) }
        }
        do { try await store.submit(fixture.record(), session: renewalSession(), confirmed: true, recoveryConfirmed: true); XCTFail() }
        catch { XCTAssertEqual(error as? AccountDeletionError, .accountChanged) }
        XCTAssertNil(storage.saved)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testFailedReadOrWriteCannotSendOrReplaceTicket() async throws {
        let fixture = DeletionFixture()
        for stage in [AccountDeletionRecord.Stage.prepared, .submitted] {
            let storage = DeletionMemoryStorage(); storage.rejectsStage = stage
            let client = try DeletionTestClient(fixture)
            let store = deletionCoordinator(fixture, storage: storage, client: client)
            do { try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true); XCTFail() } catch {}
            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertEqual(storage.saved?.stage, stage == .submitted ? .prepared : nil)
        }
        let storage = DeletionMemoryStorage(try fixture.record()); storage.failsLoad = true
        let client = try DeletionTestClient(fixture)
        let store = deletionCoordinator(fixture, storage: storage, client: client)
        XCTAssertEqual(store.error, .storage)
        do { try await store.resume(); XCTFail() } catch {}
        XCTAssertEqual(storage.saved?.ticket, fixture.ticket)
        XCTAssertTrue(client.queries.isEmpty)
    }

    func testSuspensionFailureLeavesDiscardableUnsentRecord() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        let cleanup = DeletionTestCleanup(); cleanup.failSuspend = true
        let store = deletionCoordinator(fixture, storage: storage, client: client, cleanup: cleanup)
        do { try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true); XCTFail() } catch {}
        XCTAssertEqual(storage.saved?.stage, .prepared)
        XCTAssertTrue(client.requests.isEmpty)
        try store.acknowledgeOrDiscardPrepared(ticket: fixture.ticket)
        XCTAssertNil(storage.saved)
    }

    func testNetworkFailureAndMissingStatusRemainUncertainWithoutAutomaticRetry() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        client.requestResult = .failure(URLError(.networkConnectionLost))
        let store = deletionCoordinator(fixture, storage: storage, client: client)
        do { try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true); XCTFail() } catch {}
        XCTAssertEqual(storage.saved?.stage, .submitted)
        XCTAssertThrowsError(try store.acknowledgeOrDiscardPrepared(ticket: fixture.ticket))
        client.statusResult = .failure(AccountDeletionError.requestNotFound)
        let restarted = deletionCoordinator(fixture, storage: storage, client: client)
        do { try await restarted.resume(); XCTFail() } catch {}
        XCTAssertEqual(restarted.error, .requestNotFound)
        XCTAssertEqual(storage.saved?.stage, .submitted)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.queries, [fixture.ticket])
    }

    func testExplicitRetryQueriesFirstAndUsesSameRequestOnlyAfter404() async throws {
        let fixture = DeletionFixture()
        var record = try fixture.record(); try record.willSubmit()
        let storage = DeletionMemoryStorage(record)
        let client = try DeletionTestClient(fixture)
        let store = deletionCoordinator(fixture, storage: storage, client: client)
        client.statusResult = .failure(URLError(.timedOut))
        do { try await store.retryUnconfirmed(session: fixture.session, googleUserID: record.googleUserID, confirmed: true); XCTFail() } catch {}
        XCTAssertTrue(client.requests.isEmpty)
        client.statusResult = .failure(AccountDeletionError.requestNotFound)
        try await store.retryUnconfirmed(session: fixture.session, googleUserID: record.googleUserID, confirmed: true)
        XCTAssertEqual(client.requests.map(\.ticket), [fixture.ticket])
        XCTAssertEqual(storage.saved?.stage, .accepted)
        do { try await store.retryUnconfirmed(session: fixture.session, googleUserID: record.googleUserID, confirmed: true); XCTFail() } catch {}
        XCTAssertEqual(client.requests.count, 1)
    }

    func testExplicitRetryWithKnownReceiptDoesNotResend() async throws {
        let fixture = DeletionFixture()
        var record = try fixture.record(); try record.willSubmit()
        let storage = DeletionMemoryStorage(record)
        let client = try DeletionTestClient(fixture)
        let store = deletionCoordinator(fixture, storage: storage, client: client)
        do { try await store.retryUnconfirmed(session: fixture.session, googleUserID: "wrong", confirmed: true); XCTFail() } catch {}
        XCTAssertTrue(client.queries.isEmpty)
        try await store.retryUnconfirmed(session: fixture.session, googleUserID: record.googleUserID, confirmed: true)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(storage.saved?.stage, .completed)
    }

    func testCancellationAfterServerReceiptPersistsBeforeAnyLocalDestruction() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        let cleanup = DeletionTestCleanup()
        client.onRequest = {
            withUnsafeCurrentTask { $0?.cancel() }
            return try fixture.receipt(completed: true)
        }
        let store = deletionCoordinator(fixture, storage: storage, client: client, cleanup: cleanup)
        let task = Task { try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true) }
        do { try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail() }
        XCTAssertEqual(storage.saved?.stage, .serverCompleted)
        XCTAssertTrue(cleanup.removals.isEmpty)
        try await store.resume()
        XCTAssertEqual(storage.saved?.stage, .completed)
        XCTAssertTrue(client.queries.isEmpty)
    }

    func testGoogleFailureStillErasesLocalProfileButDoesNotClaimComplete() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage()
        let client = try DeletionTestClient(fixture)
        client.requestResult = .success(try fixture.receipt(completed: true))
        let google = DeletionTestGoogle(); google.failure = AccountDeletionError.providerDisconnectRequired
        let cleanup = DeletionTestCleanup()
        let store = deletionCoordinator(fixture, storage: storage, client: client, cleanup: cleanup, google: google)
        do { try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true); XCTFail() } catch {}
        XCTAssertEqual(cleanup.removals, [fixture.session.account])
        XCTAssertEqual(storage.saved?.stage, .serverCompleted)
        XCTAssertFalse(storage.saved!.providerDisconnected)
        google.failure = nil
        try await store.resume()
        XCTAssertEqual(storage.saved?.stage, .completed)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.queries.isEmpty)
    }

    func testCompletionWriteFailureRetriesCleanupWithoutRepeatedDisconnect() async throws {
        let fixture = DeletionFixture()
        let storage = DeletionMemoryStorage(); storage.rejectsStage = .completed
        let client = try DeletionTestClient(fixture)
        client.requestResult = .success(try fixture.receipt(completed: true))
        let google = DeletionTestGoogle()
        let store = deletionCoordinator(fixture, storage: storage, client: client, google: google)
        do { try await store.submit(fixture.record(), session: fixture.session, confirmed: true, recoveryConfirmed: true); XCTFail() } catch {}
        XCTAssertEqual(storage.saved?.stage, .serverCompleted)
        XCTAssertTrue(storage.saved!.providerDisconnected)
        storage.rejectsStage = nil
        try await store.resume()
        XCTAssertEqual(google.users.count, 1)
        XCTAssertEqual(storage.saved?.stage, .completed)
    }

    func testWrongOriginAndWrongReceiptCannotChangeSavedRequest() async throws {
        let fixture = DeletionFixture()
        var record = try fixture.record(); try record.willSubmit()
        let storage = DeletionMemoryStorage(record)
        let client = try DeletionTestClient(fixture)
        client.statusResult = .success(try fixture.receipt(completed: true, id: UUID()))
        let store = deletionCoordinator(fixture, storage: storage, client: client)
        do { try await store.resume(); XCTFail() } catch {}
        XCTAssertEqual(storage.saved, record)
        let wrong = AccountDeletionCoordinator(client: client, storage: storage, cleanup: DeletionTestCleanup(),
            google: DeletionTestGoogle(), endpoint: URL(string: "https://other.example.invalid")!)
        do { try await wrong.resume(); XCTFail() } catch {}
        XCTAssertEqual(client.queries.count, 1)
        XCTAssertEqual(storage.saved, record)
    }
}
