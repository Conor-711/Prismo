import Foundation

struct HyperliquidTradingPosition: Equatable, Sendable {
    let quantity: HyperliquidSignedDecimal
    let leverage: HyperliquidMarketLeverage
}

struct HyperliquidTradingPositionState: Equatable, Sendable {
    let position: HyperliquidTradingPosition?
    let updatedAt: Date

    func validate(now: Date) throws {
        let age = now.timeIntervalSince(updatedAt)
        guard updatedAt.timeIntervalSince1970.isFinite, age.isFinite, age >= -2, age < 15 else {
            throw HyperliquidTradingCheckError.stale
        }
    }

    static func decode(_ data: Data, market: HyperliquidExecutionMarket, now: Date) throws -> Self {
        do {
            guard data.count <= 1_048_576 else { throw HyperliquidTradingCheckError.invalidResponse }
            let response = try JSONDecoder().decode(State.self, from: data)
            guard response.time > 0, response.time <= 9_007_199_254_740_991, response.assetPositions.count <= 10_000 else {
                throw HyperliquidTradingCheckError.invalidResponse
            }
            var coins = Set<String>()
            var position: HyperliquidTradingPosition?
            for row in response.assetPositions {
                let coin = row.position.coin
                let parts = coin.split(separator: ":", omittingEmptySubsequences: false)
                guard row.type == "oneWay", coins.insert(coin).inserted,
                      !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }),
                      market.dex.isEmpty ? parts.count == 1 : (parts.count == 2 && parts[0] == market.dex) else {
                    throw HyperliquidTradingCheckError.invalidResponse
                }
                guard coin == market.coin else { continue }
                let quantity = try HyperliquidSignedDecimal(row.position.szi)
                guard quantity.magnitude.isPositive else { continue }
                try quantity.magnitude.validateSize(decimals: market.sizeDecimals)
                position = try .init(quantity: quantity, leverage: row.position.leverage.checked(market: market))
            }
            let result = Self(position: position, updatedAt: Date(timeIntervalSince1970: Double(response.time) / 1000))
            try result.validate(now: now)
            return result
        } catch let error as HyperliquidTradingCheckError { throw error }
        catch { throw HyperliquidTradingCheckError.invalidResponse }
    }

    private struct State: Decodable { let time: UInt64; let assetPositions: [Row] }
    private struct Row: Decodable { let type: String; let position: Position }
    private struct Position: Decodable { let coin, szi: String; let leverage: HyperliquidLeverageDTO }
}
