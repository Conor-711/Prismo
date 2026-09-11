import Foundation
import Security

// A canonical order is NOT a signing permit. Live preflight and a durable journal must precede signing.
struct HyperliquidOrderIntent: Equatable, Sendable {
    enum Side: String, Codable, Sendable { case buy, sell }

    let accountID: UUID
    let owner: String
    let market: HyperliquidExecutionMarket
    let side: Side
    let size: HyperliquidOrderDecimal
    let limitPrice: HyperliquidOrderDecimal
    let reduceOnly: Bool
    let cloid: String
    let nonce: UInt64
    let expiresAfter: UInt64
    let builderFee: HyperliquidBuilderFee?

    init(wallet: DeviceWalletSummary, market: HyperliquidExecutionMarket, side: Side,
         size: String, limitPrice: String, reduceOnly: Bool, cloid: String,
         nonce: UInt64, expiresAfter: UInt64, builderFee: HyperliquidBuilderFee? = nil) throws {
        try market.validatePerpetual()
        guard wallet.canAuthorizeTransactions,
              wallet.address.count == 42, let ownerBytes = FundingHex.decode(wallet.address),
              ownerBytes.count == 20, ownerBytes.contains(where: { $0 != 0 }),
              cloid.count == 34, let cloidBytes = FundingHex.decode(cloid),
              cloidBytes.count == 16, cloidBytes.contains(where: { $0 != 0 }),
              nonce > 0, nonce < expiresAfter, expiresAfter <= 9_007_199_254_740_991,
              expiresAfter - nonce <= 60_000 else { throw HyperliquidExecutionError.invalidIntent }
        let size = try HyperliquidOrderDecimal(size)
        let price = try HyperliquidOrderDecimal(limitPrice)
        try size.validateSize(decimals: market.sizeDecimals)
        try price.validatePrice(sizeDecimals: market.sizeDecimals)
        accountID = wallet.accountID
        owner = wallet.address
        self.market = market
        self.side = side
        self.size = size
        self.limitPrice = price
        self.reduceOnly = reduceOnly
        self.cloid = cloid
        self.nonce = nonce
        self.expiresAfter = expiresAfter
        self.builderFee = builderFee
    }

    static func randomCloid() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess,
              bytes.contains(where: { $0 != 0 }) else { throw HyperliquidExecutionError.invalidIntent }
        return FundingHex.encode(Data(bytes))
    }
}
