import XCTest
@testable import BSmart

final class CCTPAttestationJournalTests: XCTestCase {
    func testVerifiedEvidencePersistsReplaysAndNeverReleasesOwnerOrCreditsBalance() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let proof = try AttestationVector.load().proof()
        let result = try await context.attester(.complete(proof, forwardHash: FundingQuantity(99).abi)).observe(lookup, wallet: context.wallet)
        try await journal.recordAttestation(result, wallet: context.wallet)
        try await journal.recordAttestation(result, wallet: context.wallet)
        let restored = try context.journal()
        let archived = try await restored.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(archived.previous, result)
        let history = try await restored.history(wallet: context.wallet)
        XCTAssertEqual(history.first?.stage, .sourceExecuted)
        XCTAssertEqual(history.first?.attestationStatus, .verified)
        XCTAssertEqual(history.first?.attestedTransferFee, FundingQuantity(200_000))
        XCTAssertEqual(history.first?.stage.requiresReconciliation, true)
        let sources = try await restored.records(wallet: context.wallet)
        XCTAssertTrue(try XCTUnwrap(sources.first).reservesNonce)
        do { try await restored.cancelReview(id: lookup.record.intent.id, wallet: context.wallet); XCTFail("Cancelled signed payment") }
        catch { XCTAssertEqual(error as? FundingJournalError, .invalidTransition) }
    }

    func testNewSourceHidesOldAttestationAndRejectsLateCompletion() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let proof = try AttestationVector.load().proof()
        let attester = context.attester(.complete(proof, forwardHash: nil))
        let first = try await attester.observe(lookup, wallet: context.wallet)
        try await journal.recordAttestation(first, wallet: context.wallet)
        let prior = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        let late = try await attester.observe(prior, wallet: context.wallet)
        let sourceLookup = try await journal.sourceLookup(id: lookup.record.intent.id, wallet: context.wallet)
        let fixture = FundingObservationFixture(record: lookup.record, now: context.clock.now)
        let source = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(sourceLookup, wallet: context.wallet)
        try await journal.recordSourceObservation(source, wallet: context.wallet)
        do { try await journal.recordAttestation(late, wallet: context.wallet); XCTFail("Overwrote newer source") }
        catch { XCTAssertEqual(error as? FundingJournalError, .conflict) }
        let history = try await journal.history(wallet: context.wallet)
        XCTAssertNil(history.first?.attestationStatus)
        let fresh = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(fresh.previous, first)
        let pending = try await context.attester(.waiting).observe(fresh, wallet: context.wallet)
        try await journal.recordAttestation(pending, wallet: context.wallet)
        let nextHistory = try await journal.history(wallet: context.wallet)
        XCTAssertEqual(nextHistory.first?.attestationStatus, .waiting)
        XCTAssertNil(nextHistory.first?.attestedTransferFee)
    }

    func testLateCompetingQueriesCannotOverwriteAndForeignWalletCannotReadOrWrite() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let first = try await context.attester(.waiting).observe(lookup, wallet: context.wallet)
        let competing = try await context.attester(.waiting).observe(lookup, wallet: context.wallet)
        try await journal.recordAttestation(first, wallet: context.wallet)
        do { try await journal.recordAttestation(competing, wallet: context.wallet); XCTFail("Stale append") }
        catch { XCTAssertEqual(error as? FundingJournalError, .conflict) }
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        do { _ = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: other); XCTFail("Foreign read") }
        catch { XCTAssertEqual(error as? FundingJournalError, .conflict) }
        do { try await journal.recordAttestation(first, wallet: other); XCTFail("Foreign write") }
        catch { XCTAssertEqual(error as? FundingJournalError, .conflict) }
    }

    func testExpiredPausedAndAlreadyProcessedEvidenceDoesNotDeclareCredit() async throws {
        for (overrides, status): ([String: FundingRPCValue], FundingHistoryEntry.AttestationStatus) in [
            (["before": FundingObservationFixture.block(1000, time: Date(timeIntervalSince1970: 1_770_000_120)),
              "after": FundingObservationFixture.block(1000, time: Date(timeIntervalSince1970: 1_770_000_120))], .expired),
            (["paused()": .string(FundingQuantity(1).abi)], .paused),
            (["usedNonces(bytes32)": .string(FundingQuantity(1).abi)], .processed)
        ] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (journal, lookup) = try await context.attestationReady()
            let rpc = AttesterRPCStub(now: context.clock.now, overrides: overrides)
            let result = try await context.attester(.complete(AttestationVector.load().proof(), forwardHash: nil), rpc: rpc)
                .observe(lookup, wallet: context.wallet)
            try await journal.recordAttestation(result, wallet: context.wallet)
            let history = try await journal.history(wallet: context.wallet)
            XCTAssertEqual(history.first?.attestationStatus, status)
            XCTAssertEqual(history.first?.stage, .sourceExecuted)
            XCTAssertEqual(history.first?.stage.requiresReconciliation, true)
        }
    }

    func testAttestationRecoversAcrossEachCommitFailure() async throws {
        for phase in [FundingJournalCommitPhase.afterPendingAnchor, .beforeCommit, .afterCommit] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (_, lookup) = try await context.attestationReady()
            let result = try await context.attester(.complete(AttestationVector.load().proof(), forwardHash: nil))
                .observe(lookup, wallet: context.wallet)
            let failing = try context.journal { current in if current == phase { throw FundingJournalError.unavailable } }
            await expectJournalFailure { try await failing.recordAttestation(result, wallet: context.wallet) }
            let recovered = try context.journal()
            let stored = try await recovered.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertEqual(stored.previous, phase == .afterCommit ? result : nil)
            try await recovered.recordAttestation(result, wallet: context.wallet)
            let final = try await recovered.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
            XCTAssertEqual(final.previous, result)
        }
    }

    func testForgedBindingsFutureDateAndIncompleteProofFailClosed() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let result = try await context.attester(.complete(AttestationVector.load().proof(), forwardHash: nil))
            .observe(lookup, wallet: context.wallet)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        for (field, replacement): (String, Any) in [
            ("intentID", UUID().uuidString), ("sourceObservationID", UUID().uuidString),
            ("previousID", UUID().uuidString), ("observedAt", context.clock.now.addingTimeInterval(1).timeIntervalSinceReferenceDate),
            ("verifier", NSNull()), ("proof", NSNull()), ("forwardHash", "0x1234")
        ] {
            var altered = fields; altered[field] = replacement
            let invalid = try JSONDecoder().decode(CCTPAttestationObservation.self, from: JSONSerialization.data(withJSONObject: altered))
            await expectJournalFailure { try await journal.recordAttestation(invalid, wallet: context.wallet) }
        }
        let stored = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertNil(stored.previous)
    }

    func testDestinationCannotRegressOrUnconsumeNonceEvenAfterPendingResponse() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (journal, lookup) = try await context.attestationReady()
        let proof = try AttestationVector.load().proof()
        let result = try await context.attester(.complete(proof, forwardHash: nil), rpc:
            AttesterRPCStub(now: context.clock.now, overrides: ["usedNonces(bytes32)": .string(FundingQuantity(1).abi)]))
            .observe(lookup, wallet: context.wallet)
        try await journal.recordAttestation(result, wallet: context.wallet)
        let prior = try await journal.attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        let pending = try await context.attester(.waiting).observe(prior, wallet: context.wallet)
        try await journal.recordAttestation(pending, wallet: context.wallet)
        let current = try await context.journal().attestationLookup(id: lookup.record.intent.id, wallet: context.wallet)
        XCTAssertEqual(current.previousVerified, result)
        for overrides: [String: FundingRPCValue] in [
            [:],
            ["before": FundingObservationFixture.block(501, time: context.clock.now),
             "after": FundingObservationFixture.block(501, time: context.clock.now)],
            ["before": FundingObservationFixture.block(499, time: context.clock.now),
             "after": FundingObservationFixture.block(499, time: context.clock.now),
             "usedNonces(bytes32)": .string(FundingQuantity(1).abi)],
            ["before": FundingObservationFixture.block(500, time: context.clock.now, reorg: true),
             "after": FundingObservationFixture.block(500, time: context.clock.now, reorg: true),
             "usedNonces(bytes32)": .string(FundingQuantity(1).abi)]
        ] {
            let rpc = AttesterRPCStub(now: context.clock.now, overrides: overrides)
            do { _ = try await context.attester(.complete(proof, forwardHash: nil), rpc: rpc).observe(current, wallet: context.wallet); XCTFail("Regressed destination") }
            catch { XCTAssertEqual(error as? FundingObservationError, .unavailable) }
        }
    }

    func testSourceMismatchAndStaleSourceRejectedBeforeDestinationQuery() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.attestationReady()
        var message = try AttestationVector.load().proof().message; message[431] ^= 1
        let rpc = AttesterRPCStub(now: context.clock.now)
        let attester = context.attester(.complete(try AttestationVector.sign(message), forwardHash: nil), rpc: rpc)
        do { _ = try await attester.observe(lookup, wallet: context.wallet); XCTFail("Changed owner hook") }
        catch { XCTAssertEqual(error as? FundingObservationError, .unavailable) }
        let batches = await rpc.batches; XCTAssertTrue(batches.isEmpty)
        context.clock.advance(61)
        do { _ = try await context.attester(.waiting).observe(lookup, wallet: context.wallet); XCTFail("Stale source") }
        catch { XCTAssertEqual(error as? FundingObservationError, .unavailable) }
    }
}
