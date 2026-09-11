import XCTest
@testable import BSmart

final class FundingObservationJournalTests: XCTestCase {
    func testObservationSurvivesReopenAndNeverReleasesOrRebroadcastsSignedIntent() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(); let id = UUID()
        let transaction = try await context.transaction()
        let signed = try await context.readyWithConsent(transaction, id: id, journal: journal)
        let check = try await context.recordedSubmissionCheck(signed)
        context.clock.advance(2)
        let lookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
        let fixture = FundingObservationFixture(record: lookup.record, now: context.clock.now)
        let observation = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: context.wallet)
        try await journal.recordSourceObservation(observation, wallet: context.wallet)
        try await journal.recordSourceObservation(observation, wallet: context.wallet)
        let reopened = try context.journal()
        let stored = try await reopened.sourceLookup(id: id, wallet: context.wallet)
        XCTAssertEqual(stored.previous, observation)
        XCTAssertEqual(stored.record, lookup.record)
        let history = try await reopened.history(wallet: context.wallet)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.stage, .sourceExecuted)
        XCTAssertEqual(history.first?.sourceNetworkFee, FundingQuantity(2_000_000_000_000))
        await expectJournalFailure { try await reopened.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: check) }
        await expectJournalFailure { try await reopened.cancelReview(id: id, wallet: context.wallet) }
        let otherTransaction = try await context.transaction(nonce: "0x1", authorizationNonce: 18)
        await expectJournalFailure { try await reopened.reserve(id: UUID(), transaction: otherTransaction, wallet: context.wallet) }
    }

    func testLateConcurrentObservationCannotOverwriteNewerEvidence() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        context.clock.advance(120)
        let lookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
        let fixture = FundingObservationFixture(record: lookup.record, now: context.clock.now)
        let first = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: context.wallet)
        let concurrent = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: context.wallet)
        try await journal.recordSourceObservation(first, wallet: context.wallet)
        await expectJournalFailure { try await journal.recordSourceObservation(concurrent, wallet: context.wallet) }
        let nextLookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
        let next = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(nextLookup, wallet: context.wallet)
        try await journal.recordSourceObservation(next, wallet: context.wallet)
        XCTAssertEqual(next.previousID, first.id)
        let reopened = try await context.journal().sourceLookup(id: id, wallet: context.wallet)
        XCTAssertEqual(reopened.previous, next)
    }

    func testCorruptedForeignOrFutureObservationRejectedWithoutChangingHistory() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        context.clock.advance(120)
        let lookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
        let fixture = FundingObservationFixture(record: lookup.record, now: context.clock.now)
        let valid = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: context.wallet)
        let data = try JSONEncoder().encode(valid)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let replacements: [String: Any] = ["transactionHash": FundingQuantity(3).abi, "intentID": UUID().uuidString,
            "previousID": UUID().uuidString, "observedAt": context.clock.now.addingTimeInterval(1).timeIntervalSinceReferenceDate,
            "authorizationUsed": false, "latestNonce": "0x0"]
        for (key, value) in replacements {
            var altered = fields; altered[key] = value
            let invalid = try JSONDecoder().decode(FundingSourceObservation.self, from: JSONSerialization.data(withJSONObject: altered))
            await expectJournalFailure { try await journal.recordSourceObservation(invalid, wallet: context.wallet) }
        }
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        await expectJournalFailure { try await journal.recordSourceObservation(valid, wallet: other) }
        let stored = try await journal.sourceLookup(id: id, wallet: context.wallet)
        XCTAssertNil(stored.previous)
        XCTAssertEqual(stored.record, lookup.record)
    }

    func testObservedEvidenceRecoversAcrossCommitFailures() async throws {
        for phase in [FundingJournalCommitPhase.afterPendingAnchor, .beforeCommit, .afterCommit] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let journal = try context.journal(); let id = UUID()
            _ = try await context.ready(context.transaction(), id: id, journal: journal)
            context.clock.advance(120)
            let lookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
            let fixture = FundingObservationFixture(record: lookup.record, now: context.clock.now)
            let observation = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: context.wallet)
            let failing = try context.journal { current in if current == phase { throw FundingJournalError.unavailable } }
            await expectJournalFailure { try await failing.recordSourceObservation(observation, wallet: context.wallet) }
            let recovered = try context.journal()
            let state = try await recovered.sourceLookup(id: id, wallet: context.wallet)
            XCTAssertEqual(state.previous, phase == .afterCommit ? observation : nil)
            try await recovered.recordSourceObservation(observation, wallet: context.wallet)
            let final = try await recovered.sourceLookup(id: id, wallet: context.wallet)
            XCTAssertEqual(final.previous, observation)
        }
    }
}
