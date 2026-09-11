import SwiftUI

struct PriceEvidenceChart: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence
    @State private var selectedID: String?

    var body: some View {
        let model = RepresentativeWorkChartModel(update: update, evidence: evidence)
        BSmartPriceChart(
            series: BSmartPriceChartSeries(BSmartChartCandle.daily(model.candles)),
            markers: model.markers.enumerated().compactMap { index, marker in
                guard let date = BSmartChartCandle.day(marker.opinion.viewDay) else { return nil }
                return BSmartPriceChartMarker(id: marker.id.uuidString, time: date,
                    price: marker.opinion.viewPrice, color: marker.opinion.direction.color,
                    label: "\(marker.opinion.viewDay), \(marker.opinion.direction.label.bSmartLocalized)",
                    number: index + 1, accessibilityID: "opinion.evidence.marker.\(index)")
            },
            selectedMarkerID: selectedID,
            identifier: "opinion.evidence.chart",
            onMarker: { selectedID = $0 }
        ) { _ in }
        .id(update.id)
    }
}

struct SmartMoneyEntryEvidenceChart: View {
    let evidence: SmartMoneyRepresentativeEvidence
    @State private var selectedID: String?

    var body: some View {
        let history = evidence.priceEvidence
        let markers = history.entryMarkers.sorted { $0.entryNotional > $1.entryNotional }
            .prefix(3).sorted { $0.observedAt < $1.observedAt }
        BSmartPriceChart(
            series: BSmartPriceChartSeries(history.candles.map {
                BSmartChartCandle(time: $0.timestamp, interval: interval, open: $0.open,
                                  high: $0.high, low: $0.low, close: $0.close)
            }),
            markers: markers.enumerated().map { index, marker in
                BSmartPriceChartMarker(id: marker.id.uuidString, time: marker.observedAt,
                    price: marker.price, color: marker.direction.color,
                    label: "\(marker.observedAt.formatted()), \(marker.direction.label.bSmartLocalized)",
                    number: index + 1, accessibilityID: "money.evidence.marker.\(index)")
            },
            selectedMarkerID: selectedID,
            intraday: interval < 86_400,
            identifier: "money.evidence.chart",
            onMarker: { selectedID = $0 }
        ) { _ in }
        .id(history.market)
    }

    private var interval: TimeInterval {
        let value = evidence.priceEvidence.interval
        if let amount = Double(value.dropLast()), amount > 0 {
            switch value.last {
            case "m": return amount * 60
            case "h": return amount * 3_600
            case "d": return amount * 86_400
            case "w": return amount * 604_800
            default: break
            }
        }
        let times = evidence.priceEvidence.candles.map(\.timestamp).sorted()
        return zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }.filter { $0 > 0 }.min() ?? 86_400
    }
}
