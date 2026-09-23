import Charts
import SwiftUI

struct SmartAccountRepresentativeWorks: View {
    let works: [SmartAccountUpdate]
    let updates: [SmartAccountUpdate]
    let isLoading: Bool
    @State private var selectedTicker: String?

    private var selected: SmartAccountUpdate? {
        works.first { $0.ticker == selectedTicker } ?? works.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Representative works".bSmartLocalized).font(.title3.weight(.bold))
            if let selected, let evidence = selected.priceEvidence {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(works.prefix(3).enumerated()), id: \.element.id) { index, work in
                            Button { selectedTicker = work.ticker } label: {
                                HStack(spacing: 8) {
                                    BSmartAssetMark(ticker: work.ticker, size: 25)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(work.ticker).font(.subheadline.weight(.semibold))
                                        Text("#\(work.representativeTickerRank ?? index + 1)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(BSmartColor.secondaryText)
                                    }
                                }
                                .padding(.horizontal, 12).frame(height: 56)
                                .background(selected.ticker == work.ticker ? BSmartColor.brand.opacity(0.12) : BSmartColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                    selected.ticker == work.ticker ? BSmartColor.brand : BSmartColor.line))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected.ticker == work.ticker ? .isSelected : [])
                            .accessibilityIdentifier("account.work.select.\(work.ticker)")
                        }
                    }
                }
                RepresentativeWorkDetail(update: selected, evidence: evidence, updates: updates)
                    .id(selected.id)
            } else {
                if isLoading { BSmartSkeletonRows(style: .feed, count: 2) }
                else {
                    Text("No settled representative work with price evidence is available yet.".bSmartLocalized)
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.representative-works")
    }
}

private struct RepresentativeWorkDetail: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence
    let updates: [SmartAccountUpdate]
    let model: RepresentativeWorkChartModel
    @State private var selectedID: UUID?
    @State private var showsCandles = true

    init(update: SmartAccountUpdate, evidence: SmartAccountPriceEvidence, updates: [SmartAccountUpdate]) {
        self.update = update
        self.evidence = evidence
        self.updates = updates
        self.model = RepresentativeWorkChartModel(update: update, evidence: evidence)
    }
    private var selected: RepresentativeWorkChartModel.Marker? {
        model.markers.first { $0.id == selectedID }
            ?? model.markers.first { $0.id == update.id }
            ?? model.markers.max { $0.opinion.contribution < $1.opinion.contribution }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            performanceHeader
            if model.candles.isEmpty {
                ContentUnavailableView("Price history unavailable".bSmartLocalized, systemImage: "chart.xyaxis.line")
                    .frame(height: 270)
            } else {
                priceChart.frame(height: 306)
            }
            if !model.markers.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(model.markers.enumerated()), id: \.element.id) { index, marker in
                        Button { selectedID = marker.id } label: {
                            VStack(spacing: 5) {
                                Text("\(index + 1) · \(shortDate(marker.opinion.viewDay))")
                                    .font(.caption.weight(.semibold))
                                Text(marker.opinion.direction.label.bSmartLocalized)
                                    .font(.caption2).foregroundStyle(marker.opinion.direction.color)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(selected?.id == marker.id ? BSmartColor.brand.opacity(0.12) : BSmartColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(selected?.id == marker.id ? BSmartColor.brand : .clear).frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected?.id == marker.id ? .isSelected : [])
                        .accessibilityIdentifier("account.work.opinion.\(index)")
                    }
                }
            }
            if let selected { opinionDetail(selected.opinion) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.work.detail.\(update.ticker)")
    }

    private var performanceHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BSmartAssetMark(ticker: update.ticker, size: 28)
                Text(update.ticker).font(.headline).accessibilityIdentifier("account.work.ticker")
                Text(update.direction.label.bSmartLocalized).font(.subheadline.weight(.semibold))
                    .foregroundStyle(update.direction.color)
                Spacer()
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    performanceSummary
                    Spacer(minLength: 0)
                    chartModes
                }
                VStack(alignment: .leading, spacing: 8) {
                    performanceSummary
                    chartModes
                }
            }
        }
    }

    @ViewBuilder private var performanceSummary: some View {
        if let performance = RepresentativeWorkPerformance(update: update) {
            VStack(alignment: .leading, spacing: 2) {
                performanceValue(performance).fixedSize()
                Text("Stock price change".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            }
        }
    }

    private var chartModes: some View {
        HStack(spacing: 8) {
            chartMode(true, symbol: "chart.bar.xaxis", label: "Candlesticks")
            chartMode(false, symbol: "chart.xyaxis.line", label: "Line chart")
        }
        .fixedSize()
    }

    private func performanceValue(_ performance: RepresentativeWorkPerformance) -> some View {
        Text((performance.percent / 100).formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
            .font(.system(.largeTitle, design: .default, weight: .bold)).monospacedDigit()
            .foregroundStyle(performance.percent >= 0 ? BSmartColor.bull : BSmartColor.bear)
            .accessibilityValue("\(dateLabel(performance.startDay)) – \(dateLabel(performance.endDay))")
            .accessibilityIdentifier("account.work.performance")
    }

    private func chartMode(_ candles: Bool, symbol: String, label: String) -> some View {
        Button { showsCandles = candles } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 36)
                .foregroundStyle(showsCandles == candles ? BSmartColor.onAccent : BSmartColor.secondaryText)
                .background(showsCandles == candles ? BSmartColor.brand : BSmartColor.surface,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.bSmartLocalized)
        .accessibilityAddTraits(showsCandles == candles ? .isSelected : [])
        .accessibilityIdentifier(candles ? "account.work.candles" : "account.work.line")
    }

    private var priceChart: some View {
        BSmartPriceChart(
            series: BSmartPriceChartSeries(BSmartChartCandle.daily(model.candles)),
            showsCandles: showsCandles,
            markers: model.markers.enumerated().compactMap { index, marker in
                guard let date = BSmartChartCandle.day(marker.opinion.viewDay) else { return nil }
                return BSmartPriceChartMarker(id: marker.id.uuidString, time: date,
                    price: marker.opinion.viewPrice, color: marker.opinion.direction.color,
                    label: "\(marker.opinion.viewDay), \(marker.opinion.direction.label.bSmartLocalized)",
                    number: index + 1, accessibilityID: "account.work.marker.\(index)")
            },
            selectedMarkerID: selected?.id.uuidString,
            identifier: "account.work.chart",
            onMarker: { selectedID = UUID(uuidString: $0) }
        ) { _ in }
    }

    private func opinionDetail(_ opinion: SmartAccountOpinionMarker) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BSmartTag(text: opinion.direction.label.bSmartLocalized, color: opinion.direction.color)
                if opinion.horizon.lowercased() != "unknown" {
                    BSmartTag(text: opinion.horizon, color: BSmartColor.sky)
                }
                Spacer()
            }
            Text(opinion.thesis).font(.subheadline).lineSpacing(3)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("account.work.selected-thesis")
            if let full = (updates + [update]).first(where: { $0.id == opinion.id }) {
                BSmartDetailNavigationLink(id: "representative-selected-\(opinion.id)") {
                    SmartAccountEvidenceDetailView(update: full)
                } label: {
                    Label("View evidence".bSmartLocalized, systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
                .tint(BSmartColor.brand)
                .accessibilityIdentifier("account.work.evidence")
            } else if let url = opinion.evidenceURL {
                Link(destination: url) {
                    Label("Open original source".bSmartLocalized, systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }.tint(BSmartColor.brand)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.work.selected-opinion")
    }

    private func dateLabel(_ day: String) -> String { day.replacingOccurrences(of: "-", with: "/") }
    private func shortDate(_ day: String) -> String { String(dateLabel(day).suffix(5)) }
}
