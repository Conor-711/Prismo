import XCTest
@testable import BSmart

struct ForwardVector: Decodable, Sendable {
    let hash: String
    let variants: [String: FundingRPCValue]
    static func load() throws -> Self {
        let url = try XCTUnwrap(Bundle(for: CCTPForwardReceiptTests.self).url(forResource: "cctp-forward-vector", withExtension: "json"))
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func receipt(_ mode: String = "perps") throws -> FundingRPCValue { try XCTUnwrap(variants[mode]) }
}

actor ForwardRPCStub: FundingRPCProviding {
    let now: Date
    let receipt: FundingRPCValue
    let overrides: [String: FundingRPCValue]
    private(set) var batches: [[FundingRPCRequest]] = []
    init(now: Date, receipt: FundingRPCValue, overrides: [String: FundingRPCValue] = [:]) {
        self.now = now; self.receipt = receipt; self.overrides = overrides
    }
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        batches.append(requests)
        let final = requests.count > 1
        return try requests.map { request in
            switch request.method {
            case .chainID: return overrides[batches.count > 1 ? "finalChain" : "chain"] ?? .string("0x3e7")
            case .receipt: return overrides[final ? "finalReceipt" : "receipt"] ?? receipt
            case .block:
                let latest = request.params[0] == .string("latest")
                return overrides[(final ? "final-" : "") + (latest ? "head" : "block")]
                    ?? FundingObservationFixture.block(latest ? 500 : 490, time: latest ? now : now.addingTimeInterval(-5))
            case .call:
                let fields = try FundingReceiptCodec.fields(request.params[0])
                XCTAssertEqual(fields["to"], .string(CCTPArbitrumRoute.messageTransmitter))
                XCTAssertEqual(request.params.last, .string("latest"))
                return overrides["used"] ?? .string(FundingQuantity(1).abi)
            default: XCTFail("Unexpected RPC"); throw FundingObservationError.invalidEvidence
            }
        }
    }
}

extension FundingJournalTestContext {
    func forwardingReady() async throws -> (FundingTransactionJournal, CCTPForwardLookup) {
        let (journal, lookup) = try await attestationReady()
        let rpc = AttesterRPCStub(now: clock.now, overrides: ["usedNonces(bytes32)": .string(FundingQuantity(1).abi)])
        let evidence = try await attester(.complete(AttestationVector.load().proof(), forwardHash: ForwardVector.load().hash), rpc: rpc)
            .observe(lookup, wallet: wallet)
        try await journal.recordAttestation(evidence, wallet: wallet)
        return try await (journal, journal.forwardingLookup(id: lookup.record.intent.id, wallet: wallet))
    }
    func forwarder(mode: String = "perps", overrides: [String: FundingRPCValue] = [:]) throws -> CCTPForwardObserver {
        .init(rpc: ForwardRPCStub(now: clock.now, receipt: try ForwardVector.load().receipt(mode), overrides: overrides), clock: { clock.now })
    }
}
