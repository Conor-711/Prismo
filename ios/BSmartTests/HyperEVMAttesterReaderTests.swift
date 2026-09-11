import XCTest
@testable import BSmart

final class HyperEVMAttesterReaderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_770_000_120)

    func testFixedDestinationReadsAndExactOnchainQuorum() async throws {
        let proof = try AttestationVector.load().proof()
        let rpc = AttesterRPCStub(now: now)
        let result = try await HyperEVMAttesterReader(rpc: rpc, clock: { self.now }).snapshot(proof: proof)
        XCTAssertEqual(result.threshold, 2)
        XCTAssertFalse(result.paused); XCTAssertFalse(result.nonceUsed)
        let batches = await rpc.batches
        XCTAssertEqual(batches.count, 5)
        XCTAssertEqual(batches[0].first?.method, .chainID)
        XCTAssertEqual(batches[1].first?.method, .block)
        XCTAssertEqual(batches[3].first?.method, .block)
        for request in batches[2] {
            XCTAssertEqual(request.params.last, .string("latest"))
            if request.method == .call {
                let fields = try FundingReceiptCodec.fields(request.params[0])
                XCTAssertEqual(fields["to"], .string(CCTPArbitrumRoute.messageTransmitter))
                XCTAssertEqual(Set(fields.keys), Set(["to", "data"]))
            }
        }
    }

    func testWrongChainStaleChangedHeadsDisabledSignersAndWrongQuorumFail() async throws {
        let proof = try AttestationVector.load().proof()
        for overrides: [String: FundingRPCValue] in [
            ["chain": .string("0xa4b1")], ["finalChain": .string("0x3e6")],
            ["before": FundingObservationFixture.block(500, time: now.addingTimeInterval(-61))],
            ["after": FundingObservationFixture.block(501, time: now)],
            ["after": FundingObservationFixture.block(500, time: now, reorg: true)],
            ["code": .string("0x")], ["localDomain()": .string(FundingQuantity(3).abi)],
            ["version()": .string(FundingQuantity(0).abi)],
            ["signatureThreshold()": .string(FundingQuantity(1).abi)],
            ["signatureThreshold()": .string(FundingQuantity(3).abi)],
            ["signatureThreshold()": .string(FundingQuantity(0).abi)],
            ["isEnabledAttester(address)": .string(FundingQuantity(0).abi)],
            ["paused()": .string(FundingQuantity(2).abi)]
        ] {
            let rpc = AttesterRPCStub(now: now, overrides: overrides)
            do { _ = try await HyperEVMAttesterReader(rpc: rpc, clock: { self.now }).snapshot(proof: proof); XCTFail("Accepted \(overrides)") }
            catch { XCTAssertEqual(error as? FundingObservationError, .unavailable) }
            if overrides["chain"] != nil { let batches = await rpc.batches; XCTAssertEqual(batches.count, 1) }
        }
    }

    func testPausedAndUsedNonceAreObservationsNotCredit() async throws {
        let proof = try AttestationVector.load().proof()
        let rpc = AttesterRPCStub(now: now, overrides: ["paused()": .string(FundingQuantity(1).abi),
                                                       "usedNonces(bytes32)": .string(FundingQuantity(1).abi)])
        let result = try await HyperEVMAttesterReader(rpc: rpc, clock: { self.now }).snapshot(proof: proof)
        XCTAssertTrue(result.paused); XCTAssertTrue(result.nonceUsed)
    }
}
