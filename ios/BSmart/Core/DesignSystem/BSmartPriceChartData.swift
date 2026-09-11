import Foundation

struct BSmartChartCandle: Identifiable, Equatable {
    var id: Date { time }
    let time: Date
    let interval: TimeInterval
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    var isValid: Bool {
        time.timeIntervalSince1970.isFinite && interval.isFinite && interval > 0
            && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && low <= min(open, close) && high >= max(open, close)
    }

    static func daily(_ candles: [PriceCandle]) -> [Self] {
        candles.compactMap { candle in
            guard let time = day(candle.day) else { return nil }
            return Self(time: time, interval: 86_400, open: candle.open, high: candle.high,
                        low: candle.low, close: candle.close)
        }
    }

    static func day(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
}

struct BSmartPriceChartSeries {
    let candles: [BSmartChartCandle]

    init(_ candles: [BSmartChartCandle]) {
        var unique: [Date: BSmartChartCandle] = [:]
        for candle in candles where candle.isValid { unique[candle.time] = candle }
        self.candles = unique.values.sorted { $0.time < $1.time }
    }

    var bounds: ClosedRange<Date> {
        guard let first = candles.first, let last = candles.last else {
            return Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 1)
        }
        return first.time.addingTimeInterval(-first.interval / 2)...last.time.addingTimeInterval(last.interval)
    }

    var minimumSpan: TimeInterval {
        min(bounds.upperBound.timeIntervalSince(bounds.lowerBound), (candles.map(\.interval).min() ?? 1) * 8)
    }

    func visible(in window: ClosedRange<Date>) -> [BSmartChartCandle] {
        candles.filter { $0.time.addingTimeInterval($0.interval / 2) >= window.lowerBound
            && $0.time.addingTimeInterval(-$0.interval / 2) <= window.upperBound }
    }

    func nearest(to date: Date) -> BSmartChartCandle? {
        candles.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    func priceDomain(in window: ClosedRange<Date>, including prices: [Double]) -> ClosedRange<Double> {
        let visible = visible(in: window)
        let values = (visible.flatMap { [$0.low, $0.high] } + prices).filter { $0.isFinite && $0 > 0 }
        let low = values.min() ?? nearest(to: window.lowerBound)?.low ?? 1
        let high = values.max() ?? nearest(to: window.lowerBound)?.high ?? 1
        let padding = max((high - low) * 0.08, high * 0.001)
        return max(0, low - padding)...(high + padding)
    }
}

enum BSmartChartViewport {
    static func clamped(_ window: ClosedRange<Date>, to bounds: ClosedRange<Date>, minimumSpan: TimeInterval) -> ClosedRange<Date> {
        let span = min(bounds.upperBound.timeIntervalSince(bounds.lowerBound),
                       max(minimumSpan, window.upperBound.timeIntervalSince(window.lowerBound)))
        let start = min(max(window.lowerBound, bounds.lowerBound), bounds.upperBound.addingTimeInterval(-span))
        return start...start.addingTimeInterval(span)
    }

    static func zoom(_ window: ClosedRange<Date>, scale: Double, anchor: Double,
                     bounds: ClosedRange<Date>, minimumSpan: TimeInterval) -> ClosedRange<Date> {
        guard scale.isFinite, scale > 0, anchor.isFinite else { return window }
        let fraction = min(max(anchor, 0), 1)
        let oldSpan = window.upperBound.timeIntervalSince(window.lowerBound)
        let span = min(bounds.upperBound.timeIntervalSince(bounds.lowerBound), max(minimumSpan, oldSpan / scale))
        let start = window.lowerBound.addingTimeInterval((oldSpan - span) * fraction)
        return clamped(start...start.addingTimeInterval(span), to: bounds, minimumSpan: minimumSpan)
    }

    static func pan(_ window: ClosedRange<Date>, fraction: Double, bounds: ClosedRange<Date>) -> ClosedRange<Date> {
        guard fraction.isFinite else { return window }
        let shift = -fraction * window.upperBound.timeIntervalSince(window.lowerBound)
        return clamped(window.lowerBound.addingTimeInterval(shift)...window.upperBound.addingTimeInterval(shift),
                       to: bounds, minimumSpan: 0)
    }
}
