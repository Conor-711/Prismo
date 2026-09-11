import XCTest
@testable import BSmart

final class FundingHistoryTests: XCTestCase {
    func testOneEntryFollowsConsentSourceAndSubmissionWithoutClaimingCredit() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        try await check(.reviewAuthorization, journal: journal, context: context, id: id)
        _ = try await journal.beginAuthorization(id: id, wallet: context.wallet)
        try await check(.authorizationStarted, journal: journal, context: context, id: id)
        _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        try await check(.authorizationRecorded, journal: journal, context: context, id: id)
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        try await check(.reviewNetworkFee, journal: journal, context: context, id: id)
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        try await check(.signingStarted, journal: journal, context: context, id: id)
        let signed = try context.signed(transaction)
        _ = try await journal.acceptSignature(id: id, signed: signed, wallet: context.wallet)
        try await check(.signatureRecorded, journal: journal, context: context, id: id, hash: signed.hash)
        _ = try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed))
        try await check(.submissionStarted, journal: journal, context: context, id: id, hash: signed.hash)
        _ = try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: nil)
        try await check(.submissionUnknown, journal: journal, context: context, id: id, hash: signed.hash)
        _ = try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: signed.hash)
        context.clock.advance(3600)
        try await check(.nodeAcknowledged, journal: context.journal(), context: context, id: id, hash: signed.hash)
        await expectJournalFailure { try await journal.cancelReview(id: id, wallet: context.wallet) }
    }

    func testBothUnsignedReviewsCanBeCancelledAfterRestartAndExpiry() async throws {
        for hasSource in [false, true] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            let id = UUID()
            _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
            if hasSource {
                _ = try await journal.beginAuthorization(id: id, wallet: context.wallet)
                _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
                _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
            }
            context.clock.advance(3600)
            try await context.journal().cancelReview(id: id, wallet: context.wallet)
            try await check(.cancelled, journal: context.journal(), context: context, id: id)
            try await journal.cancelReview(id: id, wallet: context.wallet)
            let fresh = try await context.transaction(authorizationNonce: 18)
            _ = try await journal.beginConsent(id: UUID(), plan: fresh.preflight.plan, wallet: context.wallet)
            let history = try await journal.history(wallet: context.wallet)
            XCTAssertEqual(history.count, 2)
        }
    }

    func testStaleReviewCannotCancelAfterAnAuthorizationOrSigningPermitEscapes() async throws {
        for hasSource in [false, true] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            let id = UUID()
            if hasSource {
                _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
            } else {
                _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
            }
            let history = try await journal.history(wallet: context.wallet)
            XCTAssertTrue(try XCTUnwrap(history.first).stage.canCancelReview)
            if hasSource { _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet) }
            else { _ = try await journal.beginAuthorization(id: id, wallet: context.wallet) }
            await expectJournalFailure { try await journal.cancelReview(id: id, wallet: context.wallet) }
            let current = try await journal.history(wallet: context.wallet)
            XCTAssertTrue(try XCTUnwrap(current.first).stage.requiresReconciliation)
        }
    }

    func testHistoryAndCancellationAreAccountAndOwnerScoped() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        for other in [DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true),
                      DeviceWalletSummary(accountID: context.wallet.accountID, address: "0x" + String(repeating: "ab", count: 20), recoveryVerified: true)] {
            let history = try await journal.history(wallet: other)
            XCTAssertTrue(history.isEmpty)
            await expectJournalFailure { try await journal.cancelReview(id: id, wallet: other) }
        }
        try await check(.reviewAuthorization, journal: journal, context: context, id: id)
    }

    func testMissingOrCorruptHistoryDoesNotBecomeAnEmptyList() async throws {
        for failure in ["deleted", "locked", "tampered"] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            _ = try await journal.beginConsent(id: UUID(), plan: transaction.preflight.plan, wallet: context.wallet)
            switch failure {
            case "deleted": try FileManager.default.removeItem(at: context.database)
            case "locked": context.keychain.setLocked()
            default: try context.mutateDatabase("UPDATE journal_events SET sealed = zeroblob(length(sealed))")
            }
            await expectJournalFailure { try await journal.history(wallet: context.wallet) }
        }
    }

    func testInterruptedCancellationReopensTheExactCommittedState() async throws {
        for phase in [FundingJournalCommitPhase.beforeCommit, .afterCommit] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            let id = UUID()
            _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
            let interrupted = try context.journal { if $0 == phase { throw FundingJournalError.unavailable } }
            await expectJournalFailure { try await interrupted.cancelReview(id: id, wallet: context.wallet) }
            try await check(phase == .afterCommit ? .cancelled : .reviewAuthorization,
                            journal: context.journal(), context: context, id: id)
        }
    }

    private func check(_ stage: FundingHistoryEntry.Stage, journal: FundingTransactionJournal,
                       context: FundingJournalTestContext, id: UUID, hash: String? = nil) async throws {
        let entries = try await journal.history(wallet: context.wallet)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.stage, stage)
        XCTAssertEqual(entry.amountUnits, 10_000_000)
        XCTAssertEqual(entry.transactionHash, hash)
        if hash != nil {
            XCTAssertTrue(entry.stage.requiresReconciliation)
            XCTAssertFalse(entry.stage.canCancelReview)
        }
    }
}
