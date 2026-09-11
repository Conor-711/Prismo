import Foundation

struct HyperliquidMarketLeverage: Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case cross, isolated }
    let mode: Mode
    let multiplier: Int
    let isolatedRawUSD: HyperliquidSignedDecimal?
}

struct HyperliquidSignedDecimal: Equatable, Sendable {
    let magnitude: HyperliquidOrderDecimal
    let isNegative: Bool

    init(_ value: String) throws {
        let negative = value.hasPrefix("-")
        magnitude = try .init(negative ? String(value.dropFirst()) : value)
        isNegative = negative && magnitude.isPositive
    }
}

struct HyperliquidTradeCapacity: Equatable, Sendable {
    let maximumSize: HyperliquidOrderDecimal
    let availableToTrade: HyperliquidOrderDecimal
}

struct HyperliquidActiveTradingData: Equatable, Sendable {
    let leverage: HyperliquidMarketLeverage
    let buy: HyperliquidTradeCapacity
    let sell: HyperliquidTradeCapacity
    let markPrice: HyperliquidOrderDecimal

    static func decode(_ data: Data, owner: String, market: HyperliquidExecutionMarket) throws -> Self {
        do {
            guard data.count <= 65_536 else { throw HyperliquidTradingCheckError.invalidResponse }
            let value = try JSONDecoder().decode(Active.self, from: data)
            guard value.user == owner, value.coin == market.coin,
                  value.maxTradeSzs.count == 2, value.availableToTrade.count == 2 else {
                throw HyperliquidTradingCheckError.invalidResponse
            }
            let leverage = try value.leverage.checked(market: market)
            let mark = try HyperliquidOrderDecimal(value.markPx)
            guard mark.isPositive else { throw HyperliquidTradingCheckError.invalidResponse }
            return try .init(leverage: leverage,
                buy: .init(maximumSize: .init(value.maxTradeSzs[0]), availableToTrade: .init(value.availableToTrade[0])),
                sell: .init(maximumSize: .init(value.maxTradeSzs[1]), availableToTrade: .init(value.availableToTrade[1])),
                markPrice: mark)
        } catch { throw HyperliquidTradingCheckError.invalidResponse }
    }

    private struct Active: Decodable {
        let user, coin, markPx: String
        let leverage: HyperliquidLeverageDTO
        let maxTradeSzs, availableToTrade: [String]
    }
}

struct HyperliquidLeverageDTO: Decodable {
    let type: HyperliquidMarketLeverage.Mode
    let value: Int
    let rawUsd: String?

    func checked(market: HyperliquidExecutionMarket) throws -> HyperliquidMarketLeverage {
        guard value > 0, value <= market.maximumLeverage, !market.isolatedOnly || type == .isolated else {
            throw HyperliquidTradingCheckError.invalidResponse
        }
        switch type {
        case .cross:
            guard rawUsd == nil else { throw HyperliquidTradingCheckError.invalidResponse }
            return .init(mode: type, multiplier: value, isolatedRawUSD: nil)
        case .isolated:
            guard let rawUsd else { throw HyperliquidTradingCheckError.invalidResponse }
            return try .init(mode: type, multiplier: value, isolatedRawUSD: .init(rawUsd))
        }
    }
}
