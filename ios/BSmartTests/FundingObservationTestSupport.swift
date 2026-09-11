import XCTest
@testable import BSmart

struct FundingObservationFixture: Sendable {
    let record: FundingJournalRecord
    let now: Date
    var head: FundingRPCValue { Self.block(200, time: now) }
    var finalized: FundingRPCValue { Self.block(100, time: record.intent.planCreatedAt.addingTimeInterval(-600)) }
    var includedBlock: FundingRPCValue { Self.block(150, time: record.intent.planCreatedAt.addingTimeInterval(1)) }

    static func block(_ height: UInt64, time: Date, reorg: Bool = false) -> FundingRPCValue {
        .object(["number": .string(FundingQuantity(height).rpc),
            "hash": .string(FundingQuantity(height + (reorg ? 1000 : 0)).abi),
            "timestamp": .string(FundingQuantity(UInt64(time.timeIntervalSince1970)).rpc)])
    }

    static func vector() throws -> [String: String] {
        let url = try XCTUnwrap(Bundle(for: FundingReceiptCodecTests.self)
            .url(forResource: "cctp-source-message-vector", withExtension: "json"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    func transaction(pending: Bool = false) throws -> FundingRPCValue {
        let signed = try XCTUnwrap(record.signed)
        let i = record.intent
        var fields: [String: FundingRPCValue] = [
            "hash": .string(signed.hash), "from": .string(i.owner), "to": .string(CCTPArbitrumRoute.extensionAddress),
            "chainId": .string("0xa4b1"), "type": .string("0x2"), "value": .string("0x0"),
            "nonce": .string(i.nonce), "gas": .string(i.gasLimit), "maxFeePerGas": .string(i.maximumFeePerGas),
            "maxPriorityFeePerGas": .string("0x0"), "input": .string(FundingHex.encode(i.callData)), "accessList": .array([]),
            "r": .string(try FundingQuantity(abi: FundingHex.encode(Data(signed.signature[0..<32]))).rpc),
            "s": .string(try FundingQuantity(abi: FundingHex.encode(Data(signed.signature[32..<64]))).rpc),
            "v": .string(FundingQuantity(UInt64(signed.signature[64])).rpc)]
        fields.merge(location) { _, new in new }
        if pending { for key in location.keys { fields[key] = .null } }
        return .object(fields)
    }

    var location: [String: FundingRPCValue] {
        ["blockNumber": .string("0x96"), "blockHash": .string(FundingQuantity(150).abi), "transactionIndex": .string("0x2")]
    }

    func log() throws -> FundingRPCValue {
        var fields = location
        let vector = try Self.vector()
        fields.merge(["logIndex": .string("0x5"), "removed": .bool(false), "transactionHash": .string(record.signed!.hash),
            "address": .string(CCTPArbitrumRoute.messageTransmitter), "topics": .array([.string(vector["topic"]!)]),
            "data": .string(vector["event"]!)]) { _, new in new }
        return .object(fields)
    }

    func receipt(reverted: Bool = false) throws -> FundingRPCValue {
        var fields = location
        fields.merge(["transactionHash": .string(record.signed!.hash), "from": .string(record.intent.owner),
            "to": .string(CCTPArbitrumRoute.extensionAddress), "type": .string("0x2"), "contractAddress": .null,
            "status": .string(reverted ? "0x0" : "0x1"), "gasUsed": .string("0x30d40"),
            "effectiveGasPrice": .string("0x989680"), "logs": .array(reverted ? [] : [try log()])]) { _, new in new }
        return .object(fields)
    }

    func observer(rpc: FundingObservationRPC) -> ArbitrumSourceObserver { .init(rpc: rpc, clock: { now }) }
}

actor FundingObservationRPC: ArbitrumFundingRPCProviding {
    let fixture: FundingObservationFixture
    let overrides: [String: FundingRPCValue]
    private(set) var batches: [[FundingRPCRequest]] = []
    init(_ fixture: FundingObservationFixture, overrides: [String: FundingRPCValue] = [:]) {
        self.fixture = fixture; self.overrides = overrides
    }
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        batches.append(requests)
        let final = batches.count == 4
        return try requests.map { request in
            switch request.method {
            case .chainID: return overrides[final ? "finalChain" : "chain"] ?? .string("0xa4b1")
            case .transaction: return try overrides[final ? "finalTransaction" : "transaction"] ?? overrides["transaction"] ?? fixture.transaction()
            case .receipt: return try overrides[final ? "finalReceipt" : "receipt"] ?? overrides["receipt"] ?? fixture.receipt()
            case .block:
                let tag = try request.params[0].text()
                if final, let value = overrides["finalBlock-" + tag] { return value }
                if let value = overrides["block-" + tag] { return value }
                switch tag {
                case "latest", "0xc8": return fixture.head
                case "finalized", "0x64": return fixture.finalized
                case "0x96": return fixture.includedBlock
                default: throw FundingObservationError.invalidEvidence
                }
            case .nonce:
                return overrides[request.params.last == .string("pending") ? "pending" : "nonce"] ?? .string("0x1")
            case .call: return overrides["authorization"] ?? .string(FundingQuantity(1).abi)
            default: throw FundingObservationError.invalidEvidence
            }
        }
    }
}

func replacing(_ value: FundingRPCValue, _ key: String, with replacement: FundingRPCValue) throws -> FundingRPCValue {
    var fields = try FundingReceiptCodec.fields(value)
    fields[key] = replacement
    return .object(fields)
}
