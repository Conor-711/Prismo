import SwiftUI
import Charts

struct InvestorEducationCase: View {
    let example: InvestorEducationSnapshot.Example
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var selectedDate: Date?

    private var points: [InvestorEducationSnapshot.Point] {
        revealed ? example.candles : example.candles.filter { $0.day <= example.publishedDay }
    }
    private var selectedPoint: InvestorEducationSnapshot.Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("See what they spotted early.".bSmartLocalized)
                .font(.system(size: 29, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                BSmartAvatar(url: URL(string: example.avatarURL), name: example.authorName, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.authorName).font(.headline)
                    Text("X · \(example.publishedDay) UTC").font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
                Spacer()
                BSmartAssetMark(ticker: example.ticker, size: 32)
                Text(example.ticker).font(.headline)
            }
            Text(example.summary).font(.system(size: 21, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("View paraphrase".bSmartLocalized).font(.caption2).foregroundStyle(BSmartColor.secondaryText)
            if let url = URL(string: example.sourceURL) {
                Link(destination: url) { Label("Open original source".bSmartLocalized, systemImage: "arrow.up.right") }
                    .font(.subheadline).tint(BSmartColor.brand).accessibilityIdentifier("education.source")
            }
            chart
            HStack(alignment: .center) {
                Button {
                    selectedDate = nil
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.75)) { revealed.toggle() }
                } label: {
                    Label((revealed ? "Replay" : "See the stock's return").bSmartLocalized,
                          systemImage: revealed ? "arrow.counterclockwise" : "arrow.right")
                        .font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 50)
                        .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(BSmartColor.onAccent)
                }
                .buttonStyle(.plain).accessibilityIdentifier("education.reveal")
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(revealed ? "+\(example.returnPercent.formatted(.number.precision(.fractionLength(2))))%" : "—")
                        .font(.system(size: 28, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText()).foregroundStyle(BSmartColor.brand)
                        .accessibilityIdentifier("education.return")
                    Text("60-trading-day stock return".bSmartLocalized).font(.caption2)
                        .foregroundStyle(BSmartColor.secondaryText).multilineTextAlignment(.trailing)
                }
            }
            if revealed {
                HStack {
                    Label("This view added to the ranking.".bSmartLocalized, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(BSmartColor.brand)
                    Spacer()
                }.font(.subheadline.weight(.semibold)).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var chart: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(example.source) · \(example.ticker)")
                Spacer()
                if let point = selectedPoint { Text("\(point.day) · $\(point.close.formatted(.number.precision(.fractionLength(2))))") }
            }.font(.caption2).foregroundStyle(BSmartColor.secondaryText)
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Price", point.close))
                        .foregroundStyle(BSmartColor.brand).lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                if let point = points.last {
                    PointMark(x: .value("Date", point.date), y: .value("Price", point.close))
                        .foregroundStyle(BSmartColor.brand).symbolSize(26)
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date)).foregroundStyle(BSmartColor.chartVerticalCrosshair)
                    PointMark(x: .value("Date", point.date), y: .value("Price", point.close)).foregroundStyle(BSmartColor.brand)
                }
            }
            .chartXScale(domain: (example.candles.first?.date ?? .now)...(example.candles.last?.date ?? .now))
            .chartYScale(domain: priceDomain)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
            } }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
            .chartXSelection(value: $selectedDate)
            .frame(height: 260).accessibilityIdentifier("education.chart")
        }
    }

    private var priceDomain: ClosedRange<Double> {
        let low = example.candles.map(\.close).min() ?? 0
        let high = example.candles.map(\.close).max() ?? 1
        let padding = max((high - low) * 0.12, 1)
        return (low - padding)...(high + padding)
    }
}
