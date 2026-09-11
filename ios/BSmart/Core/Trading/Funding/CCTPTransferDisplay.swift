import Foundation

struct CCTPTransferDisplay {
    enum Phase: Equatable { case amount, checking, authorization, authorizing, preflight, networkFee, signing, signed, submitting, recorded, recovery }
    struct Details {
        let owner: String
        let amount: UInt64
        let maximumTransferFee: UInt64
        let maximumNetworkFee: FundingQuantity?
        let checkedAt: Date
    }
    private(set) var phase = Phase.amount
    private(set) var details: Details?
    private(set) var entry: FundingHistoryEntry?
    private(set) var expiresAt: Date?

    init(_ state: CCTPDepositPreparationState) {
        switch state {
        case .idle: phase = .amount
        case .checkingAccount: phase = .checking
        case .reviewAuthorization(let consent):
            phase = .authorization
            if let quote = try? consent.plan.restored().quote {
                details = .init(owner: consent.plan.owner, amount: quote.amountUnits,
                    maximumTransferFee: quote.maximumFeeUnits, maximumNetworkFee: nil, checkedAt: consent.plan.createdAt)
            }
            expiresAt = consent.plan.feeReceivedAt.addingTimeInterval(CCTPFeeSchedule.lifetime)
        case .authorizing: phase = .authorizing
        case .preflighting: phase = .preflight
        case .reviewNetworkFee(let transaction):
            phase = .networkFee
            let source = transaction.preflight
            details = .init(owner: source.plan.owner, amount: source.plan.quote.amountUnits,
                maximumTransferFee: source.plan.quote.maximumFeeUnits, maximumNetworkFee: source.maximumNetworkFee,
                checkedAt: source.checkedAt)
            expiresAt = transaction.preflight.expiresAt
        case .signing: phase = .signing
        case .signatureRecorded(let record):
            phase = .signed; entry = try? .init(source: record)
            expiresAt = record.intent.expiresAt
            if let entry {
                details = .init(owner: entry.owner, amount: entry.amountUnits, maximumTransferFee: entry.maximumTransferFeeUnits,
                    maximumNetworkFee: entry.maximumNetworkFee, checkedAt: record.updatedAt)
            }
        case .checkingSubmission, .submitting: phase = .submitting
        case .submissionRecorded(let result):
            phase = .recorded; entry = result
            details = .init(owner: result.owner, amount: result.amountUnits,
                maximumTransferFee: result.maximumTransferFeeUnits, maximumNetworkFee: result.maximumNetworkFee,
                checkedAt: result.updatedAt)
        case .recoveryRequired: phase = .recovery
        }
    }

    func canConfirm(at date: Date) -> Bool {
        guard let expiresAt, let details, date >= details.checkedAt, date < expiresAt else { return false }
        return phase == .authorization || phase == .networkFee || phase == .signed
    }
}
