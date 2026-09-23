import Charts
import SwiftUI

private enum PublicPortfolioPeriod: String, CaseIterable, Identifiable {
    case day = "1D", week = "1W", month = "1M"
    var id: Self { self }
}

struct FeedPublicPortfolioView: View {
    let portfolio: FeedPublicPortfolio
    @State private var period: PublicPortfolioPeriod = .day
    @State private var selectedDate: Date?

    private var points: [FeedPublicPortfolio.Point] {
        switch period {
        case .day: portfolio.history.day
        case .week: portfolio.history.week
        case .month: portfolio.history.month
        }
    }
    private var selected: FeedPublicPortfolio.Point? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var change: Double? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        return last.value - first.value
    }
    private var tint: Color { (change ?? 0) < 0 ? BSmartColor.bear : BSmartColor.bull }
    private var valueDomain: ClosedRange<Double> {
        let low = points.map(\.value).min() ?? 0
        let high = points.map(\.value).max() ?? 1
        let inset = max((high - low) * 0.15, max(high * 0.003, 1))
        return (low - inset)...(high + inset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Perps equity".bSmartLocalized)
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    Text(money(selected?.valueUSD ?? portfolio.perpsEquityUSD))
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if let change {
                        Text(change.formatted(.bSmartDollars.sign(strategy: .always()).precision(.fractionLength(2)))
                             + (percentageChange.map { " (" + $0 + ")" } ?? "") + " · " + period.rawValue)
                            .font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(tint)
                    }
                    if let date = selected?.date ?? portfolio.equityAsOf.map({ Date(timeIntervalSince1970: $0 / 1000) }) {
                        Text("As of".bSmartLocalized + " " + date.formatted(.dateTime.month().day().hour().minute()))
                            .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(PublicPortfolioPeriod.allCases) { item in
                        Button { period = item; selectedDate = nil } label: {
                            Text(item.rawValue).font(.caption.weight(.semibold))
                                .foregroundStyle(period == item ? BSmartColor.primaryText : BSmartColor.secondaryText)
                                .frame(minWidth: 38, minHeight: 36)
                                .background(period == item ? BSmartColor.selectedControlSurface : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityAddTraits(period == item ? .isSelected : [])
                    }
                }
            }
            if points.count > 1 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Date", point.date), yStart: .value("Base", valueDomain.lowerBound),
                                 yEnd: .value("Equity", point.value))
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", point.date), y: .value("Equity", point.value))
                            .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    if let point = selected ?? points.last {
                        PointMark(x: .value("Date", point.date), y: .value("Equity", point.value))
                            .foregroundStyle(tint).symbolSize(30)
                    }
                }
                .chartYScale(domain: valueDomain).chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        if period == .day { AxisValueLabel(format: .dateTime.hour().minute()) }
                        else { AxisValueLabel(format: .dateTime.month().day()) }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 160)
                .accessibilityIdentifier("feed.profile.equity-chart")
            } else {
                Text("No equity history".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
            Divider().overlay(BSmartColor.softDivider)
            HStack {
                Text("Spot USDC".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Text(money(portfolio.spotUSDC)).monospacedDigit()
            }.font(.subheadline)
            Text("Perps equity and spot USDC are shown separately; shared collateral is not added twice.".bSmartLocalized)
                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
        }
        .accessibilityIdentifier("feed.profile.portfolio")
    }

    private func money(_ raw: String?) -> String {
        guard let raw, let value = Double(raw), value.isFinite else { return "--" }
        return value.formatted(.bSmartDollars.precision(.fractionLength(2)))
    }

    private var percentageChange: String? {
        guard let change, let first = points.first?.value, first > 0 else { return nil }
        return (change / first * 100).formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%"
    }
}

struct FeedPublicPositionsView: View {
    let positions: [FeedPublicPortfolio.Position]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open positions".bSmartLocalized).font(.headline)
                Spacer()
                Text("\(positions.count)").font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }.padding(.bottom, 12)
            if positions.isEmpty {
                Text("No open positions".bSmartLocalized).font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText).padding(.vertical, 18)
            }
            ForEach(positions) { position in
                BSmartDetailNavigationLink(id: "public-position-\(position.coin)") {
                    TickerDestinationView(symbol: position.symbol)
                } label: {
                    HStack(spacing: 12) {
                        BSmartAssetMark(ticker: position.symbol, size: 40, isCrypto: !position.coin.contains(":"))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(position.symbol).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BSmartColor.primaryText)
                                Text("\(position.leverage)x " + (position.side == .long ? "Long" : "Short").bSmartLocalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(position.side == .long ? BSmartColor.bull : BSmartColor.bear)
                            }
                            Text("Entry price".bSmartLocalized + " " + money(position.entryPriceUSD))
                                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(money(position.valueUSD)).font(.subheadline.weight(.semibold))
                                .foregroundStyle(BSmartColor.primaryText)
                            Text(money(position.unrealizedPnLUSD, signed: true)
                                 + " (" + roi(position.returnOnEquity) + ")")
                                .font(.caption.weight(.medium))
                                .foregroundStyle((Double(position.unrealizedPnLUSD) ?? 0) < 0 ? BSmartColor.bear : BSmartColor.bull)
                        }.monospacedDigit()
                    }
                    .frame(minHeight: 68).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider().overlay(BSmartColor.softDivider)
            }
        }.accessibilityIdentifier("feed.profile.positions")
    }

    private func money(_ raw: String?, signed: Bool = false) -> String {
        guard let raw, let value = Double(raw), value.isFinite else { return "--" }
        let format: FloatingPointFormatStyle<Double>.Currency = .bSmartDollars.precision(.fractionLength(2))
        return value.formatted(signed ? format.sign(strategy: .always()) : format)
    }

    private func roi(_ raw: String) -> String {
        guard let value = Double(raw), value.isFinite else { return "--" }
        return (value * 100).formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%"
    }
}
