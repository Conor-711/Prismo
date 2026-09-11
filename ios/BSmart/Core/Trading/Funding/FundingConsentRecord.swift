import Foundation
import WalletCore

struct FundingConsentPlan: Codable, Equatable, Sendable {
    let routeVersion: Int
    let accountID: UUID
    let owner: String
    let amountUnits: UInt64
    let protocolRateMillionths: UInt64
    let forwardingFeeUnits: UInt64
    let feeReceivedAt: Date
    let createdAt: Date
    let authorizationNonce: Data
    let authorizationHash: Data

    init(_ plan: CCTPDepositPlan) throws {
        routeVersion = 1
        accountID = plan.accountID
        owner = plan.owner
        amountUnits = plan.quote.amountUnits
        protocolRateMillionths = plan.quote.schedule.protocolRateMillionths
        forwardingFeeUnits = plan.quote.schedule.forwardingFeeUnits
        feeReceivedAt = plan.quote.schedule.receivedAt
        createdAt = plan.createdAt
        authorizationNonce = plan.authorizationNonce
        let wallet = DeviceWalletSummary(accountID: accountID, address: owner, recoveryVerified: true)
        let json = try CCTPDepositCodec.authorizationJSON(plan: plan, wallet: wallet, now: createdAt)
        authorizationHash = EthereumAbi.encodeTyped(messageJson: json)
        _ = try restored()
    }

    func restored() throws -> CCTPDepositPlan {
        guard routeVersion == 1, FundingJournalIntent.validDate(createdAt),
              FundingJournalIntent.validDate(feeReceivedAt), authorizationHash.count == 32 else {
            throw FundingJournalError.integrity
        }
        let schedule = CCTPFeeSchedule(protocolRateMillionths: protocolRateMillionths,
                                      forwardingFeeUnits: forwardingFeeUnits, receivedAt: feeReceivedAt)
        let quote = try CCTPDepositQuote(amount: FundingQuantity(amountUnits).formatted(decimals: 6),
                                          schedule: schedule, now: createdAt)
        let wallet = DeviceWalletSummary(accountID: accountID, address: owner, recoveryVerified: true)
        let plan = try CCTPDepositPlan(wallet: wallet, quote: quote, now: createdAt, nonce: authorizationNonce)
        let json = try CCTPDepositCodec.authorizationJSON(plan: plan, wallet: wallet, now: createdAt)
        guard EthereumAbi.encodeTyped(messageJson: json) == authorizationHash else { throw FundingJournalError.integrity }
        return plan
    }

    func require(wallet: DeviceWalletSummary, now: Date? = nil) throws {
        guard wallet.accountID == accountID, wallet.address == owner else { throw FundingJournalError.conflict }
        if let now { try restored().validate(wallet: wallet, now: now) }
    }

    func matches(_ intent: FundingJournalIntent) -> Bool {
        accountID == intent.accountID && owner == intent.owner && amountUnits == intent.amountUnits
            && protocolRateMillionths == intent.protocolRateMillionths && forwardingFeeUnits == intent.forwardingFeeUnits
            && feeReceivedAt == intent.feeReceivedAt && createdAt == intent.planCreatedAt
            && FundingHex.encode(authorizationNonce) == intent.authorizationNonce
    }
}

struct FundingConsentRecord: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case review, authorizing, authorized, cancelled }
    let id: UUID
    let plan: FundingConsentPlan
    var state: State
    var signature: String?
    var updatedAt: Date
    var reservesOwner: Bool { state != .cancelled }

    func validate(after previous: Self?) throws {
        let restored = try plan.restored()
        guard FundingJournalIntent.validDate(updatedAt), updatedAt >= plan.createdAt,
              (signature != nil) == (state == .authorized) else { throw FundingJournalError.integrity }
        if let signature {
            let wallet = DeviceWalletSummary(accountID: plan.accountID, address: plan.owner, recoveryVerified: true)
            _ = try CCTPDepositCodec.callData(plan: restored, wallet: wallet, authorization: signature, now: plan.createdAt)
        }
        if let previous {
            guard previous.id == id, previous.plan == plan, updatedAt >= previous.updatedAt,
                  (previous.state == .review && [.authorizing, .cancelled].contains(state))
                    || (previous.state == .authorizing && state == .authorized) else { throw FundingJournalError.integrity }
        } else if state != .review { throw FundingJournalError.integrity }
    }
}
