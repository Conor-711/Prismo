import Foundation
import WalletCore

enum CCTPSourceMessage {
    static let topic = FundingHex.encode(Hash.keccak256(data: Data("MessageSent(bytes)".utf8)))

    static func decodeEvent(_ data: Data, intent: FundingJournalIntent) throws -> Data {
        // ABI bytes: offset, length, payload and zero padding. One fixed-route message, no trailing bytes.
        guard data.count == 512,
              try word(data, 0) == FundingQuantity(32), try word(data, 32) == FundingQuantity(432),
              data.suffix(16).allSatisfy({ $0 == 0 }) else { throw FundingObservationError.invalidEvidence }
        let message = Data(data[64..<496])
        try validate(message, intent: intent)
        return message
    }

    static func validate(_ message: Data, intent: FundingJournalIntent) throws {
        guard message.count == 432 else { throw FundingObservationError.invalidEvidence }
        let plan = try restoredPlan(intent)
        // Circle fills nonce/finality/fee/expiration when attesting, not in this source-chain event.
        guard uint32(message, 0) == 1, uint32(message, 4) == CCTPArbitrumRoute.sourceDomain,
              uint32(message, 8) == CCTPArbitrumRoute.destinationDomain,
              message[12..<44].allSatisfy({ $0 == 0 }),
              try address(message, 44) == CCTPArbitrumRoute.tokenMessenger,
              try address(message, 76) == CCTPArbitrumRoute.tokenMessenger,
              try address(message, 108) == CCTPArbitrumRoute.forwarderAddress,
              uint32(message, 140) == CCTPArbitrumRoute.finalityThreshold, uint32(message, 144) == 0,
              uint32(message, 148) == 1,
              try address(message, 152) == ArbitrumDepositPolicy.nativeUSDC.lowercased(),
              try address(message, 184) == CCTPArbitrumRoute.forwarderAddress,
              try word(message, 216) == FundingQuantity(intent.amountUnits),
              try address(message, 248) == CCTPArbitrumRoute.extensionAddress,
              try word(message, 280) == FundingQuantity(intent.maximumCCTPFeeUnits),
              try word(message, 312) == FundingQuantity(0), try word(message, 344) == FundingQuantity(0),
              Data(message[376..<432]) == plan.hookData else { throw FundingObservationError.invalidEvidence }
    }

    private static func restoredPlan(_ intent: FundingJournalIntent) throws -> CCTPDepositPlan {
        let wallet = DeviceWalletSummary(accountID: intent.accountID, address: intent.owner, recoveryVerified: true)
        let schedule = CCTPFeeSchedule(protocolRateMillionths: intent.protocolRateMillionths,
                                      forwardingFeeUnits: intent.forwardingFeeUnits, receivedAt: intent.feeReceivedAt)
        let quote = try CCTPDepositQuote(amount: FundingQuantity(intent.amountUnits).formatted(decimals: 6),
                                       schedule: schedule, now: intent.planCreatedAt)
        guard let nonce = FundingHex.decode(intent.authorizationNonce) else { throw FundingObservationError.invalidEvidence }
        return try .init(wallet: wallet, quote: quote, now: intent.planCreatedAt, nonce: nonce)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        data[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private static func word(_ data: Data, _ offset: Int) throws -> FundingQuantity {
        try FundingQuantity(abi: FundingHex.encode(Data(data[offset..<offset + 32])))
    }
    private static func address(_ data: Data, _ offset: Int) throws -> String {
        guard data[offset..<offset + 12].allSatisfy({ $0 == 0 }) else { throw FundingObservationError.invalidEvidence }
        return FundingHex.encode(Data(data[offset + 12..<offset + 32]))
    }
}
