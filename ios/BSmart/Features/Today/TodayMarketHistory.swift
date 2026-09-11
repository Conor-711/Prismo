import Foundation

/// Prepared when OHLC changes, not for every quote tick or avatar layout pass.
struct TodayMarketHistory {
    let coin: String?
    let candles: [PriceCandle]
    private let bySession: [TimeInterval: PriceCandle]

    init(candles source: [HyperliquidCandle] = []) {
        coin = source.first?.coin
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var sessions: [TimeInterval: PriceCandle] = [:]
        for candle in source where candle.coin == coin && candle.interval == "1d" && candle.hasValidOHLC {
            let key = Self.session(candle.openTime)
            sessions[key] = PriceCandle(day: formatter.string(from: candle.openTime), open: candle.open,
                                       high: candle.high, low: candle.low, close: candle.close,
                                       volume: candle.volume.isFinite && candle.volume >= 0 && candle.volume < Double(Int.max)
                                           ? Int(candle.volume) : 0)
        }
        bySession = sessions
        candles = sessions.sorted { $0.key < $1.key }.map(\.value)
    }

    func candle(at date: Date, days: Int, now: Date = Date()) -> PriceCandle? {
        guard date <= now, let candle = bySession[Self.session(date)],
              let firstDay = candles.suffix(days).first?.day, candle.day >= firstDay else { return nil }
        return candle
    }

    private static func session(_ date: Date) -> TimeInterval {
        floor(date.timeIntervalSince1970 / 86_400) * 86_400
    }
}
