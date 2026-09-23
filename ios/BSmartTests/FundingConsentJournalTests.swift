import XCTest
@testable import BSmart

final class FundingConsentJournalTests: XCTestCase {
    func testUnsubmittedAuthorizationRetainsEvidenceReleasesOwnerAndCannotBeRevived() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(), transaction = try await context.transaction(), id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        _ = try await journal.beginAuthorization(id: id, wallet: context.wallet)
        let inFlight = try await journal.finishUnsubmittedAuthorization(id: id, wallet: context.wallet)
        XCTAssertFalse(inFlight)
        _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        let finished = try await journal.finishUnsubmittedAuthorization(id: id, wallet: context.wallet)
        XCTAssertTrue(finished)
        let reopened = try context.journal()
        let records = try await reopened.consents(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .notSubmitted)
        XCTAssertEqual(records.first?.signature, transaction.preflight.authorization)
        await expectJournalFailure { try await reopened.reserve(id: id, transaction: transaction, wallet: context.wallet) }
        await expectJournalFailure { try await reopened.beginAuthorization(id: id, wallet: context.wallet) }
        await expectJournalFailure { try await reopened.beginConsent(id: UUID(), plan: transaction.preflight.plan, wallet: context.wallet) }
        let next = try await context.transaction(authorizationNonce: 18)
        _ = try await reopened.beginConsent(id: UUID(), plan: next.preflight.plan, wallet: context.wallet)
    }

    func testUnsubmittedRecoveryCannotReleaseSourceTransactions() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(), transaction = try await context.transaction(), id = UUID()
        _ = try await context.readyWithConsent(transaction, id: id, journal: journal)
        let before = try await journal.records(wallet: context.wallet)
        let finished = try await journal.finishUnsubmittedAuthorization(id: id, wallet: context.wallet)
        XCTAssertFalse(finished)
        let after = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(before, after)
        let next = try await context.transaction(authorizationNonce: 18)
        await expectJournalFailure { try await journal.beginConsent(id: UUID(), plan: next.preflight.plan, wallet: context.wallet) }
    }

    func testOrphanAuthorizationExpiresOnlyAfterChainTimeAndRetainsSignature() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(), transaction = try await context.transaction(), id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        _ = try await journal.beginAuthorization(id: id, wallet: context.wallet)
        _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        try await journal.expireAuthorizations(wallet: context.wallet, source: transaction.preflight.source)
        var records = try await journal.consents(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .authorized)
        context.clock.advance(301)
        let next = try await context.transaction(authorizationNonce: 18)
        try await journal.expireAuthorizations(wallet: context.wallet, source: next.preflight.source)
        records = try await context.journal().consents(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .expired)
        XCTAssertEqual(records.first?.signature, transaction.preflight.authorization)
        _ = try await journal.beginConsent(id: UUID(), plan: next.preflight.plan, wallet: context.wallet)
    }

    func testRecoveryNeverExpiresAuthorizationLinkedToSignedTransaction() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(), transaction = try await context.transaction(), id = UUID()
        _ = try await context.readyWithConsent(transaction, id: id, journal: journal)
        context.clock.advance(301)
        let next = try await context.transaction(authorizationNonce: 18)
        try await journal.expireAuthorizations(wallet: context.wallet, source: next.preflight.source)
        let records = try await journal.consents(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .authorized)
        await expectJournalFailure { try await journal.beginConsent(id: UUID(), plan: next.preflight.plan, wallet: context.wallet) }
    }

    func testConsentAndAuthorizationLinkAtomicallyToTheExactSourceIntent() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let plan = transaction.preflight.plan
        let id = UUID()
        let review = try await journal.beginConsent(id: id, plan: plan, wallet: context.wallet)
        let repeated = try await journal.beginConsent(id: id, plan: plan, wallet: context.wallet)
        XCTAssertEqual(review, repeated)
        let permit = try await journal.beginAuthorization(id: id, wallet: context.wallet)
        XCTAssertEqual(permit.id, id)
        XCTAssertEqual(permit.authorizationHash, review.plan.authorizationHash)
        _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        let sourcePermit = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        XCTAssertTrue(sourcePermit.hasRecordedConsent)
        let reopened = try context.journal()
        let consents = try await reopened.consents(wallet: context.wallet)
        let sources = try await reopened.records(wallet: context.wallet)
        XCTAssertEqual(consents.first?.state, .authorized)
        XCTAssertEqual(sources.first?.state, .signing)
        XCTAssertEqual(sources.first?.intent.id, consents.first?.id)
    }

    func testConsentReservesOwnerAgainstOtherConsentsAndSourceOnlyBypass() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        let other = try await context.transaction(authorizationNonce: 18)
        await expectJournalFailure { try await journal.beginConsent(id: UUID(), plan: other.preflight.plan, wallet: context.wallet) }
        await expectJournalFailure { try await journal.reserve(id: UUID(), transaction: other, wallet: context.wallet) }
        await expectJournalFailure { try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet) }
        _ = try await journal.cancelConsent(id: id, wallet: context.wallet)
        await expectJournalFailure { try await journal.beginConsent(id: UUID(), plan: transaction.preflight.plan, wallet: context.wallet) }
        _ = try await journal.beginConsent(id: UUID(), plan: other.preflight.plan, wallet: context.wallet)
    }

    func testSourceReservationPreventsCreatingAnotherConsent() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
        let next = try await context.transaction(authorizationNonce: 18)
        await expectJournalFailure { try await journal.beginConsent(id: id, plan: next.preflight.plan, wallet: context.wallet) }
        await expectJournalFailure { try await journal.beginConsent(id: UUID(), plan: next.preflight.plan, wallet: context.wallet) }
        let permit = try await journal.beginSigning(id: id, transaction: transaction, wallet: context.wallet)
        XCTAssertFalse(permit.hasRecordedConsent)
    }

    func testLinkedSourceCannotSubstitutePlanSignatureOrAccount() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let changed = try await context.transaction(authorizationNonce: 18)
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        _ = try await journal.beginAuthorization(id: id, wallet: context.wallet)
        await expectJournalFailure { try await journal.recordAuthorization(id: id, signature: changed.preflight.authorization, wallet: context.wallet) }
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        let hidden = try await journal.consents(wallet: other)
        XCTAssertTrue(hidden.isEmpty)
        await expectJournalFailure { try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: other) }
        _ = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        await expectJournalFailure { try await journal.reserve(id: id, transaction: changed, wallet: context.wallet) }
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)
    }

    func testAuthorizationSurvivesExpiryAndCancelledCallbackWithoutAnotherPermit() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        _ = try await journal.beginAuthorization(id: id, wallet: context.wallet)
        context.clock.advance(600)
        let callback = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        }
        let saved = try await callback.value
        XCTAssertEqual(saved.state, .authorized)
        let repeated = try await journal.recordAuthorization(id: id, signature: transaction.preflight.authorization, wallet: context.wallet)
        XCTAssertEqual(repeated, saved)
        await expectJournalFailure { try await journal.beginAuthorization(id: id, wallet: context.wallet) }
        await expectJournalFailure { try await journal.cancelConsent(id: id, wallet: context.wallet) }
        await expectJournalFailure { try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet) }
        let history = try await context.journal().consents(wallet: context.wallet)
        XCTAssertEqual(history, [saved])
    }

    func testAuthorizationPermitCannotEscapeFailedCommit() async throws {
        for phase in [FundingJournalCommitPhase.afterPendingAnchor, .beforeCommit, .afterCommit] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal()
            let transaction = try await context.transaction()
            let id = UUID()
            _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
            let interrupted = try context.journal { if $0 == phase { throw FundingJournalError.unavailable } }
            await expectJournalFailure { try await interrupted.beginAuthorization(id: id, wallet: context.wallet) }
            let restored = try await journal.consents(wallet: context.wallet)
            XCTAssertEqual(restored.first?.state, phase == .afterCommit ? .authorizing : .review)
            if phase == .afterCommit {
                await expectJournalFailure { try await journal.beginAuthorization(id: id, wallet: context.wallet) }
            } else { _ = try await journal.beginAuthorization(id: id, wallet: context.wallet) }
        }
    }

    func testExpiredConsentCannotEnterAuthorization() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: transaction.preflight.plan, wallet: context.wallet)
        context.clock.advance(60)
        await expectJournalFailure { try await journal.beginAuthorization(id: id, wallet: context.wallet) }
        let history = try await journal.consents(wallet: context.wallet)
        XCTAssertEqual(history.first?.state, .review)
        _ = try await journal.cancelConsent(id: id, wallet: context.wallet)
    }

    func testLegacySourceRecordDecodesWithoutDiscardingItsHistory() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let old = FundingJournalRecord(intent: .init(id: UUID(), transaction: transaction), state: .prepared,
                                       signed: nil, updatedAt: context.clock.now)
        let data = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(FundingJournalEvent.self, from: data)
        var snapshot = FundingJournalSnapshot()
        try snapshot.apply(decoded)
        XCTAssertEqual(snapshot.sources[old.intent.id], old)
        XCTAssertTrue(snapshot.consents.isEmpty)
    }
}
