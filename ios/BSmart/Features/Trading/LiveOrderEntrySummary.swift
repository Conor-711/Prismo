import Foundation

// Estimates for the restored composer, never authority to sign or spend.
struct LiveOrderEntrySummary {
    let account: HyperliquidTradingSnapshot
    let feeRate: HyperliquidExactValue
    let side: HyperliquidOrderIntent.Side

    var capacity: HyperliquidTradeCapacity { side == .buy ? account.active.buy : account.active.sell }
    var leverage: Int { account.active.leverage.multiplier }

    func margin(notional: String) -> String? {
        guard let amount = try? HyperliquidOrderDecimal(notional) else { return nil }
        return try? HyperliquidExactValue(amount).divided(by: .init(UInt64(leverage)))
            .rounded(decimalPlaces: 2, up: true).wire
    }

    func fee(notional: String) -> String? {
        guard let amount = try? HyperliquidOrderDecimal(notional) else { return nil }
        return try? HyperliquidExactValue(amount).multiplied(by: feeRate).rounded(decimalPlaces: 4, up: true).wire
    }

    func maximumNotional(slippageBPS: UInt64) -> String? {
        // Reserve fees and slippage; the fresh book/size/collateral check remains authoritative.
        guard leverage > 0, (10...100).contains(slippageBPS) else { return nil }
        do {
            let perDollar = try HyperliquidExactValue(1).divided(by: .init(UInt64(leverage))).adding(feeRate)
            let byBalance = try HyperliquidExactValue(capacity.availableToTrade).divided(by: perDollar)
            let bySize = try HyperliquidExactValue(capacity.maximumSize).multiplied(by: .init(account.active.markPrice))
            let headroom = try HyperliquidExactValue(10_000 + slippageBPS).divided(by: .init(10_000))
            let maximum = try min(byBalance, bySize).divided(by: headroom)
            return try min(maximum, HyperliquidExactValue(HyperliquidOrderDecimal("99999999.99")))
                .rounded(decimalPlaces: 2, up: false).wire
        } catch { return nil }
    }
}
