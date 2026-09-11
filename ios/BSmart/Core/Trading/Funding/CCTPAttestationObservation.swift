import Foundation

struct CCTPAttestationLookup: Sendable {
    let record: FundingJournalRecord
    let source: FundingSourceObservation
    let previous: CCTPAttestationObservation?
    let previousVerified: CCTPAttestationObservation?
}

struct CCTPAttestationObservation: Codable, Equatable, Sendable {
    let id: UUID
    let intentID: UUID
    let sourceObservationID: UUID
    let previousID: UUID?
    let observedAt: Date
    let proof: CCTPAttestedMessage?
    let verifier: CCTPVerifierSnapshot?
    let forwardHash: String?

    func validate(_ lookup: CCTPAttestationLookup) throws {
        let source = lookup.source
        guard id != previousID, intentID == lookup.record.intent.id, intentID == source.intentID,
              sourceObservationID == source.id, previousID == lookup.previous?.id,
              lookup.record.needsReconciliation, lookup.record.signed?.hash == source.transactionHash,
              let receipt = source.receipt, receipt.succeeded, let message = receipt.message,
              FundingJournalIntent.validDate(observedAt), observedAt >= source.observedAt,
              observedAt.timeIntervalSince(source.observedAt) < 60,
              lookup.previous == nil || observedAt >= lookup.previous!.observedAt else {
            throw FundingObservationError.invalidEvidence
        }
        try receipt.validate(intent: lookup.record.intent)
        if let proof, let verifier {
            try proof.validate(source: message, intent: lookup.record.intent)
            try verifier.validate(proof: proof, at: observedAt)
            if let prior = lookup.previousVerified?.verifier {
                guard verifier.head.number >= prior.head.number else { throw FundingObservationError.inconsistentState }
                if verifier.head.number == prior.head.number {
                    guard verifier.head == prior.head, verifier.transmitterCodeHash == prior.transmitterCodeHash,
                          verifier.threshold == prior.threshold, verifier.paused == prior.paused else {
                        throw FundingObservationError.inconsistentState
                    }
                }
                if try lookup.previousVerified?.proof?.nonce == proof.nonce {
                    guard !prior.nonceUsed || verifier.nonceUsed,
                          verifier.head.number != prior.head.number || verifier.nonceUsed == prior.nonceUsed else {
                        throw FundingObservationError.inconsistentState
                    }
                }
            }
            guard forwardHash == nil || FundingHex.decode(forwardHash!)?.count == 32 else {
                throw FundingObservationError.invalidEvidence
            }
        } else if proof != nil || verifier != nil || forwardHash != nil { throw FundingObservationError.invalidEvidence }
    }
}

protocol CCTPAttestationObserving: Sendable {
    func observe(_ lookup: CCTPAttestationLookup, wallet: DeviceWalletSummary) async throws -> CCTPAttestationObservation
}

protocol CCTPAttestationJournalAccessing: Sendable {
    func attestationLookup(id: UUID, wallet: DeviceWalletSummary) async throws -> CCTPAttestationLookup
    func recordAttestation(_ observation: CCTPAttestationObservation, wallet: DeviceWalletSummary) async throws
}

struct CCTPAttestationObserver: CCTPAttestationObserving {
    private let client: CCTPMessageProviding
    private let verifier: CCTPVerifierReading
    private let clock: @Sendable () -> Date

    init(client: CCTPMessageProviding = CCTPMessageClient(), verifier: CCTPVerifierReading = HyperEVMAttesterReader(),
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.verifier = verifier
        self.clock = clock
    }

    func observe(_ lookup: CCTPAttestationLookup, wallet: DeviceWalletSummary) async throws -> CCTPAttestationObservation {
        do {
            try lookup.record.intent.require(wallet: wallet)
            let pending = observation(lookup, proof: nil, verifier: nil, forwardHash: nil)
            try pending.validate(lookup)
            let result: CCTPAttestationObservation
            switch try await client.message(transactionHash: lookup.source.transactionHash) {
            case .waiting: result = observation(lookup, proof: nil, verifier: nil, forwardHash: nil)
            case .complete(let proof, let hash):
                guard let message = lookup.source.receipt?.message else { throw FundingObservationError.invalidEvidence }
                // Reject altered routes/owners/amounts before disclosing the nonce to the destination RPC.
                try proof.validate(source: message, intent: lookup.record.intent)
                result = observation(lookup, proof: proof, verifier: try await verifier.snapshot(proof: proof), forwardHash: hash)
            }
            try result.validate(lookup)
            return result
        } catch is CancellationError { throw CancellationError() }
        catch { throw FundingObservationError.unavailable }
    }

    private func observation(_ lookup: CCTPAttestationLookup, proof: CCTPAttestedMessage?, verifier: CCTPVerifierSnapshot?,
                             forwardHash: String?) -> CCTPAttestationObservation {
        .init(id: UUID(), intentID: lookup.record.intent.id, sourceObservationID: lookup.source.id,
              previousID: lookup.previous?.id, observedAt: clock(), proof: proof, verifier: verifier, forwardHash: forwardHash)
    }
}
