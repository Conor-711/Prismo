import Foundation

struct HyperliquidPerpMarket: Identifiable, Codable, Hashable, Sendable {
    let coin: String
    let symbol: String
    let dex: String
    let dexDisplayName: String
    let sizeDecimals: Int
    let maxLeverage: Int
    let marginTableID: Int?
    let isIsolatedOnly: Bool
    let isDelisted: Bool
    let markPrice: Double
    let midPrice: Double?
    let oraclePrice: Double
    let previousDayPrice: Double
    let dayNotionalVolume: Double
    let openInterest: Double
    let fundingRate: Double
    let impactBidPrice: Double?
    let impactAskPrice: Double?
    let updatedAt: Date

    var id: String { coin }

    var dayChangePercent: Double {
        guard previousDayPrice > 0 else { return 0 }
        return (markPrice - previousDayPrice) / previousDayPrice
    }

    var bestAvailableBuyPrice: Double {
        impactAskPrice ?? midPrice ?? markPrice
    }

    var bestAvailableSellPrice: Double {
        impactBidPrice ?? midPrice ?? markPrice
    }

    var maintenanceMarginRate: Double {
        1 / (2 * Double(max(1, maxLeverage)))
    }

    func roundedSize(_ value: Double) -> Double {
        let scale = pow(10, Double(max(0, sizeDecimals)))
        return floor(value * scale) / scale
    }
}

struct HyperliquidCandle: Identifiable, Codable, Hashable, Sendable {
    let openTime: Date
    let closeTime: Date
    let coin: String
    let interval: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    let tradeCount: Int

    var id: Date { openTime }

    var hasValidOHLC: Bool {
        [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && low <= min(open, close) && high >= max(open, close)
            && closeTime > openTime
    }

    static func validated(
        _ candles: [Self], coin: String, interval: String, start: Date, end: Date
    ) -> [Self] {
        var byTime: [Date: Self] = [:]
        for candle in candles where candle.coin == coin && candle.interval == interval
            && candle.hasValidOHLC && candle.closeTime >= start && candle.openTime <= end {
            byTime[candle.openTime] = candle
        }
        return byTime.values.sorted { $0.openTime < $1.openTime }
    }
}

struct HyperliquidCandleWindow: Equatable, Sendable {
    let duration: TimeInterval
    let interval: String

    static let dailyHistory = Self(duration: 90 * 86_400, interval: "1d")
}

enum HyperliquidChartRange: String, CaseIterable, Identifiable, Sendable {
    case oneHour = "1H"
    case fourHours = "4H"
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .oneHour: 60 * 60
        case .fourHours: 4 * 60 * 60
        case .oneDay: 24 * 60 * 60
        case .oneWeek: 7 * 24 * 60 * 60
        case .oneMonth: 30 * 24 * 60 * 60
        }
    }

    var candleInterval: String {
        switch self {
        case .oneHour: "1m"
        case .fourHours: "5m"
        case .oneDay: "15m"
        case .oneWeek: "1h"
        case .oneMonth: "4h"
        }
    }
}

enum HyperliquidChartStyle: String, CaseIterable, Identifiable {
    case line
    case candles

    var id: Self { self }

    var symbol: String {
        switch self {
        case .line: "chart.xyaxis.line"
        case .candles: "chart.bar.fill"
        }
    }
}

struct HyperliquidDex: Identifiable, Codable, Hashable, Sendable {
    let name: String
    let displayName: String

    var id: String { name }
}
