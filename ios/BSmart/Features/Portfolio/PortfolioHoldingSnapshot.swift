import Foundation

struct PortfolioHoldingSnapshot {
    let symbol: String
    let quantity: Double
    let price: Double?
    let averageCost: Double?
    let value: Double?
    let gain: Double?
    let gainPercent: Double?
    let leverage: Int?
    let side: PaperTradeSide?

    init(external position: PortfolioPosition) {
        symbol = position.ticker
        quantity = position.shares
        let mark = Self.positive(position.currentPrice)
        let cost = Self.positive(position.averageCost)
        price = mark
        averageCost = cost
        let shares = Self.positive(position.shares)
        value = shares.flatMap { size in mark.map { size * $0 } }
        gain = shares.flatMap { size in
            mark.flatMap { price in cost.map { size * (price - $0) } }
        }
        gainPercent = shares.flatMap { _ in cost.flatMap { entry in mark.map { ($0 - entry) / entry } } }
        leverage = nil
        side = nil
    }

    init(inApp position: PaperTradingPosition) {
        symbol = position.symbol
        quantity = position.size
        price = Self.positive(position.lastMarkPrice)
        averageCost = Self.positive(position.entryPrice)
        value = position.notional
        gain = position.unrealizedPnL
        gainPercent = position.isolatedMargin > 0 ? position.returnOnMargin : nil
        leverage = position.leverage
        side = position.side
    }

    private static func positive(_ value: Double) -> Double? {
        value.isFinite && value > 0 ? value : nil
    }
}
