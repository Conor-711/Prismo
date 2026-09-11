import Foundation

struct HyperliquidOrderBook: Sendable {
    struct Level: Sendable {
        let price: HyperliquidOrderDecimal
        let size: HyperliquidOrderDecimal
    }
    let market: HyperliquidExecutionMarket
    let updatedAt: Date
    let bids: [Level]
    let asks: [Level]

    static func decode(_ data: Data, market: HyperliquidExecutionMarket, now: Date) throws -> Self {
        do {
            guard data.count <= 65_536 else { throw HyperliquidQuoteError.invalidBook }
            let value = try JSONDecoder().decode(Response.self, from: data)
            guard value.coin == market.coin, value.time > 0, value.time <= 9_007_199_254_740_991,
                  value.levels.count == 2, value.levels.allSatisfy({ $0.count <= 20 }) else { throw HyperliquidQuoteError.invalidBook }
            let bids = try levels(value.levels[0], market: market, descending: true)
            let asks = try levels(value.levels[1], market: market, descending: false)
            if let bid = bids.first, let ask = asks.first {
                guard bid.price < ask.price else { throw HyperliquidQuoteError.invalidBook }
            }
            let result = Self(market: market, updatedAt: Date(timeIntervalSince1970: Double(value.time) / 1000), bids: bids, asks: asks)
            try result.validate(now: now)
            return result
        } catch let error as HyperliquidQuoteError { throw error }
        catch { throw HyperliquidQuoteError.invalidBook }
    }

    func validate(now: Date) throws {
        let age = now.timeIntervalSince(updatedAt)
        guard age.isFinite, age >= -2, age < 5 else { throw HyperliquidQuoteError.stale }
    }

    private static func levels(_ rows: [Row], market: HyperliquidExecutionMarket, descending: Bool) throws -> [Level] {
        var result: [Level] = []
        for row in rows {
            guard row.n > 0, row.n <= 9_007_199_254_740_991 else { throw HyperliquidQuoteError.invalidBook }
            let price = try HyperliquidOrderDecimal(row.px), size = try HyperliquidOrderDecimal(row.sz)
            try price.validatePrice(sizeDecimals: market.sizeDecimals)
            try size.validateSize(decimals: market.sizeDecimals)
            if let previous = result.last {
                guard descending ? price < previous.price : previous.price < price else { throw HyperliquidQuoteError.invalidBook }
            }
            result.append(.init(price: price, size: size))
        }
        return result
    }

    private struct Response: Decodable { let coin: String; let time: UInt64; let levels: [[Row]] }
    private struct Row: Decodable { let px, sz: String; let n: UInt64 }
}
