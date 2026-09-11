import XCTest
@testable import BSmart

final class FundingJournalSignatureTests: XCTestCase {
    func testLateSignatureIsArchivedWithoutRenewingSubmissionPermission() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        let signed = try context.signed(transaction)
        context.clock.advance(600)
        let archived = try await journal.recordSignature(id: id, signature: signed.signature, wallet: context.wallet)
        XCTAssertEqual(archived.state, .signed)
        XCTAssertEqual(archived.signed?.raw, signed.raw)
        XCTAssertEqual(archived.signed?.hash, signed.hash)
        XCTAssertEqual(archived.intent.expiresAt, transaction.preflight.expiresAt)
        let repeated = try await journal.acceptSignature(id: id, signed: signed, wallet: context.wallet)
        XCTAssertEqual(repeated, archived)
        await expectJournalFailure { try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed)) }
        await expectJournalFailure { try await journal.cancelPrepared(id: id, wallet: context.wallet) }
        let reopened = try context.journal()
        let history = try await reopened.records(wallet: context.wallet)
        XCTAssertEqual(history, [archived])
        let next = try await context.transaction(authorizationNonce: 18)
        await expectJournalFailure { try await reopened.reserve(id: UUID(), transaction: next, wallet: context.wallet) }
    }

    func testSignatureArchiveRequiresTheExactReservedIntentAndOwner() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try context.signed(transaction)
        await expectJournalFailure { try await journal.recordSignature(id: id, signature: signed.signature, wallet: context.wallet) }
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        await expectJournalFailure { try await journal.recordSignature(id: id, signature: signed.signature, wallet: context.wallet) }
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        await expectJournalFailure { try await journal.recordSignature(id: id, signature: signed.signature, wallet: other) }
        let changed = try await context.transaction(nonce: "0x7")
        let changedSignature = try context.signed(changed).signature
        await expectJournalFailure { try await journal.recordSignature(id: id, signature: changedSignature, wallet: context.wallet) }
        await expectJournalFailure { try await journal.recordSignature(id: id, signature: Data(count: 65), wallet: context.wallet) }
        let history = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(history.first?.state, .signing)
        XCTAssertNil(history.first?.signed)
        let accepted = try await journal.recordSignature(id: id, signature: signed.signature, wallet: context.wallet)
        XCTAssertEqual(accepted.signed?.raw, signed.raw)
        await expectJournalFailure { try await journal.recordSignature(id: id, signature: changedSignature, wallet: context.wallet) }
    }

    func testCancelledTaskStillPersistsAlreadyCreatedSignatureAndNodeAcknowledgement() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        let signed = try context.signed(transaction)
        let signingCallback = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.recordSignature(id: id, signature: signed.signature, wallet: context.wallet)
        }
        let recorded = try await signingCallback.value
        XCTAssertEqual(recorded.state, .signed)
        _ = try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: context.recordedSubmissionCheck(signed))
        let submissionCallback = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.recordSubmissionResult(id: id, wallet: context.wallet, reportedHash: signed.hash)
        }
        let accepted = try await submissionCallback.value
        XCTAssertEqual(accepted.state, .submitted)
        let history = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(history, [accepted])
        XCTAssertTrue(accepted.needsReconciliation)
    }

    func testInvalidSignatureDoesNotLeakPreflightNoPaymentAssurance() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        _ = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        do {
            _ = try await journal.recordSignature(id: id, signature: Data(count: 65), wallet: context.wallet)
            XCTFail("Invalid signature was accepted")
        } catch { XCTAssertEqual(error as? FundingJournalError, .unavailable) }
        let history = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(history.first?.state, .signing)
    }
}
