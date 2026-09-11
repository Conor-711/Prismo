import Foundation

enum HyperliquidLiveOrderError: Error, LocalizedError {
    case unavailable, invalidAmount, insufficientBalance, changed, recoveryRequired, noPosition, invalidReduction
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Live trading is not open yet.".bSmartLocalized
        case .invalidAmount: return "Enter a valid order value of at least 10 USDC.".bSmartLocalized
        case .insufficientBalance: return "Insufficient trading balance including estimated fees.".bSmartLocalized
        case .changed: return "Market or account conditions changed. Review a new quote.".bSmartLocalized
        case .recoveryRequired: return "Check order history before placing another order.".bSmartLocalized
        case .noPosition: return "There is no open position in this market to reduce.".bSmartLocalized
        case .invalidReduction: return "This reduction is smaller than the market's quantity step. Choose a larger percentage.".bSmartLocalized
        }
    }
}

enum HyperliquidMarketOrderPlan {
    static func order(notional: String, side: HyperliquidOrderIntent.Side, slippageBPS: UInt64,
                      wallet: DeviceWalletSummary, snapshot: HyperliquidTradingSnapshot,
                      book: HyperliquidOrderBook, nonce: UInt64) throws -> HyperliquidOrderIntent {
        let amount = try HyperliquidOrderDecimal(notional)
        guard amount.scale <= 6, amount >= (try HyperliquidOrderDecimal("10")), (10...100).contains(slippageBPS),
              snapshot.market == book.market else { throw HyperliquidLiveOrderError.invalidAmount }
        guard let best = (side == .buy ? book.asks : book.bids).first else { throw HyperliquidQuoteError.noLiquidity }
        let size = try HyperliquidExactValue(amount).divided(by: .init(best.price))
            .rounded(decimalPlaces: snapshot.market.sizeDecimals, up: false)
        guard try HyperliquidExactValue(size).multiplied(by: .init(best.price)) >= HyperliquidExactValue(10) else {
            throw HyperliquidLiveOrderError.invalidAmount
        }
        let limit = try limitPrice(side: side, slippageBPS: slippageBPS, book: book)
        guard nonce > 0, nonce <= 9_007_199_254_740_991 - 60_000 else { throw HyperliquidExecutionError.invalidIntent }
        return try .init(wallet: wallet, market: snapshot.market, side: side, size: size.wire, limitPrice: limit.wire,
                         reduceOnly: false, cloid: HyperliquidOrderIntent.randomCloid(), nonce: nonce, expiresAfter: nonce + 60_000)
    }

    static func reduction(percent: Int, slippageBPS: UInt64, wallet: DeviceWalletSummary,
                          snapshot: HyperliquidTradingSnapshot, book: HyperliquidOrderBook,
                          nonce: UInt64) throws -> HyperliquidOrderIntent {
        guard (1...100).contains(percent), snapshot.market == book.market,
              nonce > 0, nonce <= 9_007_199_254_740_991 - 60_000 else { throw HyperliquidExecutionError.invalidIntent }
        guard let position = snapshot.position else { throw HyperliquidLiveOrderError.noPosition }
        let side: HyperliquidOrderIntent.Side = position.quantity.isNegative ? .buy : .sell
        // Full close preserves the exchange quantity; partial reductions round down, never up.
        let size = try percent == 100 ? position.quantity.magnitude : HyperliquidExactValue(position.quantity.magnitude)
            .multiplied(by: .init(UInt64(percent))).divided(by: .init(100))
            .rounded(decimalPlaces: snapshot.market.sizeDecimals, up: false)
        guard size.isPositive, size <= position.quantity.magnitude else { throw HyperliquidLiveOrderError.invalidReduction }
        let limit = try limitPrice(side: side, slippageBPS: slippageBPS, book: book)
        return try .init(wallet: wallet, market: snapshot.market, side: side, size: size.wire, limitPrice: limit.wire,
                         reduceOnly: true, cloid: HyperliquidOrderIntent.randomCloid(), nonce: nonce, expiresAfter: nonce + 60_000)
    }

    private static func limitPrice(side: HyperliquidOrderIntent.Side, slippageBPS: UInt64,
                                   book: HyperliquidOrderBook) throws -> HyperliquidOrderDecimal {
        guard (10...100).contains(slippageBPS) else { throw HyperliquidExecutionError.invalidIntent }
        guard let best = (side == .buy ? book.asks : book.bids).first else { throw HyperliquidQuoteError.noLiquidity }
        let numerator: UInt64 = side == .buy ? 10_000 + slippageBPS : 10_000 - slippageBPS
        let raw = try HyperliquidExactValue(best.price).multiplied(by: .init(numerator)).divided(by: .init(10_000))
        return try roundedPrice(raw, sizeDecimals: book.market.sizeDecimals, up: side == .sell)
    }

    static func roundedPrice(_ value: HyperliquidExactValue, sizeDecimals: Int, up: Bool) throws -> HyperliquidOrderDecimal {
        for places in stride(from: 6 - sizeDecimals, through: 0, by: -1) {
            let price = try value.rounded(decimalPlaces: places, up: up)
            if (try? price.validatePrice(sizeDecimals: sizeDecimals)) != nil { return price }
        }
        throw HyperliquidExecutionError.invalidPrecision
    }

    static func checkFunds(_ preview: HyperliquidOrderPreview) throws {
        let order = preview.order
        if order.reduceOnly {
            guard preview.quote.quotedSize.isPositive else { throw HyperliquidQuoteError.noLiquidity }
            return
        }
        guard preview.quote.fullyCovered else { throw HyperliquidQuoteError.noLiquidity }
        let capacity = order.side == .buy ? preview.account.active.buy : preview.account.active.sell
        let reference = max(order.limitPrice, preview.account.active.markPrice)
        let notional = try HyperliquidExactValue(order.size).multiplied(by: .init(reference))
        let margin = try notional.divided(by: .init(UInt64(preview.reviewedLeverage)))
        let fee = try notional.multiplied(by: preview.quote.takerRate)
        guard try margin.adding(max(fee, preview.quote.estimatedTotalFee)) <= HyperliquidExactValue(capacity.availableToTrade) else {
            throw HyperliquidLiveOrderError.insufficientBalance
        }
    }
}
