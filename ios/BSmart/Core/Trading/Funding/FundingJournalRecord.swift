import Foundation

struct FundingJournalIntent: Codable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let owner: String
    let chainID: Int
    let authorizationNonce: String
    let nonce: String
    let amountUnits: UInt64
    let maximumCCTPFeeUnits: UInt64
    let protocolRateMillionths: UInt64
    let forwardingFeeUnits: UInt64
    let feeReceivedAt: Date
    let planCreatedAt: Date
    let authorization: String
    let gasLimit: String
    let maximumFeePerGas: String
    let maximumNetworkFee: String
    let callData: Data
    let signingHash: Data
    let preparedAt: Date
    let expiresAt: Date
    let authorizationExpiresAt: Date

    init(id: UUID, transaction: CCTPSourceTransaction) {
        let source = transaction.preflight
        self.id = id
        accountID = source.plan.accountID
        owner = source.plan.owner
        chainID = ArbitrumDepositPolicy.chainID
        authorizationNonce = FundingHex.encode(source.plan.authorizationNonce)
        nonce = source.nonce.rpc
        amountUnits = source.plan.quote.amountUnits
        maximumCCTPFeeUnits = source.plan.quote.maximumFeeUnits
        protocolRateMillionths = source.plan.quote.schedule.protocolRateMillionths
        forwardingFeeUnits = source.plan.quote.schedule.forwardingFeeUnits
        feeReceivedAt = source.plan.quote.schedule.receivedAt
        planCreatedAt = source.plan.createdAt
        authorization = source.authorization
        gasLimit = source.gasLimit.rpc
        maximumFeePerGas = source.maximumFeePerGas.rpc
        maximumNetworkFee = source.maximumNetworkFee.rpc
        callData = source.callData
        signingHash = transaction.signingHash
        preparedAt = source.checkedAt
        expiresAt = source.expiresAt
        authorizationExpiresAt = Date(timeIntervalSince1970: TimeInterval(source.plan.validBefore))
    }

    func validate() throws {
        guard chainID == ArbitrumDepositPolicy.chainID, TradingWalletChallenge.validAddress(owner),
              FundingHex.decode(authorizationNonce)?.count == 32, signingHash.count == 32, callData.count == 580,
              amountUnits <= ArbitrumDepositPolicy.maximumBurnUnits, maximumCCTPFeeUnits < amountUnits,
              amountUnits - maximumCCTPFeeUnits >= CCTPDepositQuote.minimumResidualUnits,
              authorization.utf8.count == 132, Self.validDate(feeReceivedAt), Self.validDate(planCreatedAt),
              feeReceivedAt <= planCreatedAt, planCreatedAt <= preparedAt,
              Self.validDate(preparedAt), Self.validDate(expiresAt), Self.validDate(authorizationExpiresAt),
              expiresAt > preparedAt, expiresAt.timeIntervalSince(preparedAt) <= 30,
              authorizationExpiresAt > expiresAt, authorizationExpiresAt.timeIntervalSince(preparedAt) <= 300 else {
            throw FundingJournalError.integrity
        }
        let limit = try FundingQuantity(rpc: gasLimit)
        let price = try FundingQuantity(rpc: maximumFeePerGas)
        let fee = try FundingQuantity(rpc: maximumNetworkFee)
        guard try FundingQuantity(rpc: nonce).uint64 != nil,
              limit >= FundingQuantity(21_000), limit <= FundingQuantity(5_000_000), price > FundingQuantity(0),
              try limit.multiplied(by: price) == fee, fee <= FundingQuantity(10_000_000_000_000_000) else {
            throw FundingJournalError.integrity
        }
    }

    func require(wallet: DeviceWalletSummary, now: Date? = nil) throws {
        guard wallet.accountID == accountID, wallet.address == owner else { throw FundingJournalError.conflict }
        if let now {
            guard wallet.canAuthorizeTransactions, now >= preparedAt, now < expiresAt else { throw FundingJournalError.expired }
        }
    }

    static func validDate(_ value: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        return seconds.isFinite && seconds >= 0 && seconds < 4_102_444_800
    }
}

struct FundingJournalRecord: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case prepared, signing, signed, submitting, submitted, uncertain, cancelled, notSubmitted
    }
    struct Signed: Codable, Equatable, Sendable {
        let signature: Data
        let raw: Data
        let hash: String
    }
    let intent: FundingJournalIntent
    var state: State
    var signed: Signed?
    var updatedAt: Date

    var needsReconciliation: Bool { [.signing, .signed, .submitting, .submitted, .uncertain].contains(state) }
    var reservesNonce: Bool { ![.cancelled, .notSubmitted].contains(state) }

    func canFinishWithoutSubmission(observation: FundingSourceObservation?) -> Bool {
        guard [.signed, .notSubmitted].contains(state) else { return false }
        guard let observation else { return true }
        return !observation.transactionPresent && observation.receipt == nil && observation.priorReceiptBlock == nil
            && !observation.authorizationUsed && observation.latestNonce == intent.nonce && observation.pendingNonce == intent.nonce
    }

    func validate(after previous: Self?) throws {
        try intent.validate()
        guard FundingJournalIntent.validDate(updatedAt), updatedAt >= intent.preparedAt else { throw FundingJournalError.integrity }
        let needsSignature = [.signed, .submitting, .submitted, .uncertain, .notSubmitted].contains(state)
        guard (signed != nil) == needsSignature else { throw FundingJournalError.integrity }
        if let signed {
            guard signed.signature.count == 65, signed.raw.first == 2, (100...1_024).contains(signed.raw.count),
                  FundingHex.decode(signed.hash)?.count == 32 else { throw FundingJournalError.integrity }
        }
        if let previous {
            guard previous.intent == intent, updatedAt >= previous.updatedAt,
                  previous.signed == nil || previous.signed == signed else { throw FundingJournalError.integrity }
            let allowed: [State: Set<State>] = [
                .prepared: [.signing, .cancelled], .signing: [.signed], .signed: [.submitting, .notSubmitted],
                .submitting: [.submitted, .uncertain], .submitted: [.uncertain], .uncertain: [.submitted]
            ]
            guard allowed[previous.state]?.contains(state) == true else { throw FundingJournalError.integrity }
        } else if state != .prepared {
            throw FundingJournalError.integrity
        }
        try CCTPSourceTransaction.verifyStored(intent: intent, signed: signed)
    }
}

enum FundingJournalError: Error, LocalizedError, Equatable {
    case unavailable, integrity, conflict, invalidTransition, expired, capacity, busy

    var orderMessage: String {
        switch self {
        case .unavailable, .integrity, .capacity:
            return "Local order records could not be verified. Check order status before retrying.".bSmartLocalized
        case .busy:
            return "Another order operation is in progress. Try again shortly.".bSmartLocalized
        case .conflict, .invalidTransition:
            return "Check the previous order's status before placing another order.".bSmartLocalized
        case .expired:
            return "Order confirmation expired. Review a new quote.".bSmartLocalized
        }
    }

    var errorDescription: String? {
        switch self {
        case .unavailable, .integrity:
            return "Deposit history cannot be verified. Transfers are paused.".bSmartLocalized
        case .conflict:
            return "This wallet has an unresolved or different deposit. Check its status before continuing.".bSmartLocalized
        case .invalidTransition:
            return "This deposit needs to be checked before it can continue.".bSmartLocalized
        case .expired:
            return "Deposit confirmation expired. Review the details again.".bSmartLocalized
        case .capacity:
            return "Deposit history reached its safety limit. Transfers are paused.".bSmartLocalized
        case .busy:
            return "Another deposit operation is in progress. Try again shortly.".bSmartLocalized
        }
    }
}
