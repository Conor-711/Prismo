import XCTest
@testable import BSmart

final class ArbitrumSourceObserverTests: XCTestCase {
    func testOldReceiptAfterSignatureExpiryAndCanonicalStateReads() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let lookup = try await lookup(context)
        let f = FundingObservationFixture(record: lookup.record, now: context.clock.now.addingTimeInterval(120))
        let rpc = FundingObservationRPC(f)
        let result = try await f.observer(rpc: rpc).observe(lookup, wallet: context.wallet)
        XCTAssertTrue(result.receipt?.succeeded == true)
        XCTAssertFalse(result.sourceDataFinalized)
        XCTAssertGreaterThan(result.observedAt.timeIntervalSince(result.receiptBlock!.timestamp), 60)
        let batches = await rpc.batches
        XCTAssertEqual(batches.count, 4)
        XCTAssertEqual(batches[0].map(\.method), [.chainID])
        XCTAssertEqual(batches[1][1].params, [.string(lookup.record.signed!.hash)])
        XCTAssertEqual(batches[1][2].params, [.string(lookup.record.signed!.hash)])
        XCTAssertEqual(batches[2][0].params.last, result.head.reference)
        XCTAssertEqual(batches[2][2].params.last, result.head.reference)
        XCTAssertEqual(try FundingHistoryEntry(source: lookup.record, observation: result).stage, .sourceExecuted)
    }

    func testMissingPendingRevertedAndConsumedNonceRemainUnresolved() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let lookup = try await lookup(context)
        let f = FundingObservationFixture(record: lookup.record, now: context.clock.now.addingTimeInterval(120))
        let empty: [String: FundingRPCValue] = ["transaction": .null, "receipt": .null,
            "nonce": .string("0x0"), "pending": .string("0x0"), "authorization": .string(FundingQuantity(0).abi)]
        let cases: [(FundingHistoryEntry.Stage, [String: FundingRPCValue])] = [(.sourceNotFound, empty),
            (.sourcePending, empty.merging(["transaction": try f.transaction(pending: true), "pending": .string("0x1")]) { _, v in v }),
            (.sourceConflict, empty.merging(["nonce": .string("0x1"), "pending": .string("0x1")]) { _, v in v }),
            (.sourceConflict, empty.merging(["authorization": .string(FundingQuantity(1).abi)]) { _, v in v }),
            (.sourceReverted, ["receipt": try f.receipt(reverted: true), "authorization": .string(FundingQuantity(0).abi)])]
        for (expected, overrides) in cases {
            let result = try await f.observer(rpc: FundingObservationRPC(f, overrides: overrides)).observe(lookup, wallet: context.wallet)
            let entry = try FundingHistoryEntry(source: lookup.record, observation: result)
            XCTAssertEqual(entry.stage, expected)
            XCTAssertTrue(entry.stage.requiresReconciliation)
            XCTAssertFalse(entry.stage.canCancelReview)
        }
    }

    func testWrongChainBeforeDisclosureAndWrongAccountBeforeNetwork() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let lookup = try await lookup(context)
        let f = FundingObservationFixture(record: lookup.record, now: context.clock.now)
        let wrongChain = FundingObservationRPC(f, overrides: ["chain": .string("0x1")])
        await expectJournalFailure { try await f.observer(rpc: wrongChain).observe(lookup, wallet: context.wallet) }
        let batches = await wrongChain.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertTrue(batches[0][0].params.isEmpty)
        let rpc = FundingObservationRPC(f)
        let other = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        await expectJournalFailure { try await f.observer(rpc: rpc).observe(lookup, wallet: other) }
        let requests = await rpc.batches
        XCTAssertTrue(requests.isEmpty)
    }

    func testMixedSnapshotsChangedRepliesAndContradictionsFailClosed() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let lookup = try await lookup(context)
        let f = FundingObservationFixture(record: lookup.record, now: context.clock.now.addingTimeInterval(120))
        let overrides: [[String: FundingRPCValue]] = [
            ["transaction": .null], ["receipt": .null], ["nonce": .string("0x0")], ["pending": .string("0x0")],
            ["authorization": .string(FundingQuantity(0).abi)], ["finalChain": .string("0x1")],
            ["finalTransaction": .null], ["finalReceipt": .null],
            ["block-latest": FundingObservationFixture.block(200, time: f.now.addingTimeInterval(-60))],
            ["block-0x96": FundingObservationFixture.block(150, time: context.clock.now, reorg: true)],
            ["finalBlock-0xc8": FundingObservationFixture.block(200, time: f.now, reorg: true)],
            ["finalBlock-0x64": FundingObservationFixture.block(100, time: context.clock.now, reorg: true)]]
        for override in overrides {
            do {
                _ = try await f.observer(rpc: FundingObservationRPC(f, overrides: override)).observe(lookup, wallet: context.wallet)
                XCTFail("Accepted \(override.keys)")
            } catch { XCTAssertTrue(error is FundingObservationError) }
        }
    }

    func testReorgRequiresChangedPriorBlockAndFinalizedEvidenceCannotBeRewritten() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let initial = try await lookup(context)
        let f = FundingObservationFixture(record: initial.record, now: context.clock.now.addingTimeInterval(120))
        for finalized in [false, true] {
            let overrides: [String: FundingRPCValue] = finalized ? ["block-finalized": f.includedBlock] : [:]
            let prior = try await f.observer(rpc: FundingObservationRPC(f, overrides: overrides)).observe(initial, wallet: context.wallet)
            XCTAssertEqual(prior.sourceDataFinalized, finalized)
            let next = FundingSourceLookup(record: initial.record, previous: prior)
            let missing: [String: FundingRPCValue] = ["transaction": .null, "receipt": .null,
                "nonce": .string("0x0"), "pending": .string("0x0"), "authorization": .string(FundingQuantity(0).abi)]
            await expectJournalFailure { try await f.observer(rpc: FundingObservationRPC(f, overrides: missing)).observe(next, wallet: context.wallet) }
            var reorg = missing
            reorg["block-0x96"] = FundingObservationFixture.block(150, time: context.clock.now, reorg: true)
            if finalized { reorg["block-finalized"] = f.head }
            let observer = f.observer(rpc: FundingObservationRPC(f, overrides: reorg))
            if finalized {
                await expectJournalFailure { try await observer.observe(next, wallet: context.wallet) }
            } else {
                let result = try await observer.observe(next, wallet: context.wallet)
                XCTAssertEqual(try FundingHistoryEntry(source: next.record, observation: result).stage, .sourceReorganized)
            }
        }
    }

    private func lookup(_ context: FundingJournalTestContext) async throws -> FundingSourceLookup {
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        return try await journal.sourceLookup(id: id, wallet: context.wallet)
    }
}
