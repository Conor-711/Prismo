import XCTest
import Security
@testable import BSmart

final class FundingTransactionJournalTests: XCTestCase {
    func testNeverSubmittedSourceRetainsSignatureButCannotIssuePermitAndAllowsFreshAuthorization() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(), id = UUID()
        let signed = try await context.readyWithConsent(context.transaction(), id: id, journal: journal)
        let check = try await context.recordedSubmissionCheck(signed)
        let finished = try await journal.finishUnsubmittedSource(id: id, wallet: context.wallet)
        XCTAssertTrue(finished)
        let reopened = try context.journal()
        let sources = try await reopened.records(wallet: context.wallet)
        let source = try XCTUnwrap(sources.first)
        XCTAssertEqual(source.state, .notSubmitted)
        XCTAssertEqual(source.signed?.raw, signed.raw)
        XCTAssertEqual(source.signed?.hash, signed.hash)
        XCTAssertFalse(source.reservesNonce)
        await expectJournalFailure { try await reopened.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: check) }
        await expectJournalFailure { try await reopened.reserve(id: UUID(), transaction: signed.transaction, wallet: context.wallet) }
        let next = try await context.transaction(authorizationNonce: 18)
        _ = try await reopened.beginConsent(id: UUID(), plan: next.preflight.plan, wallet: context.wallet)
        let history = try await reopened.history(wallet: context.wallet)
        XCTAssertEqual(history.first(where: { $0.id == id })?.stage, .notSubmitted)
    }

    func testSubmissionPermitAndUnknownResultCanNeverBeReleasedAsUnsubmitted() async throws {
        for state in [FundingJournalRecord.State.submitting, .submitted, .uncertain] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal(), id = UUID()
            let signed = try await context.readyWithConsent(context.transaction(), id: id, journal: journal)
            _ = try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed))
            if state != .submitting {
                _ = try await journal.recordSubmissionResult(id: id, wallet: context.wallet,
                    reportedHash: state == .submitted ? signed.hash : nil)
            }
            let finished = try await journal.finishUnsubmittedSource(id: id, wallet: context.wallet)
            XCTAssertFalse(finished)
            let sources = try await context.journal().records(wallet: context.wallet)
            XCTAssertEqual(sources.first?.state, state)
            XCTAssertEqual(sources.first?.reservesNonce, true)
        }
    }

    func testDurableIntentSignatureAndUnknownSubmissionSurviveReopenAndExpiry() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try await context.ready(transaction, id: id, journal: journal)
        let permit = try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed))
        XCTAssertEqual(permit.owner, context.wallet.address)
        XCTAssertEqual(permit.hash, signed.hash)
        XCTAssertEqual(permit.chainID, 42161)
        _ = try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: nil)
        context.clock.advance(400)
        let records = try await context.journal().records(wallet: context.wallet)
        let stored = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(stored.state, .uncertain)
        XCTAssertEqual(stored.signed?.raw, signed.raw)
        XCTAssertEqual(stored.signed?.hash, signed.hash)
        XCTAssertEqual(stored.intent.callData, transaction.preflight.callData)
        XCTAssertTrue(stored.reservesNonce)
        XCTAssertTrue(stored.needsReconciliation)
        await expectJournalFailure { try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        await expectJournalFailure { try await journal.cancelPrepared(id: id, wallet: context.wallet) }
    }

    func testReservationIsIdempotentAndSigningLocksTheNonceAcrossInstances() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let first = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        let again = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        XCTAssertEqual(first, again)
        let permit = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        XCTAssertEqual(permit.signingHash, transaction.signingHash)
        XCTAssertEqual(permit.owner, context.wallet.address)
        let reopened = try context.journal()
        let records = try await reopened.records(wallet: context.wallet)
        XCTAssertEqual(records.map(\.state), [.signing])
        XCTAssertNil(records.first?.signed)
        XCTAssertTrue(records.first?.needsReconciliation == true)
        await expectJournalFailure { try await reopened.reserve(id: UUID(), transaction: transaction, wallet: context.wallet) }
        await expectJournalFailure { try await reopened.beginSigning(id: id, transaction: transaction, wallet: context.wallet) }
        await expectJournalFailure { try await reopened.cancelPrepared(id: id, wallet: context.wallet) }
    }

    func testOnlyPreparedIntentCanBeCancelledAndAuthorizationCannotBeReused() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        let cancelled = try await journal.cancelPrepared(id: id, wallet: context.wallet)
        XCTAssertFalse(cancelled.reservesNonce)
        await expectJournalFailure { try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet) }
        await expectJournalFailure { try await journal.reserve(id: UUID(), transaction: transaction, wallet: context.wallet) }
        let replacement = try await context.transaction(authorizationNonce: 18)
        let prepared = try await journal.reserve(id: UUID(), transaction: replacement, wallet: context.wallet)
        XCTAssertEqual(prepared.state, .prepared)
        XCTAssertEqual(prepared.intent.nonce, cancelled.intent.nonce)
        XCTAssertNotEqual(prepared.intent.authorizationNonce, cancelled.intent.authorizationNonce)
    }

    func testStagesCannotBeSkippedAndOnlyOneSubmissionPermitIsIssued() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let signed = try context.signed(transaction)
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        await expectJournalFailure { try await journal.acceptSignature(id: id, signed: signed, wallet: context.wallet) }
        await expectJournalFailure { try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        _ = try await journal.acceptSignature(id: id, signed: signed, wallet: context.wallet)
        await expectJournalFailure { try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: signed.hash) }
        _ = try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed))
        await expectJournalFailure { try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        let accepted = try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: signed.hash)
        let before = context.keychain.data
        let duplicate = try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: signed.hash)
        XCTAssertEqual(accepted, duplicate)
        XCTAssertEqual(context.keychain.data, before)
        XCTAssertEqual(accepted.state, .submitted)
        XCTAssertTrue(accepted.needsReconciliation) // A node acknowledgement is not a receipt or credit.
    }

    func testWrongNodeHashRemainsUncertainAndCannotReplaceLocalHash() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try await context.ready(transaction, id: id, journal: journal)
        _ = try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed))
        let response = try await journal.recordSubmissionResult(id: id, wallet: context.wallet,
                                                               reportedHash: "0x" + String(repeating: "1", count: 64))
        XCTAssertEqual(response.state, .uncertain)
        XCTAssertEqual(response.signed?.hash, signed.hash)
        let accepted = try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: signed.hash)
        XCTAssertEqual(accepted.state, .submitted)
        XCTAssertTrue(accepted.reservesNonce)
    }

    func testIdentityAndPayloadChangesCannotUseTheReservation() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let changed = try await context.transaction(nonce: "0x7")
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        await expectJournalFailure { try await journal.reserve(id: id, transaction: changed, wallet: context.wallet) }
        await expectJournalFailure { try await journal.beginSigning(id: id, transaction: changed, wallet: context.wallet) }
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        let hidden = try await journal.records(wallet: other)
        XCTAssertTrue(hidden.isEmpty)
        await expectJournalFailure { try await journal.beginSigning(id: id, transaction: transaction, wallet: other) }
        await expectJournalFailure { try await journal.cancelPrepared(id: id, wallet: other) }
    }

    func testLedgerIsEncryptedExcludedFromBackupAndDeviceOnly() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let signed = try await context.ready(transaction, id: UUID(), journal: journal)
        let data = try Data(contentsOf: context.database)
        for secret in [Data(context.wallet.address.utf8), transaction.preflight.callData, signed.raw,
                       Data("signingHash".utf8), Data("accountID".utf8)] {
            XCTAssertNil(data.range(of: secret))
        }
        let file = try FileManager.default.attributesOfItem(atPath: context.database.path)
        let directory = try FileManager.default.attributesOfItem(atPath: context.directory.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertTrue(try context.database.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        XCTAssertEqual(context.keychain.addAttributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String)
        XCTAssertEqual(context.keychain.addAttributes[kSecAttrSynchronizable as String] as? Bool, false)
    }

    func testExpiryDuringCommitCannotReturnSubmissionBytes() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try await context.ready(transaction, id: id, journal: journal)
        let delayed = try context.journal { phase in if phase == .afterCommit { context.clock.advance(30) } }
        await expectJournalFailure { try await delayed.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        let records = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .submitting)
        XCTAssertTrue(records.first?.reservesNonce == true)
    }
}
