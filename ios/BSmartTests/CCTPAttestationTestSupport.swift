import XCTest
import WalletCore
@testable import BSmart

struct AttestationVector: Decodable {
    let message: String
    let attestation: String
    let digest: String
    let signers: [String]

    static func load() throws -> Self {
        let url = try XCTUnwrap(Bundle(for: CCTPAttestedMessageTests.self).url(forResource: "cctp-attestation-vector", withExtension: "json"))
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func proof() throws -> CCTPAttestedMessage {
        .init(message: try XCTUnwrap(FundingHex.decode(message)), attestation: try XCTUnwrap(FundingHex.decode(attestation)))
    }
    // Public deterministic test keys, never actual attesters or a device wallet.
    static func sign(_ message: Data) throws -> CCTPAttestedMessage {
        var signatures = Data()
        for value: UInt8 in [2, 3] {
            let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([value])))
            var signature = try XCTUnwrap(key.sign(digest: Hash.keccak256(data: message), curve: .secp256k1))
            signature[64] += 27
            signatures.append(signature)
        }
        return .init(message: message, attestation: signatures)
    }
    func response(hash: String, row: [String: Any] = [:], count: Int = 1) throws -> Data {
        var item: [String: Any] = ["message": message, "attestation": attestation,
                                 "eventNonce": try proof().nonce, "status": "complete", "cctpVersion": 2]
        item.merge(row) { _, new in new }
        return try JSONSerialization.data(withJSONObject: ["sourceTxHash": hash, "messages": Array(repeating: item, count: count)])
    }
}

actor AttesterRPCStub: FundingRPCProviding {
    let now: Date
    let overrides: [String: FundingRPCValue]
    private(set) var batches: [[FundingRPCRequest]] = []
    init(now: Date, overrides: [String: FundingRPCValue] = [:]) { self.now = now; self.overrides = overrides }
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        batches.append(requests)
        return try requests.map { request in
            switch request.method {
            case .chainID: return overrides[batches.count == 5 ? "finalChain" : "chain"] ?? .string("0x3e7")
            case .block: return overrides[batches.count == 4 ? "after" : "before"] ?? FundingObservationFixture.block(500, time: now)
            case .code: return overrides["code"] ?? .string("0x60006000")
            case .call:
                let fields = try FundingReceiptCodec.fields(request.params[0])
                let data = try FundingReceiptCodec.text(fields, "data")
                for (name, value) in [("localDomain()", 19), ("version()", 1), ("signatureThreshold()", 2),
                                       ("paused()", 0), ("usedNonces(bytes32)", 0), ("isEnabledAttester(address)", 1)] {
                    if data.hasPrefix(try CCTPSourceReadCodec.call(name)) {
                        return overrides[name] ?? .string(FundingQuantity(UInt64(value)).abi)
                    }
                }
                throw FundingObservationError.invalidEvidence
            default: throw FundingObservationError.invalidEvidence
            }
        }
    }
}

struct AttestationMessageStub: CCTPMessageProviding {
    let result: CCTPMessageResult
    func message(transactionHash: String) async throws -> CCTPMessageResult { result }
}

extension FundingJournalTestContext {
    func attestationReady() async throws -> (FundingTransactionJournal, CCTPAttestationLookup) {
        let journal = try journal()
        let id = UUID()
        _ = try await ready(transaction(), id: id, journal: journal)
        clock.advance(120)
        let lookup = try await journal.sourceLookup(id: id, wallet: wallet)
        let fixture = FundingObservationFixture(record: lookup.record, now: clock.now)
        let source = try await fixture.observer(rpc: FundingObservationRPC(fixture)).observe(lookup, wallet: wallet)
        try await journal.recordSourceObservation(source, wallet: wallet)
        return try await (journal, journal.attestationLookup(id: id, wallet: wallet))
    }

    func attester(_ result: CCTPMessageResult, rpc: AttesterRPCStub? = nil) -> CCTPAttestationObserver {
        .init(client: AttestationMessageStub(result: result),
              verifier: HyperEVMAttesterReader(rpc: rpc ?? AttesterRPCStub(now: clock.now), clock: { clock.now }),
              clock: { clock.now })
    }
}
