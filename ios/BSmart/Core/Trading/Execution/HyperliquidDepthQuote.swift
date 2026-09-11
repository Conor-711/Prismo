import Foundation

struct HyperliquidDepthQuote: Sendable {
    let quotedSize: HyperliquidExactValue
    let uncoveredSize: HyperliquidExactValue
    let notional: HyperliquidExactValue
    let averagePrice: HyperliquidExactValue
    let impactBasisPoints: HyperliquidExactValue
    let estimatedTakerFee: HyperliquidExactValue
    let estimatedBuilderFee: HyperliquidExactValue
    let estimatedTotalFee: HyperliquidExactValue
    let takerRate: HyperliquidExactValue
    let levelsUsed: Int
    var fullyCovered: Bool { !uncoveredSize.isPositive }

    static func calculate(order: HyperliquidOrderIntent, book: HyperliquidOrderBook,
                          fees: HyperliquidTakerFees, now: Date) throws -> Self {
        try book.validate(now: now)
        guard order.market == book.market, order.owner == fees.owner else { throw HyperliquidTradingCheckError.accountChanged }
        let levels = order.side == .buy ? book.asks : book.bids
        guard let best = levels.first else { throw HyperliquidQuoteError.noLiquidity }
        var remaining = HyperliquidExactValue(order.size), notional = HyperliquidExactValue(0), used = 0
        for level in levels {
            guard remaining.isPositive else { break }
            guard order.side == .buy ? level.price <= order.limitPrice : level.price >= order.limitPrice else { break }
            let taken = min(remaining, HyperliquidExactValue(level.size))
            notional = try notional.adding(taken.multiplied(by: .init(level.price)))
            remaining = try remaining.subtracting(taken)
            used += 1
        }
        let filled = try HyperliquidExactValue(order.size).subtracting(remaining)
        guard filled.isPositive else { throw HyperliquidQuoteError.noLiquidity }
        let average = try notional.divided(by: filled), bestPrice = HyperliquidExactValue(best.price)
        let impact = try order.side == .buy ? average.subtracting(bestPrice) : bestPrice.subtracting(average)
        let rate = try fees.rate(market: order.market)
        let venueFee = try notional.multiplied(by: rate)
        let builderFee = try notional.multiplied(by: order.builderFee?.rate ?? .init(0))
        return try .init(quotedSize: filled, uncoveredSize: remaining, notional: notional,
            averagePrice: average, impactBasisPoints: impact.divided(by: bestPrice).multiplied(by: .init(10_000)),
            estimatedTakerFee: venueFee, estimatedBuilderFee: builderFee,
            estimatedTotalFee: venueFee.adding(builderFee), takerRate: rate, levelsUsed: used)
    }
}
