import Foundation

// Protocol data only. Construction never grants access to the device key or network.
struct HyperliquidWithdrawalIntent: Equatable, Sendable {
    enum Source: String, CaseIterable, Sendable { case perps = "", spot = "spot" }
    static let signatureChainID: UInt64 = 42161
    static let destinationDomain: UInt32 = 3
    static let gasLimit: UInt64 = 200_000
    let accountID: UUID
    let owner: String
    let recipient: String
    let amount: HyperliquidOrderDecimal
    let amountUnits: FundingQuantity
    let source: Source
    let nonce: UInt64

    init(wallet: DeviceWalletSummary, recipient: String, amount: String, source: Source, nonce: UInt64) throws {
        let recipient = try Self.recipient(recipient)
        let value = try HyperliquidOrderDecimal(amount)
        guard wallet.canAuthorizeTransactions, TradingWalletChallenge.validAddress(wallet.address),
              wallet.address == wallet.address.lowercased(),
              wallet.address != "0x" + String(repeating: "0", count: 40),
              value.isPositive, value.scale <= 6, nonce > 0, nonce < 9_007_199_254_740_991 else {
            throw HyperliquidWithdrawalError.invalidIntent
        }
        let units = try FundingQuantity(ArbitrumDepositPolicy.units(value.wire))
        // HyperCore stores USDC at eight decimals in a uint64, CCTP at six.
        guard try units.multiplied(by: FundingQuantity(100)).uint64 != nil else {
            throw HyperliquidWithdrawalError.invalidIntent
        }
        accountID = wallet.accountID; owner = wallet.address; self.recipient = recipient
        self.amount = value; amountUnits = units; self.source = source; self.nonce = nonce
    }

    func validate(wallet: DeviceWalletSummary) throws {
        guard wallet.canAuthorizeTransactions, accountID == wallet.accountID, owner == wallet.address else {
            throw HyperliquidWithdrawalError.invalidIntent
        }
    }

    private static func recipient(_ input: String) throws -> String {
        let lower = input.lowercased()
        let checksum = try WalletReceiveAddress(owner: lower).value
        guard input.hasPrefix("0x"), input == lower || input == checksum || input == "0x" + lower.dropFirst(2).uppercased(),
              ![CCTPArbitrumRoute.coreDepositWallet, CCTPArbitrumRoute.coreTokenSystemAddress,
                CCTPArbitrumRoute.destinationUSDC, CCTPArbitrumRoute.extensionAddress,
                CCTPArbitrumRoute.forwarderAddress, ArbitrumDepositPolicy.nativeUSDC.lowercased()].contains(lower) else {
            throw HyperliquidWithdrawalError.invalidIntent
        }
        return lower
    }
}

enum HyperliquidWithdrawalError: Error, Equatable {
    case invalidIntent, invalidSignature, invalidResponse, unavailable, stale, routeChanged
    case insufficientBalance, unsupportedBalance, belowFee, recoveryRequired
}
