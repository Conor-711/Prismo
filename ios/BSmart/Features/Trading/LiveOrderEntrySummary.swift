import Foundation

// Estimates for the restored composer, never authority to sign or spend.
struct LiveOrderEntrySummary {
    let account: HyperliquidTradingSnapshot
    let feeRate: HyperliquidExactValue
    let side: HyperliquidOrderIntent.Side
    var selectedLeverage: Int? = nil

    var capacity: HyperliquidTradeCapacity { side == .buy ? account.active.buy : account.active.sell }
    var leverage: Int { selectedLeverage ?? account.active.leverage.multiplier }

    var needsSharedBalance: Bool {
        !account.market.dex.isEmpty && !account.mode.usesSharedBalance && !capacity.availableToTrade.isPositive
    }

    func shouldOfferDeposit(balance: HyperCoreBalanceSnapshot?) -> Bool {
        guard let balance, balance.accountID == account.accountID, balance.owner == account.owner,
              balance.mode == account.mode,
              !account.active.buy.availableToTrade.isPositive,
              !account.active.sell.availableToTrade.isPositive else { return false }
        return balance.usdc.units == FundingQuantity(0)
            && (balance.perps?.equity.units ?? FundingQuantity(0)) == FundingQuantity(0)
    }

    func openingIssue(margin: String) -> String? {
        guard let amount = try? HyperliquidOrderDecimal(margin), amount.isPositive else { return nil }
        guard let text = notional(margin: margin), let value = try? HyperliquidOrderDecimal(text),
              HyperliquidExactValue(value) >= HyperliquidExactValue(10) else {
            return "Minimum order value: 10 USDC".bSmartLocalized
        }
        guard let text = maximumMargin(), let maximum = try? HyperliquidOrderDecimal(text), amount <= maximum else {
            return "Insufficient available margin".bSmartLocalized
        }
        return nil
    }

    func reductionQuantity(percent: Int) -> String? {
        guard (1...100).contains(percent), let position = account.position else { return nil }
        if percent == 100 { return position.quantity.magnitude.wire }
        return try? HyperliquidExactValue(position.quantity.magnitude).multiplied(by: .init(UInt64(percent)))
            .divided(by: .init(100)).rounded(decimalPlaces: account.market.sizeDecimals, up: false).wire
    }

    func reductionNotional(percent: Int) -> String? {
        guard let size = reductionQuantity(percent: percent), let value = try? HyperliquidOrderDecimal(size) else { return nil }
        return try? HyperliquidExactValue(value).multiplied(by: .init(account.active.markPrice))
            .rounded(decimalPlaces: 6, up: false).wire
    }

    func notional(margin: String) -> String? {
        guard leverage > 0, let amount = try? HyperliquidOrderDecimal(margin) else { return nil }
        return try? HyperliquidExactValue(amount).multiplied(by: .init(UInt64(leverage)))
            .rounded(decimalPlaces: 6, up: false).wire
    }

    var balance: String {
        (try? HyperliquidExactValue(capacity.availableToTrade).rounded(decimalPlaces: 6, up: false).wire) ?? "--"
    }

    func maximumMargin() -> String? {
        guard leverage > 0 else { return nil }
        return try? HyperliquidExactValue(capacity.availableToTrade)
            .divided(by: HyperliquidExactValue(1).adding(feeRate.multiplied(by: .init(UInt64(leverage)))))
            .divided(by: HyperliquidExactValue(10_050).divided(by: .init(10_000)))
            .rounded(decimalPlaces: 6, up: false).wire
    }

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
