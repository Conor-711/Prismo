import Foundation
import CoreGraphics

struct RepresentativeWorkChartModel {
    struct Marker: Identifiable {
        let opinion: SmartAccountOpinionMarker
        let session: Double
        var id: UUID { opinion.id }
    }

    let candles: [PriceCandle]
    let markers: [Marker]

    init(update: SmartAccountUpdate, evidence: SmartAccountPriceEvidence) {
        var byDay: [String: PriceCandle] = [:]
        for candle in evidence.candles {
            guard Self.date(candle.day) != nil,
                  [candle.open, candle.close, candle.high, candle.low].allSatisfy({ $0.isFinite && $0 > 0 }),
                  candle.low <= min(candle.open, candle.close),
                  candle.high >= max(candle.open, candle.close) else { continue }
            byDay[candle.day] = candle
        }
        let candles = byDay.values.sorted { $0.day < $1.day }
        self.candles = candles
        let supplied = evidence.opinionMarkers ?? []
        let opinions = supplied.isEmpty ? [SmartAccountOpinionMarker(
            id: update.id, publishedAt: update.publishedAt, viewDay: evidence.viewDay,
            viewPrice: evidence.viewPrice, direction: update.direction,
            contribution: update.settlement?.contribution ?? 0,
            horizon: update.horizon, thesis: update.thesis, evidenceURL: update.sourceURL ?? update.evidenceURL
        )] : supplied
        var seen = Set<UUID>()
        markers = opinions.filter {
            $0.viewPrice.isFinite && $0.viewPrice > 0 && $0.contribution.isFinite && seen.insert($0.id).inserted
        }.compactMap { opinion -> Marker? in
            guard let session = Self.session(for: opinion.viewDay, candles: candles) else { return nil }
            return Marker(opinion: opinion, session: session)
        }.sorted {
            if $0.opinion.contribution != $1.opinion.contribution {
                return $0.opinion.contribution > $1.opinion.contribution
            }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(3).sorted { $0.opinion.publishedAt < $1.opinion.publishedAt }
    }

    var priceRange: ClosedRange<Double> {
        let prices = candles.flatMap { [$0.low, $0.high] } + markers.map { $0.opinion.viewPrice }
        let low = prices.min() ?? 0
        let high = prices.max() ?? 1
        let padding = max((high - low) * 0.16, high * 0.015)
        return (low - padding)...(high + padding)
    }

    var axisSessions: [Int] {
        guard candles.count > 1 else { return candles.isEmpty ? [] : [0] }
        return Array(Set([0, (candles.count - 1) / 2, candles.count - 1])).sorted()
    }

    private static func session(for day: String, candles: [PriceCandle]) -> Double? {
        guard let first = candles.first, let last = candles.last,
              day >= first.day, day <= last.day, let date = date(day) else { return nil }
        if let index = candles.firstIndex(where: { $0.day == day }) { return Double(index) }
        guard let next = candles.firstIndex(where: { $0.day > day }), next > 0,
              let before = Self.date(candles[next - 1].day), let after = Self.date(candles[next].day) else { return nil }
        return Double(next - 1) + date.timeIntervalSince(before) / after.timeIntervalSince(before)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}

typealias RepresentativeMarkerLayout = BSmartChartMarkerLayout
