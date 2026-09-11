import XCTest
@testable import BSmart

final class CCTPForwardObserverTests: XCTestCase {
    func testFixedChainHashAndCanonicalReceiptAreReadTwiceWithoutWrites() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.forwardingReady()
        let fixture = try ForwardVector.load()
        let rpc = ForwardRPCStub(now: context.clock.now, receipt: try fixture.receipt())
        let result = try await CCTPForwardObserver(rpc: rpc, clock: { context.clock.now }).observe(lookup, wallet: context.wallet)
        XCTAssertEqual(result.receipt?.transactionHash, fixture.hash)
        let batches = await rpc.batches
        XCTAssertEqual(batches.first?.first?.method, .chainID)
        XCTAssertEqual(batches.last?.first?.method, .chainID)
        let receiptReads = batches.flatMap { $0 }.filter { $0.method == .receipt }
        XCTAssertEqual(receiptReads.count, 2)
        XCTAssertTrue(receiptReads.allSatisfy { $0.params == [.string(fixture.hash)] })
        XCTAssertTrue(batches.flatMap { $0 }.allSatisfy { [.chainID, .block, .receipt, .call].contains($0.method) })
    }

    func testWrongChainChangedReceiptsHeadsBlocksAndNonceFailClosed() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.forwardingReady()
        for overrides: [String: FundingRPCValue] in [
            ["chain": .string("0xa4b1")], ["finalChain": .string("0xa4b1")], ["used": .string(FundingQuantity(0).abi)],
            ["finalReceipt": .null], ["final-head": FundingObservationFixture.block(501, time: context.clock.now)],
            ["final-block": FundingObservationFixture.block(490, time: context.clock.now.addingTimeInterval(-5), reorg: true)],
            ["block": FundingObservationFixture.block(490, time: context.clock.now, reorg: true)],
            ["head": FundingObservationFixture.block(499, time: context.clock.now)],
            ["head": FundingObservationFixture.block(500, time: context.clock.now.addingTimeInterval(-61))]
        ] {
            do { _ = try await context.forwarder(overrides: overrides).observe(lookup, wallet: context.wallet); XCTFail("Accepted inconsistent destination") }
            catch { XCTAssertEqual(error as? FundingObservationError, .unavailable) }
        }
    }

    func testForeignAndStaleLookupRejectedBeforeDisclosingHashAndMissingReceiptIsNotCredit() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.forwardingReady()
        let rpc = ForwardRPCStub(now: context.clock.now, receipt: .null)
        let observer = CCTPForwardObserver(rpc: rpc, clock: { context.clock.now })
        let foreign = DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true)
        do { _ = try await observer.observe(lookup, wallet: foreign); XCTFail("Foreign wallet") } catch {}
        var requests = await rpc.batches; XCTAssertTrue(requests.isEmpty)
        let result = try await observer.observe(lookup, wallet: context.wallet)
        XCTAssertNil(result.receipt); XCTAssertNil(result.receiptBlock)
        context.clock.advance(60)
        let staleRPC = ForwardRPCStub(now: context.clock.now, receipt: .null)
        do { _ = try await CCTPForwardObserver(rpc: staleRPC, clock: { context.clock.now }).observe(lookup, wallet: context.wallet); XCTFail("Stale attestation") } catch {}
        requests = await staleRPC.batches; XCTAssertTrue(requests.isEmpty)
    }
}
