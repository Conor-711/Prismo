import XCTest
@testable import BSmart

final class CCTPForwardJournalTests: XCTestCase {
    func testAllOutcomesSurviveRestartWithoutReleasingNonceOrDeclaringCredit() async throws {
        for mode in ["perps", "fee", "spot"] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (journal, lookup) = try await context.forwardingReady()
            let result = try await context.forwarder(mode: mode).observe(lookup, wallet: context.wallet)
            try await journal.recordForwarding(result, wallet: context.wallet)
            try await journal.recordForwarding(result, wallet: context.wallet)
            let restored = try context.journal()
            let current = try await restored.forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertEqual(current.previous, result)
            let history = try await restored.history(wallet: context.wallet)
            XCTAssertEqual(history.first?.forwardingStatus, mode == "spot" ? .spotFallback : .perpsRequested)
            XCTAssertEqual(history.first?.forwardedCoreAmount?.formatted(decimals: 8), mode == "fee" ? "8.79999999" : "9.8")
            XCTAssertEqual(history.first?.stage, .sourceExecuted)
            XCTAssertEqual(history.first?.stage.requiresReconciliation, true)
            let records = try await restored.records(wallet: context.wallet)
            XCTAssertEqual(records.first?.reservesNonce, true)
            await expectJournalFailure { try await restored.cancelReview(id: lookup.record.intent.id, wallet: context.wallet) }
        }
    }

    func testOldProofIsHiddenAndLateEvidenceCannotReplaceCurrentAttestation() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.forwardingReady()
        let first = try await context.forwarder().observe(lookup, wallet: context.wallet)
        try await journal.recordForwarding(first, wallet: context.wallet)
        let prior = try await journal.forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
        let late = try await context.forwarder().observe(prior, wallet: context.wallet)
        let attestationLookup = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        let pending = try await context.attester(.waiting).observe(attestationLookup, wallet: context.wallet)
        try await journal.recordAttestation(pending, wallet: context.wallet)
        await expectJournalFailure { try await journal.recordForwarding(late, wallet: context.wallet) }
        let history = try await journal.history(wallet: context.wallet)
        XCTAssertNil(history.first?.forwardingStatus)
        XCTAssertNil(history.first?.forwardedCoreAmount)
        XCTAssertEqual(history.first?.attestationStatus, .waiting)
        let fresh = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        let rpc = AttesterRPCStub(now: context.clock.now, overrides: ["usedNonces(bytes32)": .string(FundingQuantity(1).abi)])
        let evidence = try await context.attester(.complete(AttestationVector.load().proof(), forwardHash: ForwardVector.load().hash), rpc: rpc)
            .observe(fresh, wallet: context.wallet)
        try await journal.recordAttestation(evidence, wallet: context.wallet)
        let reopened = try await context.journal().forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(reopened.previous, first)
        do { _ = try await context.forwarder(overrides: ["receipt": .null]).observe(reopened, wallet: context.wallet); XCTFail("Erased accepted receipt") } catch {}
        do { _ = try await context.forwarder(mode: "spot").observe(reopened, wallet: context.wallet); XCTFail("Replaced accepted receipt") } catch {}
    }

    func testConcurrentQueriesForeignWalletAndForgedBindingsCannotAppend() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.forwardingReady()
        let first = try await context.forwarder().observe(lookup, wallet: context.wallet)
        let competing = try await context.forwarder().observe(lookup, wallet: context.wallet)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        for (key, value): (String, Any) in [
            ("intentID", UUID().uuidString), ("sourceObservationID", UUID().uuidString),
            ("attestationID", UUID().uuidString), ("previousID", UUID().uuidString),
            ("transactionHash", FundingQuantity(99).abi), ("nonceUsed", false), ("receiptBlock", NSNull()),
            ("observedAt", context.clock.now.addingTimeInterval(1).timeIntervalSinceReferenceDate)
        ] {
            var changed = fields; changed[key] = value
            let invalid = try JSONDecoder().decode(CCTPForwardObservation.self, from: JSONSerialization.data(withJSONObject: changed))
            await expectJournalFailure { try await journal.recordForwarding(invalid, wallet: context.wallet) }
        }
        try await journal.recordForwarding(first, wallet: context.wallet)
        await expectJournalFailure { try await journal.recordForwarding(competing, wallet: context.wallet) }
        let foreign = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        await expectJournalFailure { try await journal.recordForwarding(first, wallet: foreign) }
        await expectJournalFailure { _ = try await journal.forwardingLookup(id: lookup.record.intent.id, wallet: foreign) }
    }

    func testAllCommitFailureWindowsRecoverVerifiedForwarding() async throws {
        for phase in [FundingJournalCommitPhase.afterPendingAnchor, .beforeCommit, .afterCommit] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (_, lookup) = try await context.forwardingReady()
            let result = try await context.forwarder(mode: "fee").observe(lookup, wallet: context.wallet)
            let failing = try context.journal { if $0 == phase { throw FundingJournalError.unavailable } }
            await expectJournalFailure { try await failing.recordForwarding(result, wallet: context.wallet) }
            let restored = try context.journal()
            let before = try await restored.forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertEqual(before.previous, phase == .afterCommit ? result : nil)
            try await restored.recordForwarding(result, wallet: context.wallet)
            let after = try await restored.forwardingLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertEqual(after.previous, result)
        }
    }
}
