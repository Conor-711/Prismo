import Charts
import SwiftUI

struct BSmartPriceChartMarker: Identifiable {
    let id: String
    let time: Date
    let price: Double
    let color: Color
    let label: String
    let number: Int
    let accessibilityID: String
}

/// Shared trading-style plot. Callers retain ownership of data sources and evidence navigation.
struct BSmartPriceChart<Overlay: View>: View {
    let series: BSmartPriceChartSeries
    var showsCandles = true
    var accent = BSmartColor.brand
    var referencePrice: Double? = nil
    var markers: [BSmartPriceChartMarker] = []
    var selectedMarkerID: String? = nil
    var intraday = false
    var identifier = "price.chart"
    var onSelection: (Date?) -> Void = { _ in }
    var onMarker: (String) -> Void = { _ in }
    @ViewBuilder let overlay: (ChartProxy) -> Overlay
    @State private var viewport: ClosedRange<Date>?
    @State private var selectedTime: Date?

    private var window: ClosedRange<Date> {
        BSmartChartViewport.clamped(viewport ?? series.bounds, to: series.bounds, minimumSpan: series.minimumSpan)
    }
    private var visibleCandles: [BSmartChartCandle] { series.visible(in: window) }
    private var visibleMarkers: [BSmartPriceChartMarker] {
        markers.filter { window.contains($0.time) && $0.price.isFinite && $0.price > 0 }
    }
    private var selected: BSmartChartCandle? {
        guard let selectedTime else { return nil }
        return series.nearest(to: selectedTime)
    }
    private var priceDomain: ClosedRange<Double> {
        // A live quote must not flatten an older, zoomed-in historical window.
        let reference = viewport == nil ? [referencePrice].compactMap { $0 } : []
        return series.priceDomain(in: window, including: visibleMarkers.map(\.price) + reference)
    }

    var body: some View {
        VStack(spacing: 4) {
            readout
            if series.candles.isEmpty {
                ContentUnavailableView("Price history unavailable".bSmartLocalized, systemImage: "chart.xyaxis.line")
                    .frame(maxHeight: .infinity)
            } else {
                plot
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .transaction { $0.animation = nil }
        .onChange(of: series.bounds) { old, new in
            if let viewport {
                let followsLatest = abs(viewport.upperBound.timeIntervalSince(old.upperBound)) < 1
                let shift = followsLatest ? new.upperBound.timeIntervalSince(old.upperBound) : 0
                self.viewport = BSmartChartViewport.clamped(
                    viewport.lowerBound.addingTimeInterval(shift)...viewport.upperBound.addingTimeInterval(shift),
                    to: new, minimumSpan: series.minimumSpan)
            }
            if let selectedTime, !new.contains(selectedTime) { select(nil) }
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text((selected ?? visibleCandles.last).map { dateLabel($0.time, full: true) } ?? "--")
                    .font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("\(identifier).date")
                Spacer(minLength: 0)
                chartButton("minus.magnifyingglass", label: "Zoom out", suffix: "zoom-out") { zoom(1 / 1.5, anchor: 0.5) }
                    .disabled(viewport == nil || window == series.bounds)
                chartButton("plus.magnifyingglass", label: "Zoom in", suffix: "zoom-in") { zoom(1.5, anchor: 0.5) }
                    .disabled(window.upperBound.timeIntervalSince(window.lowerBound) <= series.minimumSpan)
                chartButton("arrow.counterclockwise", label: "Reset chart", suffix: "reset", action: reset)
                    .disabled(viewport == nil && selectedTime == nil)
            }
            .frame(height: 36)
            if let candle = selected ?? visibleCandles.last {
                HStack(spacing: 8) {
                    price("O", candle.open)
                    price("H", candle.high)
                    price("L", candle.low)
                    price("C", candle.close)
                }
                .foregroundStyle(candle.close >= candle.open ? BSmartColor.bull : BSmartColor.bear)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(identifier).ohlc")
            }
        }
        .frame(height: 54, alignment: .top)
    }

    private func price(_ name: String, _ value: Double) -> some View {
        Text("\(name) \(value.formatted(.number.precision(.fractionLength(0...2))))")
            .font(.system(size: 10)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartButton(_ symbol: String, label: String, suffix: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
        .accessibilityLabel(label.bSmartLocalized).help(label.bSmartLocalized)
        .accessibilityIdentifier("\(identifier).\(suffix)")
    }

    private var plot: some View {
        Chart {
            ForEach(visibleCandles) { candle in
                if showsCandles {
                    BSmartCandlestick(time: candle.time, interval: candle.interval, open: candle.open,
                                      high: candle.high, low: candle.low, close: candle.close)
                } else {
                    LineMark(x: .value("Time", candle.time), y: .value("Price", candle.close))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let referencePrice, referencePrice.isFinite, priceDomain.contains(referencePrice) {
                RuleMark(y: .value("Reference", referencePrice))
                    .foregroundStyle(accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
            }
            if let selected, window.contains(selected.time) {
                RuleMark(x: .value("Selected", selected.time))
                    .foregroundStyle(BSmartColor.chartVerticalCrosshair)
                    .lineStyle(StrokeStyle(lineWidth: 0.7))
                RuleMark(y: .value("Close", selected.close))
                    .foregroundStyle(BSmartColor.chartHorizontalCrosshair)
                    .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [2, 3]))
                PointMark(x: .value("Time", selected.time), y: .value("Price", selected.close))
                    .foregroundStyle(BSmartColor.primaryText).symbolSize(35)
            }
            ForEach(visibleMarkers) { marker in
                PointMark(x: .value("Time", marker.time), y: .value("Evidence", marker.price))
                    .foregroundStyle(marker.color).symbolSize(24)
            }
        }
        .chartXScale(domain: window)
        .chartYScale(domain: priceDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dateLabel(date, full: false))
                            .font(.system(size: 10))
                    }
                }.foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(BSmartColor.chartAxisGrid)
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(price.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.system(size: 10)).monospacedDigit()
                    }
                }.foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    ZStack(alignment: .topLeading) {
                        BSmartChartGestures(inspect: { fraction in
                            let date = window.lowerBound.addingTimeInterval(
                                Double(fraction) * window.upperBound.timeIntervalSince(window.lowerBound))
                            select(series.nearest(to: date)?.time)
                        }, pan: { fraction in
                            viewport = BSmartChartViewport.pan(window, fraction: Double(fraction), bounds: series.bounds)
                            select(nil)
                        }, zoom: { scale, anchor in zoom(Double(scale), anchor: Double(anchor)) }, reset: reset)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityElement()
                        .accessibilityLabel("Price history".bSmartLocalized)
                        .accessibilityValue("\(window.lowerBound.timeIntervalSince1970):\(window.upperBound.timeIntervalSince1970)")
                        .accessibilityAdjustableAction { direction in
                            let current = selected ?? visibleCandles.last
                            guard let current, let index = series.candles.firstIndex(where: { $0.id == current.id }) else { return }
                            let next = min(max(index + (direction == .increment ? 1 : -1), 0), series.candles.count - 1)
                            reset()
                            select(series.candles[next].time)
                        }
                        .accessibilityIdentifier("\(identifier).plot")
                        markerOverlay(proxy: proxy, frame: frame)
                        overlay(proxy)
                    }
                }
            }
        }
    }

    private func markerOverlay(proxy: ChartProxy, frame: CGRect) -> some View {
        let entries = visibleMarkers.compactMap { marker -> (BSmartPriceChartMarker, CGPoint)? in
            guard let x = proxy.position(forX: marker.time), let y = proxy.position(forY: marker.price) else { return nil }
            return (marker, CGPoint(x: x, y: y))
        }
        let positions = BSmartChartMarkerLayout.positions(anchors: entries.map { $0.1 }, size: frame.size)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.0.id) { index, entry in
                let center = positions[index]
                Path { path in
                    path.move(to: CGPoint(x: entry.1.x + frame.minX, y: entry.1.y + frame.minY))
                    path.addLine(to: CGPoint(x: center.x + frame.minX, y: center.y + frame.minY))
                }.stroke(entry.0.color.opacity(0.5), lineWidth: 1).allowsHitTesting(false)
                Button {
                    select(series.nearest(to: entry.0.time)?.time)
                    onMarker(entry.0.id)
                } label: {
                    Text("\(entry.0.number)").font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(selectedMarkerID == entry.0.id ? BSmartColor.onAccent : entry.0.color)
                        .frame(width: 28, height: 28)
                        .background(selectedMarkerID == entry.0.id ? entry.0.color : BSmartColor.ink, in: Circle())
                        .overlay(Circle().stroke(entry.0.color, lineWidth: 1.5))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(x: center.x + frame.minX, y: center.y + frame.minY)
                .accessibilityLabel(entry.0.label)
                .accessibilityIdentifier(entry.0.accessibilityID)
            }
        }
    }

    private func select(_ date: Date?) { selectedTime = date; onSelection(date) }
    private func reset() { viewport = nil; select(nil) }
    private func dateLabel(_ date: Date, full: Bool) -> String {
        if intraday { return date.formatted(date: full ? .abbreviated : .omitted, time: .shortened) }
        // Daily evidence keys are UTC session dates, not instants to shift to the prior local day.
        let format = Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).month(.abbreviated).day()
        return date.formatted(full ? format.year() : format)
    }
    private func zoom(_ scale: Double, anchor: Double) {
        let next = BSmartChartViewport.zoom(window, scale: scale, anchor: anchor,
                                            bounds: series.bounds, minimumSpan: series.minimumSpan)
        viewport = next == series.bounds ? nil : next
        select(nil)
    }
}
