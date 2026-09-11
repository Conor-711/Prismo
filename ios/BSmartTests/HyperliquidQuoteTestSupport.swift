import XCTest
@testable import BSmart

enum HyperliquidQuoteFixture {
    typealias F = HyperliquidTradingFixture
    static let recipient = "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf"
    static func market(scale: String? = "1.0", growth: String? = "enabled", native: Bool = false,
                       overrides: [String: Any] = [:]) throws -> HyperliquidExecutionMarket {
        let coin = native ? "NVDA" : F.coin
        var row: [String: Any] = ["name": coin, "szDecimals": 3, "maxLeverage": 20, "marginMode": "normal"]
        if let scale { row["deployerFeeScale"] = scale }
        if let growth { row["growthMode"] = growth }
        row.merge(overrides) { _, new in new }
        return try .resolve(perpDexs: HyperliquidOrderTestSupport.dexs,
            meta: F.data(["collateralToken": 0, "universe": [row]]), dex: native ? "" : "xyz", coin: coin)
    }
    static func fees(rate: String = "0.0004", discount: String = "0") throws -> Data {
        try F.data(["userCrossRate": rate, "activeReferralDiscount": discount,
                    "activeStakingDiscount": ["discount": "0.5"], "userAddRate": "-0.0001"])
    }
    static func book(bids: [[String: Any]] = [level("219", "1"), level("218", "2")],
                     asks: [[String: Any]] = [level("220", "1"), level("221", "2")],
                     at: Date = F.now, coin: String = F.coin) throws -> Data {
        try F.data(["coin": coin, "time": UInt64(at.timeIntervalSince1970 * 1000), "levels": [bids, asks]])
    }
    static func level(_ price: String, _ size: String) -> [String: Any] { ["px": price, "sz": size, "n": 1] }
    static func order(side: HyperliquidOrderIntent.Side = .buy, size: String = "2.5", price: String = "221",
                      builder: HyperliquidBuilderFee? = nil, market: HyperliquidExecutionMarket? = nil,
                      expiry: UInt64 = 1_789_084_830_001) throws -> HyperliquidOrderIntent {
        try .init(wallet: F.wallet, market: market ?? Self.market(), side: side, size: size, limitPrice: price,
            reduceOnly: false, cloid: "0x00000000000000000000000000000001", nonce: 1_789_084_800_001,
            expiresAfter: expiry, builderFee: builder)
    }
    static func snapshot(clock: TradingCheckClock = .init(), market: HyperliquidExecutionMarket? = nil) throws -> HyperliquidTradingSnapshot {
        let market = try market ?? Self.market()
        return try .init(accountID: F.wallet.accountID, owner: F.wallet.address, market: market, mode: .unifiedAccount,
            active: .decode(F.active(), owner: F.wallet.address, market: market),
            positions: .decode(F.positions(), market: market, now: clock.now),
            requestedAt: clock.now, checkedAt: clock.now, requestedContinuousAt: clock.instant, checkedContinuousAt: clock.instant)
    }
    static func exact(_ value: String) throws -> HyperliquidExactValue { try .init(.init(value)) }
}
