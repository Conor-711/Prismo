import Foundation

enum FundingReceiptCodec {
    static func transaction(_ value: FundingRPCValue, record: FundingJournalRecord) throws -> FundingTransactionLocation? {
        guard let signed = record.signed, signed.signature.count == 65 else { throw FundingObservationError.invalidEvidence }
        let f = try fields(value)
        let intent = record.intent
        guard try text(f, "hash").lowercased() == signed.hash,
              try text(f, "from").lowercased() == intent.owner,
              try text(f, "to").lowercased() == CCTPArbitrumRoute.extensionAddress,
              try quantity(f, "chainId") == FundingQuantity(UInt64(intent.chainID)),
              try quantity(f, "type") == FundingQuantity(2), try quantity(f, "value") == FundingQuantity(0),
              try quantity(f, "nonce") == FundingQuantity(rpc: intent.nonce),
              try quantity(f, "gas") == FundingQuantity(rpc: intent.gasLimit),
              try quantity(f, "maxFeePerGas") == FundingQuantity(rpc: intent.maximumFeePerGas),
              try quantity(f, "maxPriorityFeePerGas") == FundingQuantity(0),
              try text(f, "input").lowercased() == FundingHex.encode(intent.callData),
              f["accessList"] == .array([]), f["authorizationList"] == nil else { throw FundingObservationError.invalidEvidence }
        let r = try FundingQuantity(abi: FundingHex.encode(Data(signed.signature[0..<32])))
        let s = try FundingQuantity(abi: FundingHex.encode(Data(signed.signature[32..<64])))
        guard try quantity(f, "r") == r, try quantity(f, "s") == s,
              try quantity(f, "v") == FundingQuantity(UInt64(signed.signature[64])) else { throw FundingObservationError.invalidEvidence }
        if let parity = f["yParity"] {
            guard try FundingQuantity(rpc: parity.text()) == FundingQuantity(UInt64(signed.signature[64])) else { throw FundingObservationError.invalidEvidence }
        }
        if f["blockHash"] == .null {
            guard f["blockNumber"] == .null, f["transactionIndex"] == .null else { throw FundingObservationError.inconsistentState }
            return nil
        }
        return try location(f)
    }

    static func receipt(_ value: FundingRPCValue, record: FundingJournalRecord) throws -> FundingSourceReceipt {
        guard let signed = record.signed else { throw FundingObservationError.invalidEvidence }
        let f = try fields(value)
        guard try text(f, "transactionHash").lowercased() == signed.hash,
              try text(f, "from").lowercased() == record.intent.owner,
              try text(f, "to").lowercased() == CCTPArbitrumRoute.extensionAddress,
              try quantity(f, "type") == FundingQuantity(2), f["contractAddress"] == .null,
              case .array(let logs) = f["logs"], logs.count <= 24 else { throw FundingObservationError.invalidEvidence }
        let status = try quantity(f, "status")
        guard status == FundingQuantity(0) || status == FundingQuantity(1),
              status != FundingQuantity(0) || logs.isEmpty else { throw FundingObservationError.invalidEvidence }
        let place = try location(f)
        var message: Data?
        var messageIndex: UInt64?
        var seen = Set<UInt64>()
        for value in logs {
            let log = try fields(value)
            let index = try quantity(log, "logIndex").uint64Checked()
            guard seen.insert(index).inserted, log["removed"] == .bool(false), try location(log) == place,
                  try text(log, "transactionHash").lowercased() == signed.hash,
                  case .array(let topics) = log["topics"], topics.count <= 4,
                  try topics.allSatisfy({ FundingHex.decode(try $0.text().lowercased())?.count == 32 }),
                  let bytes = try FundingHex.decode(text(log, "data").lowercased()), bytes.count <= 2_048,
                  let address = try FundingHex.decode(text(log, "address").lowercased()), address.count == 20 else {
                throw FundingObservationError.invalidEvidence
            }
            if FundingHex.encode(address) == CCTPArbitrumRoute.messageTransmitter,
               try topics.first?.text().lowercased() == CCTPSourceMessage.topic {
                guard topics.count == 1, message == nil else { throw FundingObservationError.invalidEvidence }
                message = try CCTPSourceMessage.decodeEvent(bytes, intent: record.intent)
                messageIndex = index
            }
        }
        let result = FundingSourceReceipt(location: place, succeeded: status == FundingQuantity(1),
            gasUsed: try quantity(f, "gasUsed").rpc, gasPrice: try quantity(f, "effectiveGasPrice").rpc,
            message: message, messageLogIndex: messageIndex)
        try result.validate(intent: record.intent)
        return result
    }

    static func fields(_ value: FundingRPCValue) throws -> [String: FundingRPCValue] {
        guard case .object(let fields) = value else { throw FundingObservationError.invalidEvidence }
        return fields
    }
    static func text(_ fields: [String: FundingRPCValue], _ key: String) throws -> String {
        guard let value = fields[key] else { throw FundingObservationError.invalidEvidence }
        return try value.text()
    }
    static func quantity(_ fields: [String: FundingRPCValue], _ key: String) throws -> FundingQuantity {
        try FundingQuantity(rpc: text(fields, key))
    }
    static func location(_ fields: [String: FundingRPCValue]) throws -> FundingTransactionLocation {
        let hash = try text(fields, "blockHash").lowercased()
        let number = try quantity(fields, "blockNumber").uint64Checked()
        let index = try quantity(fields, "transactionIndex").uint64Checked()
        guard number > 0, FundingHex.decode(hash)?.count == 32,
              !hash.dropFirst(2).allSatisfy({ $0 == "0" }) else { throw FundingObservationError.invalidEvidence }
        return .init(blockNumber: number, blockHash: hash, index: index)
    }
}
