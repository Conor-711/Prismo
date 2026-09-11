import Foundation

// Presentation-only projection. Never carry authorization signatures or broadcastable bytes into a view.
struct FundingHistoryEntry: Identifiable, Equatable, Sendable {
    enum AttestationStatus: Sendable { case waiting, verified, expired, paused, processed }
    enum ForwardingStatus: Sendable { case waiting, perpsRequested, spotFallback }
    enum Stage: String, Sendable {
        case reviewAuthorization, authorizationStarted, authorizationRecorded, reviewNetworkFee
        case signingStarted, signatureRecorded, submissionStarted, nodeAcknowledged, submissionUnknown, cancelled
        case sourceNotFound, sourcePending, sourceExecuted, sourceReverted, sourceReorganized, sourceConflict

        var canCancelReview: Bool { self == .reviewAuthorization || self == .reviewNetworkFee }
        var requiresReconciliation: Bool { !canCancelReview && self != .cancelled }
    }

    let id: UUID
    let accountID: UUID
    let owner: String
    let amountUnits: UInt64
    let maximumTransferFeeUnits: UInt64
    let maximumNetworkFee: FundingQuantity?
    let createdAt: Date
    let updatedAt: Date
    let stage: Stage
    let transactionHash: String?
    let sourceNetworkFee: FundingQuantity?
    let sourceDataFinalized: Bool
    let attestationStatus: AttestationStatus?
    let attestedTransferFee: FundingQuantity?
    let forwardingStatus: ForwardingStatus?
    let forwardingTransactionHash: String?
    let forwardedCoreAmount: FundingQuantity?
    let destinationAccountFee: FundingQuantity?

    init(consent: FundingConsentRecord) throws {
        let plan = try consent.plan.restored()
        id = consent.id
        accountID = consent.plan.accountID
        owner = consent.plan.owner
        amountUnits = consent.plan.amountUnits
        maximumTransferFeeUnits = plan.quote.maximumFeeUnits
        maximumNetworkFee = nil
        createdAt = consent.plan.createdAt
        updatedAt = consent.updatedAt
        transactionHash = nil
        sourceNetworkFee = nil
        sourceDataFinalized = false
        attestationStatus = nil
        attestedTransferFee = nil
        forwardingStatus = nil
        forwardingTransactionHash = nil
        forwardedCoreAmount = nil
        destinationAccountFee = nil
        switch consent.state {
        case .review: stage = .reviewAuthorization
        case .authorizing: stage = .authorizationStarted
        case .authorized: stage = .authorizationRecorded
        case .cancelled: stage = .cancelled
        }
    }

    init(source: FundingJournalRecord, observation: FundingSourceObservation? = nil,
         attestation: CCTPAttestationObservation? = nil, forwarding: CCTPForwardObservation? = nil) throws {
        id = source.intent.id
        accountID = source.intent.accountID
        owner = source.intent.owner
        amountUnits = source.intent.amountUnits
        maximumTransferFeeUnits = source.intent.maximumCCTPFeeUnits
        maximumNetworkFee = try FundingQuantity(rpc: source.intent.maximumNetworkFee)
        createdAt = source.intent.planCreatedAt
        let current = attestation.flatMap { $0.sourceObservationID == observation?.id ? $0 : nil }
        let forward = forwarding.flatMap { $0.sourceObservationID == observation?.id && $0.attestationID == current?.id ? $0 : nil }
        updatedAt = max(source.updatedAt, observation?.observedAt ?? source.updatedAt,
                        current?.observedAt ?? source.updatedAt, forward?.observedAt ?? source.updatedAt)
        transactionHash = source.signed?.hash
        sourceNetworkFee = try observation?.receipt?.networkFee
        sourceDataFinalized = observation?.sourceDataFinalized ?? false
        attestedTransferFee = try current?.proof?.fee
        if let forward {
            guard forward.intentID == id, forward.transactionHash == current?.forwardHash,
                  let proof = current?.proof else { throw FundingJournalError.integrity }
            forwardingTransactionHash = forward.transactionHash
            if let receipt = forward.receipt {
                let resolution = try receipt.resolution(proof: proof, intent: source.intent)
                forwardingStatus = resolution.destinationDex == 0 ? .perpsRequested : .spotFallback
                forwardedCoreAmount = resolution.coreAmount
                destinationAccountFee = resolution.accountFee
            } else {
                forwardingStatus = .waiting
                forwardedCoreAmount = nil
                destinationAccountFee = nil
            }
        } else {
            forwardingStatus = nil
            forwardingTransactionHash = nil
            forwardedCoreAmount = nil
            destinationAccountFee = nil
        }
        if let current {
            guard current.intentID == id, observation?.receipt?.succeeded == true else { throw FundingJournalError.integrity }
            if let proof = current.proof, let verifier = current.verifier {
                if verifier.nonceUsed { attestationStatus = .processed }
                else if verifier.paused { attestationStatus = .paused }
                else if try proof.expiration > 0 && proof.expiration <= verifier.head.number { attestationStatus = .expired }
                else { attestationStatus = .verified }
            } else { attestationStatus = .waiting }
        } else { attestationStatus = nil }
        if let observation {
            guard observation.intentID == source.intent.id, observation.transactionHash == source.signed?.hash else {
                throw FundingJournalError.integrity
            }
            let nonceConsumed = try FundingQuantity(rpc: observation.latestNonce) > FundingQuantity(rpc: source.intent.nonce)
            if let receipt = observation.receipt { stage = receipt.succeeded ? .sourceExecuted : .sourceReverted }
            else if observation.priorReceiptBlock != nil { stage = .sourceReorganized }
            else if observation.authorizationUsed || nonceConsumed {
                stage = .sourceConflict
            } else { stage = observation.transactionPresent ? .sourcePending : .sourceNotFound }
            return
        }
        switch source.state {
        case .prepared: stage = .reviewNetworkFee
        case .signing: stage = .signingStarted
        case .signed: stage = .signatureRecorded
        case .submitting: stage = .submissionStarted
        case .submitted: stage = .nodeAcknowledged
        case .uncertain: stage = .submissionUnknown
        case .cancelled: stage = .cancelled
        }
    }
}

protocol FundingHistoryAccessing: Sendable {
    func history(wallet: DeviceWalletSummary) async throws -> [FundingHistoryEntry]
    func cancelReview(id: UUID, wallet: DeviceWalletSummary) async throws
}

protocol FundingSourceJournalAccessing: Sendable {
    func sourceLookup(id: UUID, wallet: DeviceWalletSummary) async throws -> FundingSourceLookup
    func recordSourceObservation(_ observation: FundingSourceObservation, wallet: DeviceWalletSummary) async throws
}
