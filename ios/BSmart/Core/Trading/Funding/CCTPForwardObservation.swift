import Foundation

struct CCTPForwardLookup: Sendable {
    let record: FundingJournalRecord
    let source: FundingSourceObservation
    let attestation: CCTPAttestationObservation
    let previous: CCTPForwardObservation?

    func validate(at date: Date) throws -> CCTPAttestedMessage {
        guard record.needsReconciliation, record.signed?.hash == source.transactionHash,
              source.intentID == record.intent.id, attestation.intentID == record.intent.id,
              attestation.sourceObservationID == source.id, source.receipt?.succeeded == true,
              let message = source.receipt?.message, let proof = attestation.proof, let verifier = attestation.verifier,
              let hash = attestation.forwardHash, FundingHex.decode(hash)?.count == 32, hash != FundingQuantity(0).abi,
              FundingJournalIntent.validDate(date), date >= attestation.observedAt,
              date.timeIntervalSince(attestation.observedAt) < 60 else { throw FundingObservationError.invalidEvidence }
        try proof.validate(source: message, intent: record.intent)
        try verifier.validate(proof: proof, at: attestation.observedAt)
        return proof
    }
}

struct CCTPForwardObservation: Codable, Equatable, Sendable {
    let id: UUID
    let intentID: UUID
    let sourceObservationID: UUID
    let attestationID: UUID
    let previousID: UUID?
    let transactionHash: String
    let head: FundingSourceBlock
    let nonceUsed: Bool
    let receipt: CCTPForwardReceipt?
    let receiptBlock: FundingSourceBlock?
    let observedAt: Date

    func validate(_ lookup: CCTPForwardLookup) throws {
        let proof = try lookup.validate(at: observedAt)
        guard id != previousID, intentID == lookup.record.intent.id, sourceObservationID == lookup.source.id,
              attestationID == lookup.attestation.id, previousID == lookup.previous?.id,
              transactionHash == lookup.attestation.forwardHash, let verified = lookup.attestation.verifier else {
            throw FundingObservationError.invalidEvidence
        }
        try head.validate(now: observedAt, fresh: true)
        guard head.number >= verified.head.number, head.timestamp >= verified.head.timestamp,
              head.number != verified.head.number || head == verified.head,
              !verified.nonceUsed || nonceUsed,
              head.number != verified.head.number || nonceUsed == verified.nonceUsed else {
            throw FundingObservationError.inconsistentState
        }
        if let receipt, let block = receiptBlock {
            _ = try receipt.resolution(proof: proof, intent: lookup.record.intent)
            try block.validate(now: observedAt)
            guard nonceUsed, receipt.transactionHash == transactionHash,
                  block.number == receipt.location.blockNumber, block.hash == receipt.location.blockHash,
                  block.number <= head.number, block.timestamp <= head.timestamp,
                  block.number != head.number || block == head,
                  let sourceBlock = lookup.source.receiptBlock, block.timestamp >= sourceBlock.timestamp.addingTimeInterval(-15),
                  try proof.expiration == 0 || block.number < proof.expiration else { throw FundingObservationError.inconsistentState }
        } else if receipt != nil || receiptBlock != nil { throw FundingObservationError.invalidEvidence }
        if let prior = lookup.previous {
            guard observedAt >= prior.observedAt, head.number >= prior.head.number,
                  head.timestamp >= prior.head.timestamp, head.number != prior.head.number || head == prior.head else {
                throw FundingObservationError.inconsistentState
            }
            // HyperBFT inclusion is final. Never silently downgrade/replace an accepted destination receipt.
            if let accepted = prior.receipt {
                guard receipt == accepted, receiptBlock == prior.receiptBlock else { throw FundingObservationError.inconsistentState }
            }
            if transactionHash == prior.transactionHash, prior.nonceUsed, !nonceUsed {
                throw FundingObservationError.inconsistentState
            }
        }
    }
}

protocol CCTPForwardObserving: Sendable {
    func observe(_ lookup: CCTPForwardLookup, wallet: DeviceWalletSummary) async throws -> CCTPForwardObservation
}

protocol CCTPForwardJournalAccessing: Sendable {
    func forwardingLookup(id: UUID, wallet: DeviceWalletSummary) async throws -> CCTPForwardLookup
    func recordForwarding(_ observation: CCTPForwardObservation, wallet: DeviceWalletSummary) async throws
}
