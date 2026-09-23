import CoreGraphics
import Foundation

// Prepare domains and dates once per story, not once per chart mark or scroll tick.
struct TodayRepresentativeChartData {
    let calls: [TodayRepresentativeStory.Call]
    let callTimes: [Date]
    let priceDomain: ClosedRange<Double>
    let timeDomain: ClosedRange<Date>

    init?(story: TodayRepresentativeStory) {
        let calls = story.earliestCalls
        let times = calls.compactMap { BSmartChartCandle.day($0.day) }
        guard !calls.isEmpty, times.count == calls.count,
              let first = story.prices.first, let last = story.prices.last,
              first.time < last.time,
              story.prices.allSatisfy({ $0.time.timeIntervalSince1970.isFinite }) else { return nil }
        let values = story.prices.map(\.value) + calls.map(\.price) + [story.peak.value]
        guard values.allSatisfy({ $0.isFinite && $0 > 0 }),
              let low = values.min(), let high = values.max() else { return nil }
        let padding = max(high - low, high * 0.1) * 0.25
        guard (low - padding).isFinite, (high + padding).isFinite else { return nil }
        self.calls = calls
        callTimes = times
        priceDomain = (low - padding)...(high + padding)
        timeDomain = first.time...last.time
    }

    func point(time: Date, value: Double, in size: CGSize) -> CGPoint {
        let fraction = time.timeIntervalSince(timeDomain.lowerBound)
            / timeDomain.upperBound.timeIntervalSince(timeDomain.lowerBound)
        return CGPoint(x: 14 + max(0, size.width - 28) * fraction,
            y: size.height * (1 - (value - priceDomain.lowerBound)
                / (priceDomain.upperBound - priceDomain.lowerBound)))
    }

    func callPoints(in size: CGSize) -> [CGPoint] {
        zip(calls, callTimes).map { point(time: $0.1, value: $0.0.price, in: size) }
    }
}

struct TodayRepresentativeStoryAnnotations {
    let first: CGRect
    let peak: CGRect

    init(first point: CGPoint, peak high: CGPoint, size: CGSize, scale: CGFloat) {
        func fit(_ origin: CGPoint, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: min(max(0, origin.x), max(0, size.width - width)),
                   y: min(max(0, origin.y), max(0, size.height - height)), width: width, height: height)
        }
        peak = fit(CGPoint(x: high.x - 42 * scale, y: high.y - 25 * scale), width: 84 * scale, height: 18 * scale)
        var start = fit(CGPoint(x: point.x + 7, y: point.y + 10), width: 96 * scale, height: 30 * scale)
        if start.intersects(peak.insetBy(dx: -4, dy: -4)) {
            start = fit(CGPoint(x: point.x + 7, y: size.height - 30 * scale), width: 96 * scale, height: 30 * scale)
        }
        first = start
    }
}
