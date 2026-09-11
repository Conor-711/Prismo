import XCTest
@testable import BSmart

final class FundingJournalRecoveryTests: XCTestCase {
    func testInterruptionsOnEitherSideOfSQLiteCommitRecoverExactlyOnce() async throws {
        for phase in [FundingJournalCommitPhase.afterPendingAnchor, .beforeCommit, .afterCommit] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            _ = try await journal.records(wallet: context.wallet)
            let transaction = try await context.transaction()
            let id = UUID()
            let failing = try context.journal { if $0 == phase { throw FundingJournalError.unavailable } }
            await expectJournalFailure { try await failing.reserve(id: id, transaction: transaction, wallet: context.wallet) }
            let recovered = try await journal.records(wallet: context.wallet)
            XCTAssertEqual(recovered.count, phase == .afterCommit ? 1 : 0)
            let anchor = try JSONDecoder().decode(FundingJournalAnchor.self, from: XCTUnwrap(context.keychain.data))
            XCTAssertNil(anchor.pending)
            XCTAssertEqual(anchor.committed.sequence, phase == .afterCommit ? 1 : 0)
            _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
            let repeated = try await journal.records(wallet: context.wallet)
            XCTAssertEqual(repeated.count, 1)
        }
    }

    func testKeychainFinalizationFailureKeepsCommittedIntentAndPendingAnchor() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        context.keychain.failFinalization()
        await expectJournalFailure { try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet) }
        let unfinished = try JSONDecoder().decode(FundingJournalAnchor.self, from: XCTUnwrap(context.keychain.data))
        XCTAssertEqual(unfinished.committed.sequence, 0)
        XCTAssertEqual(unfinished.pending?.sequence, 1)
        let recovered = try await context.journal().records(wallet: context.wallet)
        XCTAssertEqual(recovered.map(\.intent.id), [id])
        let finished = try JSONDecoder().decode(FundingJournalAnchor.self, from: XCTUnwrap(context.keychain.data))
        XCTAssertEqual(finished.committed.sequence, 1)
        XCTAssertNil(finished.pending)
    }

    func testCommittedSubmissionWithNoReturnedPermitStillRequiresReconciliation() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try await context.ready(transaction, id: id, journal: journal)
        let failing = try context.journal { if $0 == .afterCommit { throw FundingJournalError.unavailable } }
        await expectJournalFailure { try await failing.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        let recovered = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(recovered.first?.state, .submitting)
        XCTAssertEqual(recovered.first?.signed?.hash, signed.hash)
        await expectJournalFailure { try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
    }

    func testDatabaseRollbackTruncationAndCiphertextCorruptionAreRejected() async throws {
        for mutation in ["rollback", "truncate", "ciphertext"] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            let id = UUID()
            _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
            let old = try Data(contentsOf: context.database)
            _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
            switch mutation {
            case "rollback": try old.write(to: context.database)
            case "truncate": try context.mutateDatabase("DELETE FROM journal_events WHERE sequence = 2")
            default: try context.mutateDatabase("UPDATE journal_events SET sealed = zeroblob(length(sealed)) WHERE sequence = 1")
            }
            let before = try Data(contentsOf: context.database)
            await expectJournalFailure { try await context.journal().records(wallet: context.wallet) }
            XCTAssertEqual(try Data(contentsOf: context.database), before)
        }
    }

    func testMissingDatabaseOrKeyAndLockedKeychainNeverCreateAnEmptyHistory() async throws {
        for failure in ["database", "key", "locked"] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            _ = try await journal.reserve(id: UUID(), transaction: transaction, wallet: context.wallet)
            switch failure {
            case "database": try FileManager.default.removeItem(at: context.database)
            case "key": context.keychain.forget()
            default: context.keychain.setLocked()
            }
            await expectJournalFailure { try await context.journal().records(wallet: context.wallet) }
            if failure == "database" { XCTAssertFalse(FileManager.default.fileExists(atPath: context.database.path)) }
            if failure == "key" { XCTAssertNil(context.keychain.data) }
        }
    }

    func testCopiedDatabaseFromAnotherDeviceJournalCannotBeOpened() async throws {
        let first = FundingJournalTestContext(); defer { first.cleanup() }
        let second = FundingJournalTestContext(); defer { second.cleanup() }
        let transaction = try await first.transaction()
        _ = try await first.journal().reserve(id: UUID(), transaction: transaction, wallet: first.wallet)
        _ = try await second.journal().records(wallet: second.wallet)
        try Data(contentsOf: first.database).write(to: second.database)
        await expectJournalFailure { try await second.journal().records(wallet: second.wallet) }
    }

    func testConcurrentJournalInstancesCannotReserveTwoDeposits() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let first = try context.journal()
        let second = try context.journal()
        _ = try await first.records(wallet: context.wallet)
        let transaction = try await context.transaction()
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for journal in [first, second] {
                group.addTask {
                    do { _ = try await journal.reserve(id: UUID(), transaction: transaction, wallet: context.wallet); return true }
                    catch { return false }
                }
            }
            var count = 0
            for await success in group { count += success ? 1 : 0 }
            return count
        }
        XCTAssertEqual(successes, 1)
        let records = try await first.records(wallet: context.wallet)
        XCTAssertEqual(records.count, 1)
    }

    func testSymlinkDatabaseIsNotFollowedOrOverwritten() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        _ = try await journal.records(wallet: context.wallet)
        let target = context.directory.appendingPathComponent("unrelated.txt")
        let contents = Data("Do not overwrite".utf8)
        try contents.write(to: target)
        try FileManager.default.removeItem(at: context.database)
        try FileManager.default.createSymbolicLink(at: context.database, withDestinationURL: target)
        await expectJournalFailure { try await journal.records(wallet: context.wallet) }
        XCTAssertEqual(try Data(contentsOf: target), contents)
    }

    func testCancellationAfterCommitNeverReturnsAPermitOrReleasesNonce() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try await context.ready(transaction, id: id, journal: journal)
        let cancelled = try context.journal { phase in
            if phase == .afterCommit { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let attempt = Task { try await cancelled.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        switch await attempt.result {
        case .success: XCTFail("A cancelled task must not obtain submission bytes")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        let records = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .submitting)
        XCTAssertTrue(records.first?.reservesNonce == true)
    }
}
