import Charts
import SwiftUI

enum PortfolioChartPeriod: String, CaseIterable, Identifiable {
    case day = "1D", week = "1W", month = "1M", all = "All"
    var id: Self { self }
    var days: Double? {
        switch self { case .day: 1; case .week: 7; case .month: 30; case .all: nil }
    }

    func points(in history: [PortfolioValuePoint], now: Date) -> [PortfolioValuePoint] {
        let valid = PortfolioValuationHistory.normalized(history, now: now)
        guard let days else { return valid }
        let start = now.addingTimeInterval(-days * 86_400)
        return valid.filter { $0.timestamp >= start }
    }
}

struct PortfolioValueChart: View {
    let history: [PortfolioValuePoint]
    @State private var period: PortfolioChartPeriod = .all
    @State private var selectedDate: Date?

    private var points: [PortfolioValuePoint] { period.points(in: history, now: Date()) }
    private var selected: PortfolioValuePoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) }
    }
    private var change: Double { (points.last?.value ?? 0) - (points.first?.value ?? 0) }
    private var tint: Color { change < 0 ? BSmartColor.bear : BSmartColor.bull }
    private var domain: ClosedRange<Double> {
        let minValue = points.map(\.value).min() ?? 0
        let maxValue = points.map(\.value).max() ?? 1
        let padding = max((maxValue - minValue) * 0.15, maxValue * 0.003, 1)
        return (minValue - padding)...(maxValue + padding)
    }
    private var timeDomain: ClosedRange<Date> {
        let first = points.first?.timestamp ?? Date()
        let last = points.last?.timestamp ?? first
        return first.addingTimeInterval(first == last ? -1800 : 0)...last.addingTimeInterval(first == last ? 1800 : 0)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                if let selected {
                    Text(selected.value.formatted(.bSmartDollars.precision(.fractionLength(2))))
                        .foregroundStyle(BSmartColor.primaryText)
                        .accessibilityIdentifier("portfolio.chart.selected-value")
                    Spacer()
                    Text(selected.timestamp, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(BSmartColor.secondaryText)
                } else {
                    Text("Valuation change".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                    Text(points.count > 1 ? change.formatted(.bSmartDollars.precision(.fractionLength(2)).sign(strategy: .always())) : "--")
                        .foregroundStyle(tint)
                }
            }
            .font(.system(size: 12, weight: .medium)).monospacedDigit().frame(height: 22)

            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Date", point.timestamp), yStart: .value("Base", domain.lowerBound), yEnd: .value("Value", point.value))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.timestamp), y: .value("Value", point.value))
                        .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if let point = selected ?? points.last {
                    PointMark(x: .value("Date", point.timestamp), y: .value("Value", point.value))
                        .foregroundStyle(tint).symbolSize(28)
                    if selected != nil {
                        RuleMark(x: .value("Date", point.timestamp)).foregroundStyle(BSmartColor.secondaryText.opacity(0.5))
                    }
                }
            }
            .chartXScale(domain: timeDomain).chartYScale(domain: domain)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    if period == .day {
                        AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(BSmartColor.tertiaryText)
                    } else {
                        AxisValueLabel(format: .dateTime.month().day()).foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 132)
            .overlay {
                if points.isEmpty {
                    Text("No valuation history".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("portfolio.value-chart")

            HStack(spacing: 0) {
                ForEach(PortfolioChartPeriod.allCases) { item in
                    Button { period = item; selectedDate = nil } label: {
                        Text(item.rawValue.bSmartLocalized).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(period == item ? BSmartColor.brand : BSmartColor.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(period == item ? BSmartColor.brand.opacity(0.1) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(period == item ? .isSelected : [])
                        .accessibilityIdentifier("portfolio.period.\(item.rawValue)")
                }
            }
        }
        .onChange(of: history) { _, _ in selectedDate = nil }
    }
}
