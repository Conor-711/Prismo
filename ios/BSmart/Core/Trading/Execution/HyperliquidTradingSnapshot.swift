import Foundation

// Read-only constraints, not signing authorization or a fee-inclusive collateral reservation.
struct HyperliquidTradingSnapshot: Sendable {
    let accountID: UUID
    let owner: String
    let market: HyperliquidExecutionMarket
    let mode: HyperCoreAccountMode
    let active: HyperliquidActiveTradingData
    let positions: HyperliquidTradingPositionState
    let requestedAt: Date
    let checkedAt: Date
    let requestedContinuousAt: ContinuousClock.Instant
    let checkedContinuousAt: ContinuousClock.Instant

    var position: HyperliquidTradingPosition? { positions.position }
    var expiresAt: Date { min(requestedAt, positions.updatedAt).addingTimeInterval(15) }

    func validate(wallet: DeviceWalletSummary, now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        try market.validatePerpetual()
        guard wallet.canAuthorizeTransactions, wallet.accountID == accountID, wallet.address == owner,
              TradingWalletChallenge.validAddress(owner) else { throw HyperliquidTradingCheckError.accountChanged }
        guard market.collateralToken == 0 else { throw HyperliquidTradingCheckError.unsupportedCollateral }
        try positions.validate(now: now)
        let remainingAtCheck = expiresAt.timeIntervalSince(checkedAt)
        guard requestedAt.timeIntervalSince1970.isFinite, checkedAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite, requestedAt <= checkedAt, checkedAt <= now, now < expiresAt,
              requestedContinuousAt <= checkedContinuousAt, checkedContinuousAt <= continuousNow,
              requestedContinuousAt.duration(to: continuousNow) < .seconds(15),
              remainingAtCheck.isFinite, remainingAtCheck > 0,
              checkedContinuousAt.duration(to: continuousNow) < .seconds(remainingAtCheck) else {
            throw HyperliquidTradingCheckError.stale
        }
    }

    func checkConstraints(order: HyperliquidOrderIntent, wallet: DeviceWalletSummary,
                          reviewedLeverage: Int, reviewedMarginMode: HyperliquidMarketLeverage.Mode,
                          now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        try validate(wallet: wallet, now: now, continuousNow: continuousNow)
        guard order.accountID == accountID, order.owner == owner, order.market == market else {
            throw HyperliquidTradingCheckError.accountChanged
        }
        let nowMS = now.timeIntervalSince1970 * 1000
        guard nowMS >= 0, nowMS <= 9_007_199_254_740_991,
              Double(order.nonce) <= nowMS + 1000, Double(order.expiresAfter) > nowMS else {
            throw HyperliquidTradingCheckError.stale
        }
        guard reviewedLeverage == active.leverage.multiplier, reviewedMarginMode == active.leverage.mode else {
            throw HyperliquidTradingCheckError.leverageChanged
        }
        if order.reduceOnly {
            guard let position, position.quantity.isNegative == (order.side == .buy),
                  order.size <= position.quantity.magnitude else { throw HyperliquidTradingCheckError.invalidReduction }
        } else {
            let capacity = order.side == .buy ? active.buy : active.sell
            guard order.size <= capacity.maximumSize else { throw HyperliquidTradingCheckError.exceedsCapacity }
        }
    }
}
