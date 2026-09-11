import Foundation

struct FundingSourceBlock: Codable, Equatable, Sendable {
    let number: UInt64
    let hash: String
    let timestamp: Date

    init(_ value: FundingRPCValue, now: Date, fresh: Bool = false) throws {
        let fields = try FundingReceiptCodec.fields(value)
        number = try FundingReceiptCodec.quantity(fields, "number").uint64Checked()
        hash = try FundingReceiptCodec.text(fields, "hash").lowercased()
        let seconds = try FundingReceiptCodec.quantity(fields, "timestamp").uint64Checked()
        guard seconds < 4_102_444_800 else { throw FundingObservationError.invalidEvidence }
        timestamp = Date(timeIntervalSince1970: TimeInterval(seconds))
        try validate(now: now, fresh: fresh)
    }

    var rpc: String { FundingQuantity(number).rpc }
    var reference: FundingRPCValue { .object(["blockHash": .string(hash), "requireCanonical": .bool(true)]) }

    func validate(now: Date, fresh: Bool = false) throws {
        guard number > 0, FundingHex.decode(hash)?.count == 32, !hash.dropFirst(2).allSatisfy({ $0 == "0" }),
              FundingJournalIntent.validDate(timestamp), timestamp <= now.addingTimeInterval(15),
              !fresh || now.timeIntervalSince(timestamp) < 60 else { throw FundingObservationError.inconsistentState }
    }
}

struct FundingTransactionLocation: Codable, Equatable, Sendable {
    let blockNumber: UInt64
    let blockHash: String
    let index: UInt64
}

struct FundingSourceReceipt: Codable, Equatable, Sendable {
    let location: FundingTransactionLocation
    let succeeded: Bool
    let gasUsed: String
    let gasPrice: String
    let message: Data?
    let messageLogIndex: UInt64?

    var networkFee: FundingQuantity { get throws { try FundingQuantity(rpc: gasUsed).multiplied(by: FundingQuantity(rpc: gasPrice)) } }

    func validate(intent: FundingJournalIntent) throws {
        guard location.blockNumber > 0, FundingHex.decode(location.blockHash)?.count == 32,
              try FundingQuantity(rpc: gasUsed) >= FundingQuantity(21_000),
              try FundingQuantity(rpc: gasUsed) <= FundingQuantity(rpc: intent.gasLimit),
              try FundingQuantity(rpc: gasPrice) > FundingQuantity(0),
              try FundingQuantity(rpc: gasPrice) <= FundingQuantity(rpc: intent.maximumFeePerGas),
              try networkFee <= FundingQuantity(rpc: intent.maximumNetworkFee),
              succeeded == (message != nil), succeeded == (messageLogIndex != nil) else { throw FundingObservationError.invalidEvidence }
        if let message { try CCTPSourceMessage.validate(message, intent: intent) }
    }
}

struct FundingSourceLookup: Sendable {
    let record: FundingJournalRecord
    let previous: FundingSourceObservation?
}

struct FundingSourceObservation: Codable, Equatable, Sendable {
    let id: UUID
    let intentID: UUID
    let previousID: UUID?
    let transactionHash: String
    let transactionPresent: Bool
    let receipt: FundingSourceReceipt?
    let head: FundingSourceBlock
    let finalizedHead: FundingSourceBlock
    let receiptBlock: FundingSourceBlock?
    let priorReceiptBlock: FundingSourceBlock?
    let latestNonce: String
    let pendingNonce: String
    let authorizationUsed: Bool
    let observedAt: Date

    var sourceDataFinalized: Bool { receipt.map { $0.location.blockNumber <= finalizedHead.number } ?? false }

    func validate(record: FundingJournalRecord, previous: Self?) throws {
        guard let signed = record.signed, record.needsReconciliation,
              record.intent.id == intentID, signed.hash == transactionHash, previousID == previous?.id,
              id != previousID, FundingJournalIntent.validDate(observedAt), observedAt >= record.intent.preparedAt,
              previous == nil || observedAt >= previous!.observedAt else { throw FundingObservationError.invalidEvidence }
        try head.validate(now: observedAt, fresh: true)
        try finalizedHead.validate(now: observedAt)
        guard finalizedHead.number <= head.number, finalizedHead.timestamp <= head.timestamp,
              finalizedHead.number != head.number || finalizedHead.hash == head.hash,
              previous == nil || head.number >= previous!.head.number,
              previous == nil || finalizedHead.number >= previous!.finalizedHead.number else { throw FundingObservationError.inconsistentState }
        if let previous, finalizedHead.number == previous.finalizedHead.number, finalizedHead != previous.finalizedHead {
            throw FundingObservationError.inconsistentState
        }
        var canonical: [UInt64: FundingSourceBlock] = [:]
        for block in [head, finalizedHead] + [receiptBlock, priorReceiptBlock].compactMap({ $0 }) {
            if let existing = canonical[block.number], existing != block { throw FundingObservationError.inconsistentState }
            canonical[block.number] = block
        }
        let nonce = try FundingQuantity(rpc: latestNonce)
        let pending = try FundingQuantity(rpc: pendingNonce)
        guard nonce.uint64 != nil, pending.uint64 != nil, pending >= nonce else { throw FundingObservationError.invalidEvidence }
        if let receipt, let receiptBlock {
            try receipt.validate(intent: record.intent)
            try receiptBlock.validate(now: observedAt)
            guard transactionPresent, receiptBlock.number == receipt.location.blockNumber,
                  receiptBlock.hash == receipt.location.blockHash, receiptBlock.number <= head.number,
                  receiptBlock.timestamp >= record.intent.planCreatedAt.addingTimeInterval(-30), receiptBlock.timestamp <= head.timestamp,
                  receiptBlock.number != head.number || receiptBlock.hash == head.hash,
                  receiptBlock.number != finalizedHead.number || receiptBlock.hash == finalizedHead.hash,
                  try nonce > FundingQuantity(rpc: record.intent.nonce), !receipt.succeeded || authorizationUsed else {
                throw FundingObservationError.inconsistentState
            }
        } else if receipt != nil || receiptBlock != nil { throw FundingObservationError.invalidEvidence }
        if let prior = previous?.receipt {
            guard let block = priorReceiptBlock, block.number == prior.location.blockNumber else { throw FundingObservationError.invalidEvidence }
            try block.validate(now: observedAt)
            guard block.number <= head.number, block.timestamp <= head.timestamp else { throw FundingObservationError.inconsistentState }
            if let previous, prior.location.blockNumber <= previous.finalizedHead.number,
               block.hash != prior.location.blockHash { throw FundingObservationError.inconsistentState }
            if receipt == nil && block.hash == prior.location.blockHash { throw FundingObservationError.inconsistentState }
            if let receipt, receipt.location.blockHash == prior.location.blockHash, receipt != prior { throw FundingObservationError.inconsistentState }
        } else if priorReceiptBlock != nil { throw FundingObservationError.invalidEvidence }
        if transactionPresent && receipt == nil {
            guard try nonce <= FundingQuantity(rpc: record.intent.nonce), !authorizationUsed else { throw FundingObservationError.inconsistentState }
        }
    }
}

enum FundingObservationError: Error, LocalizedError {
    case unavailable, invalidEvidence, inconsistentState
    var errorDescription: String? {
        "The source transaction could not be verified. Do not send another deposit.".bSmartLocalized
    }
}

extension FundingQuantity {
    func uint64Checked() throws -> UInt64 {
        guard let value = uint64 else { throw FundingObservationError.invalidEvidence }
        return value
    }
}
