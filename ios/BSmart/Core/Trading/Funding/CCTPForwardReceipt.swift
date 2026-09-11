import Foundation

struct CCTPForwardReceipt: Codable, Equatable, Sendable {
    let transactionHash: String
    let location: FundingTransactionLocation
    let logs: [CCTPForwardLog]

    func resolution(proof: CCTPAttestedMessage, intent: FundingJournalIntent) throws -> CCTPForwardResolution {
        guard FundingHex.decode(transactionHash)?.count == 32, transactionHash != FundingQuantity(0).abi,
              location.blockNumber > 0, FundingHex.decode(location.blockHash)?.count == 32,
              location.blockHash != FundingQuantity(0).abi else { throw FundingObservationError.invalidEvidence }
        return try CCTPForwardEventCodec.resolve(logs, proof: proof, intent: intent)
    }

    static func decode(_ value: FundingRPCValue, hash: String, proof: CCTPAttestedMessage,
                       intent: FundingJournalIntent) throws -> Self {
        let f = try FundingReceiptCodec.fields(value)
        guard try FundingReceiptCodec.text(f, "transactionHash").lowercased() == hash,
              try FundingReceiptCodec.quantity(f, "status") == FundingQuantity(1), f["contractAddress"] == .null,
              case .array(let values) = f["logs"], (1...128).contains(values.count) else {
            throw FundingObservationError.invalidEvidence
        }
        let location = try FundingReceiptCodec.location(f)
        var logs: [CCTPForwardLog] = []
        for value in values {
            let fields = try FundingReceiptCodec.fields(value)
            guard fields["removed"] == .bool(false), try FundingReceiptCodec.location(fields) == location,
                  try FundingReceiptCodec.text(fields, "transactionHash").lowercased() == hash,
                  case .array(let topics) = fields["topics"],
                  let data = try FundingHex.decode(FundingReceiptCodec.text(fields, "data").lowercased()) else {
                throw FundingObservationError.invalidEvidence
            }
            let log = try CCTPForwardLog(index: FundingReceiptCodec.quantity(fields, "logIndex").uint64Checked(),
                address: FundingReceiptCodec.text(fields, "address").lowercased(), topics: topics.map { try $0.text().lowercased() }, data: data)
            try log.validate()
            guard logs.last == nil || logs.last!.index < log.index else { throw FundingObservationError.invalidEvidence }
            logs.append(log)
        }
        let nonce = try proof.nonce
        let matches = logs.indices.filter {
            logs[$0].address == CCTPArbitrumRoute.messageTransmitter && logs[$0].topics.first == CCTPForwardEventCodec.received
                && logs[$0].topics.count > 2 && logs[$0].topics[2] == nonce
        }
        guard matches.count == 1, let start = matches.first else { throw FundingObservationError.invalidEvidence }
        // Relayers may batch messages. Correlate only the synchronous receive -> forward interval for this nonce.
        var selected: [CCTPForwardLog] = []
        for log in logs[start...] {
            if log.index != logs[start].index, log.address == CCTPArbitrumRoute.messageTransmitter,
               log.topics.first == CCTPForwardEventCodec.received { break }
            if CCTPForwardEventCodec.relevant(log) { selected.append(log) }
            if log.address == CCTPArbitrumRoute.forwarderAddress, log.topics.first == CCTPForwardEventCodec.forwarded { break }
        }
        let result = Self(transactionHash: hash, location: location, logs: selected)
        _ = try result.resolution(proof: proof, intent: intent)
        return result
    }
}
