import Foundation

enum ManagedFundingNetwork: String, Codable, CaseIterable, Identifiable {
    case monad, arbitrum, base, ethereum, bnb
    var id: String { rawValue }
    var title: String {
        switch self {
        case .arbitrum: "Arbitrum One"
        case .monad: "Monad"
        case .base: "Base"
        case .ethereum: "Ethereum"
        case .bnb: "BNB Chain"
        }
    }
    var logoAsset: String {
        switch self {
        case .arbitrum: "FundingChain_Arbitrum"
        case .monad: "FundingChain_Monad"
        case .base: "FundingChain_Base"
        case .ethereum: "FundingChain_Ethereum"
        case .bnb: "FundingChain_BNB"
        }
    }
    var depositAsset: String { self == .bnb ? "Binance-Peg USDC (BEP-20)" : "native USDC" }
}

struct ManagedFundingAddress: Decodable {
    let network: ManagedFundingNetwork
    let recipient: String
    let refundAddress: String
    let depositAddress: String
    let reusable: Bool
    let createdAt: Date

    func validate(owner: String, network: ManagedFundingNetwork, now: Date = Date()) throws {
        guard recipient == owner, refundAddress == owner, self.network == network,
              reusable, depositAddress != owner,
              TradingWalletChallenge.validAddress(depositAddress),
              now.timeIntervalSince(createdAt) >= -30 else {
            throw ManagedFundingError.unavailable
        }
    }
}

struct ManagedFundingDeposit: Decodable, Identifiable {
    let id: String
    let status: String
    let createdAt: Date
    let amount: String?

    var title: String {
        switch status {
        case "waiting": "Awaiting deposit"
        case "depositing", "pending", "submitted": "Deposit processing"
        case "delayed": "Deposit delayed"
        case "success": "Delivered to trading account"
        case "refund": "Returned to your wallet"
        case "failure": "Deposit needs attention"
        default: "Deposit status unavailable"
        }
    }
}

enum ManagedFundingError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? { "Deposit service is temporarily unavailable. Try again later.".bSmartLocalized }
}
