import Foundation

enum FundingJournalEvent: Codable {
    case source(FundingJournalRecord)
    case consent(FundingConsentRecord)
    case observation(FundingSourceObservation)
    case attestation(CCTPAttestationObservation)
    case forwarding(CCTPForwardObservation)
    case order(HyperliquidOrderRecord)
    case orderFills(HyperliquidOrderFillBatch)
    case withdrawal(HyperliquidWithdrawalRecord)
    case accountSetup(UnifiedAccountSetup)
    case leverage(HyperliquidLeverageUpdate)

    private enum CodingKeys: String, CodingKey { case kind, source, consent, observation, attestation, forwarding, order, orderFills, withdrawal, accountSetup, leverage }
    private enum Kind: String, Codable { case source, consent, observation, attestation, forwarding, order, orderFills, withdrawal, accountSetup, leverage }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if !container.contains(.kind) {
            // Source-only journals created before consent support retain their authenticated history.
            self = .source(try FundingJournalRecord(from: decoder))
        } else {
            switch try container.decode(Kind.self, forKey: .kind) {
            case .leverage: self = .leverage(try container.decode(HyperliquidLeverageUpdate.self, forKey: .leverage))
            case .accountSetup: self = .accountSetup(try container.decode(UnifiedAccountSetup.self, forKey: .accountSetup))
            case .orderFills: self = .orderFills(try container.decode(HyperliquidOrderFillBatch.self, forKey: .orderFills))
            case .withdrawal: self = .withdrawal(try container.decode(HyperliquidWithdrawalRecord.self, forKey: .withdrawal))
            case .order: self = .order(try container.decode(HyperliquidOrderRecord.self, forKey: .order))
            case .source: self = .source(try container.decode(FundingJournalRecord.self, forKey: .source))
            case .consent: self = .consent(try container.decode(FundingConsentRecord.self, forKey: .consent))
            case .observation: self = .observation(try container.decode(FundingSourceObservation.self, forKey: .observation))
            case .attestation: self = .attestation(try container.decode(CCTPAttestationObservation.self, forKey: .attestation))
            case .forwarding: self = .forwarding(try container.decode(CCTPForwardObservation.self, forKey: .forwarding))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leverage(let record):
            try container.encode(Kind.leverage, forKey: .kind)
            try container.encode(record, forKey: .leverage)
        case .accountSetup(let record):
            try container.encode(Kind.accountSetup, forKey: .kind)
            try container.encode(record, forKey: .accountSetup)
        case .orderFills(let batch):
            try container.encode(Kind.orderFills, forKey: .kind)
            try container.encode(batch, forKey: .orderFills)
        case .withdrawal(let record):
            try container.encode(Kind.withdrawal, forKey: .kind)
            try container.encode(record, forKey: .withdrawal)
        case .order(let record):
            try container.encode(Kind.order, forKey: .kind)
            try container.encode(record, forKey: .order)
        case .source(let record):
            try container.encode(Kind.source, forKey: .kind)
            try container.encode(record, forKey: .source)
        case .consent(let record):
            try container.encode(Kind.consent, forKey: .kind)
            try container.encode(record, forKey: .consent)
        case .observation(let observation):
            try container.encode(Kind.observation, forKey: .kind)
            try container.encode(observation, forKey: .observation)
        case .attestation(let observation):
            try container.encode(Kind.attestation, forKey: .kind)
            try container.encode(observation, forKey: .attestation)
        case .forwarding(let observation):
            try container.encode(Kind.forwarding, forKey: .kind)
            try container.encode(observation, forKey: .forwarding)
        }
    }
}

struct FundingJournalSnapshot {
    var leverages: [UUID: HyperliquidLeverageUpdate] = [:]
    var accountSetups: [UUID: UnifiedAccountSetup] = [:]
    var withdrawals: [UUID: HyperliquidWithdrawalRecord] = [:]
    var orders: [UUID: HyperliquidOrderRecord] = [:]
    var orderFills: [UUID: [UInt64: HyperliquidOrderFill]] = [:]
    var sources: [UUID: FundingJournalRecord] = [:]
    var consents: [UUID: FundingConsentRecord] = [:]
    var observations: [UUID: FundingSourceObservation] = [:]
    var attestations: [UUID: CCTPAttestationObservation] = [:]
    var verifiedAttestations: [UUID: CCTPAttestationObservation] = [:]
    var forwardings: [UUID: CCTPForwardObservation] = [:]

    mutating func apply(_ event: FundingJournalEvent) throws {
        switch event {
        case .leverage(let record):
            try record.validate(wallet: record.wallet)
            try checkHyperliquidReservation(id: record.id, owner: record.owner, nonce: record.nonce, at: record.createdAt)
            leverages[record.id] = record
        case .accountSetup(let record):
            try record.validate(wallet: record.wallet)
            try checkHyperliquidReservation(id: record.id, owner: record.owner, nonce: record.nonce, at: record.createdAt)
            accountSetups[record.id] = record
        case .orderFills(let batch): try applyOrderFills(batch)
        case .withdrawal(let record):
            try record.validate(after: withdrawals[record.id])
            if withdrawals[record.id] == nil {
                try checkHyperliquidReservation(id: record.id, owner: record.intent.owner,
                                               nonce: record.intent.nonce, at: record.updatedAt)
            } else if record.state == .signing {
                // A superseded review must not revive after wall-clock rollback.
                guard latestHyperliquidNonce(owner: record.intent.owner) == record.intent.nonce else {
                    throw FundingJournalError.conflict
                }
            }
            withdrawals[record.id] = record
        case .order(let record):
            try record.validate(after: orders[record.id])
            if orders[record.id] == nil {
                try checkHyperliquidReservation(id: record.id, owner: record.order.owner,
                                               nonce: record.order.nonce, at: record.updatedAt)
                let previous = orders.values.filter { $0.order.owner == record.order.owner }
                guard !previous.contains(where: { $0.order.cloid == record.order.cloid }) else {
                    throw FundingJournalError.conflict
                }
            }
            orders[record.id] = record
        case .forwarding(let observation):
            guard let record = sources[observation.intentID], let source = observations[observation.intentID],
                  let attestation = attestations[observation.intentID] else { throw FundingJournalError.invalidTransition }
            try observation.validate(.init(record: record, source: source, attestation: attestation,
                                           previous: forwardings[observation.intentID]))
            forwardings[observation.intentID] = observation
        case .attestation(let observation):
            guard let record = sources[observation.intentID], let source = observations[observation.intentID] else {
                throw FundingJournalError.invalidTransition
            }
            try observation.validate(.init(record: record, source: source, previous: attestations[observation.intentID],
                                           previousVerified: verifiedAttestations[observation.intentID]))
            attestations[observation.intentID] = observation
            if observation.proof != nil { verifiedAttestations[observation.intentID] = observation }
        case .observation(let observation):
            guard let record = sources[observation.intentID] else { throw FundingJournalError.invalidTransition }
            try observation.validate(record: record, previous: observations[observation.intentID])
            observations[observation.intentID] = observation
        case .consent(let record):
            try record.validate(after: consents[record.id])
            if consents[record.id] == nil {
                guard sources[record.id] == nil, !reservesOwner(record.plan.owner),
                      !hasAuthorization(record.plan.owner, nonce: FundingHex.encode(record.plan.authorizationNonce)) else {
                    throw FundingJournalError.conflict
                }
            } else if sources[record.id] != nil { throw FundingJournalError.invalidTransition }
            consents[record.id] = record
        case .source(let record):
            try record.validate(after: sources[record.intent.id])
            if record.state == .notSubmitted {
                guard record.canFinishWithoutSubmission(observation: observations[record.intent.id]) else {
                    throw FundingJournalError.conflict
                }
            }
            if sources[record.intent.id] == nil {
                guard !reservesOwner(record.intent.owner, excludingConsent: record.intent.id),
                      !hasAuthorization(record.intent.owner, nonce: record.intent.authorizationNonce,
                                        excludingConsent: record.intent.id) else { throw FundingJournalError.conflict }
                if let consent = consents[record.intent.id] {
                    guard consent.state == .authorized, consent.plan.matches(record.intent),
                          consent.signature == record.intent.authorization else { throw FundingJournalError.conflict }
                }
            }
            sources[record.intent.id] = record
        }
    }

    private func reservesOwner(_ owner: String, excludingConsent: UUID? = nil) -> Bool {
        sources.values.contains { $0.intent.owner == owner && $0.reservesNonce }
            || consents.values.contains {
                $0.id != excludingConsent && sources[$0.id] == nil && $0.plan.owner == owner && $0.reservesOwner
            }
    }

    private func hasAuthorization(_ owner: String, nonce: String, excludingConsent: UUID? = nil) -> Bool {
        sources.values.contains { $0.intent.owner == owner && $0.intent.authorizationNonce == nonce }
            || consents.values.contains {
                $0.id != excludingConsent && $0.plan.owner == owner && FundingHex.encode($0.plan.authorizationNonce) == nonce
            }
    }
}
