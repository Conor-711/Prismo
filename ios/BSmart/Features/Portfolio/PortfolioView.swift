import Charts
import SwiftUI

private enum PortfolioSection: String, CaseIterable, Identifiable {
    case holdings = "Holdings"
    case watchlist = "Watchlist"
    case allTickers = "All tickers"

    var id: String { rawValue }
}

struct PortfolioView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @State private var isAddingEntry = false
    @State private var isShowingSettings = false
    @State private var isShowingBrokerageConnections = false
    @State private var editingEntry: PortfolioPosition?
    @State private var section: PortfolioSection = .holdings

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker

                switch section {
                case .holdings:
                    holdingsContent
                case .watchlist:
                    watchlistContent
                case .allTickers:
                    AllTickersView()
                }
            }
            .background(BSmartColor.ink)
            .navigationTitle(language.localized("Portfolio"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("portfolio.screen")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingBrokerageConnections = true
                    } label: {
                        Image(systemName: "link")
                    }
                    .accessibilityLabel("Brokerage connections")
                    .accessibilityIdentifier("portfolio.brokerage-connections")

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Open settings")
                    .accessibilityIdentifier("portfolio.settings")

                    Button {
                        isAddingEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add ticker")
                }
            }
            .sheet(isPresented: $isAddingEntry) {
                AddPositionView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $isShowingSettings) {
                AppSettingsView()
            }
            .sheet(isPresented: $isShowingBrokerageConnections) {
                BrokerageConnectionView()
                    .environmentObject(model)
            }
            .sheet(item: $editingEntry) { entry in
                AddPositionView(position: entry)
                    .environmentObject(model)
            }
        }
        .bSmartPage()
    }

    private var sectionPicker: some View {
        Picker("Portfolio view".bSmartLocalized, selection: $section) {
            ForEach(PortfolioSection.allCases) { item in
                Text(item.rawValue.bSmartLocalized).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.top, BSmartSpacing.small)
        .padding(.bottom, BSmartSpacing.xSmall)
        .accessibilityIdentifier("portfolio.section-picker")
    }

    private var holdingsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            if !model.heldPositions.isEmpty {
                portfolioSummary
                    .accessibilityIdentifier("portfolio.value-overview")
            }

            brokerageConnectionRow
                .padding(BSmartSpacing.medium)
                .background(BSmartColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                        .stroke(BSmartColor.line, lineWidth: 0.6)
                }

            portfolioEntriesPanel(
                title: "Positions",
                entries: model.heldPositions,
                emptyTitle: "No positions yet",
                emptySymbol: "chart.pie"
            )
            }
            .padding(.horizontal, BSmartSpacing.large)
            .padding(.top, BSmartSpacing.small)
            .padding(.bottom, 88)
        }
        .background(BSmartColor.ink)
        .accessibilityIdentifier("portfolio.holdings")
    }

    private var watchlistContent: some View {
        ScrollView {
            portfolioEntriesPanel(
                title: "Watchlist",
                entries: model.watchlist,
                emptyTitle: "No watched tickers",
                emptySymbol: "eye"
            )
            .padding(.horizontal, BSmartSpacing.large)
            .padding(.top, BSmartSpacing.small)
            .padding(.bottom, 88)
        }
        .background(BSmartColor.ink)
        .accessibilityIdentifier("portfolio.watchlist")
    }

    private var portfolioSummary: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio value".bSmartLocalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                    Text(portfolioValueLabel)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(BSmartColor.primaryText)
                        .monospacedDigit()
                }

                Spacer()

                Text("1M".bSmartLocalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .padding(.horizontal, BSmartSpacing.small)
                    .padding(.vertical, 5)
                    .background(BSmartColor.recessed)
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            }

            if portfolioChartPoints.count > 1 {
                portfolioPerformance
                portfolioChart
            } else {
                portfolioHistoryUnavailable
            }

            BSmartMetricStrip(metrics: portfolioMetrics)
        }
        .padding(BSmartSpacing.medium)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    private var portfolioValueLabel: String {
        guard model.hasAnyPortfolioValuation else { return "Not available".bSmartLocalized }
        return model.portfolioValue.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private var portfolioChartPoints: [PortfolioValuePoint] {
        guard model.hasCompletePortfolioValuation,
              model.portfolioValue > 0,
              let latest = model.portfolioHistory.last,
              abs(latest.value - model.portfolioValue) / model.portfolioValue <= 0.02
        else { return [] }
        return model.portfolioHistory
    }

    private var portfolioPeriodChange: Double {
        guard let first = portfolioChartPoints.first else { return 0 }
        return model.portfolioValue - first.value
    }

    private var portfolioPeriodChangePercent: Double {
        guard let first = portfolioChartPoints.first, first.value > 0 else { return 0 }
        return portfolioPeriodChange / first.value
    }

    private var portfolioChartColor: Color {
        portfolioPeriodChange >= 0 ? BSmartColor.brand : BSmartColor.bear
    }

    private var portfolioPerformance: some View {
        HStack(spacing: BSmartSpacing.small) {
            Image(systemName: portfolioPeriodChange >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text(portfolioPeriodChange.formatted(
                .currency(code: "USD").precision(.fractionLength(0)).sign(strategy: .always())
            ))
            Text(portfolioPeriodChangePercent.formatted(
                .percent.precision(.fractionLength(1)).sign(strategy: .always())
            ))
            Text("past month".bSmartLocalized)
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(portfolioChartColor)
        .monospacedDigit()
    }

    private var portfolioChart: some View {
        Chart(portfolioChartPoints) { point in
            AreaMark(
                x: .value("Date", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [portfolioChartColor.opacity(0.28), portfolioChartColor.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.timestamp),
                y: .value("Value", point.value)
            )
            .foregroundStyle(portfolioChartColor)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: portfolioChartDomain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .chartPlotStyle { plot in
            plot.background(BSmartColor.recessed.opacity(0.45))
        }
        .frame(height: 132)
        .accessibilityLabel("Portfolio value over the past month".bSmartLocalized)
    }

    private var portfolioChartDomain: ClosedRange<Double> {
        let values = portfolioChartPoints.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.15, maximum * 0.005, 1)
        return (minimum - padding)...(maximum + padding)
    }

    private var portfolioHistoryUnavailable: some View {
        HStack(spacing: BSmartSpacing.small) {
            Image(systemName: "chart.xyaxis.line")
            Text("Portfolio history will appear after valuation snapshots are available.".bSmartLocalized)
        }
        .font(.caption)
        .foregroundStyle(BSmartColor.tertiaryText)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.medium)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
    }

    private var portfolioMetrics: [BSmartStripMetric] {
        [
            BSmartStripMetric(
                id: "positions",
                label: "Positions",
                value: "\(model.heldPositions.count)"
            ),
            BSmartStripMetric(
                id: "return",
                label: model.hasAnyPortfolioReturn ? "Total return" : "Declared allocation",
                value: model.hasAnyPortfolioReturn
                    ? model.portfolioGainPercent.formatted(
                        .percent.precision(.fractionLength(1)).sign(strategy: .always())
                    )
                    : declaredAllocationLabel,
                color: model.hasAnyPortfolioReturn
                    ? (model.portfolioGain >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    : BSmartColor.primaryText
            ),
            BSmartStripMetric(
                id: "unread",
                label: "Unread signals",
                value: "\(model.unreadPortfolioSignalCount)",
                color: model.unreadPortfolioSignalCount > 0 ? BSmartColor.bear : BSmartColor.primaryText
            ),
        ]
    }

    private var brokerageConnectionRow: some View {
        Button {
            isShowingBrokerageConnections = true
        } label: {
            HStack(spacing: BSmartSpacing.medium) {
                Image(systemName: model.linkedBrokerageAccounts.isEmpty ? "link.badge.plus" : "link.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(model.linkedBrokerageAccounts.isEmpty ? BSmartColor.secondaryText : BSmartColor.brand)
                    .frame(width: 38, height: 38)
                    .background(BSmartColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text((model.linkedBrokerageAccounts.isEmpty ? "Link a brokerage" : "Linked brokerages").bSmartLocalized)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)
                    Text(brokerageConnectionDetail)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if !model.linkedBrokerageAccounts.isEmpty {
                    Text("\(model.linkedBrokerageAccounts.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.pulseInk)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(BSmartColor.brand)
                        .clipShape(Circle())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("portfolio.link-brokerage-row")
    }

    private var brokerageConnectionDetail: String {
        guard !model.linkedBrokerageAccounts.isEmpty else {
            return "Read-only positions and cost basis".bSmartLocalized
        }
        let latest = model.linkedBrokerageAccounts.map(\.lastSyncedAt).max()
        guard let latest else { return "%d connected".bSmartLocalized(model.linkedBrokerageAccounts.count) }
        return "%d connected · synced %@".bSmartLocalized(
            model.linkedBrokerageAccounts.count,
            latest.bSmartRelativeTimestamp
        )
    }

    private func portfolioEntriesPanel(
        title: String,
        entries: [PortfolioPosition],
        emptyTitle: String,
        emptySymbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.secondaryText)
                .padding(.horizontal, BSmartSpacing.medium)
                .padding(.vertical, BSmartSpacing.small)

            if entries.isEmpty {
                Label(emptyTitle.bSmartLocalized, systemImage: emptySymbol)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BSmartSpacing.medium)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    portfolioEntryRow(entry)
                        .padding(.horizontal, BSmartSpacing.medium)

                    if index < entries.count - 1 {
                        Divider()
                            .overlay(BSmartColor.line)
                            .padding(.leading, 66)
                    }
                }
            }
        }
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    @ViewBuilder
    private func portfolioEntryRow(_ entry: PortfolioPosition) -> some View {
        if let ticker = model.intelligence(for: entry.ticker) {
            BSmartDetailNavigationLink(id: "portfolio-entry-\(entry.id)") {
                TickerIntelligenceView(ticker: ticker)
            } label: {
                positionRow(entry)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("portfolio.entry.\(entry.ticker)")
        } else {
            Button {
                editingEntry = entry
            } label: {
                positionRow(entry)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("portfolio.entry.\(entry.ticker)")
        }
    }

    private func positionRow(_ position: PortfolioPosition) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: position.ticker, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: BSmartSpacing.small) {
                    Text(position.ticker)
                        .font(.subheadline.weight(.bold))
                    if !position.isPosition {
                        BSmartTag(text: "Watching", color: BSmartColor.sky)
                    }
                }
                Text(position.companyName)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)
                let signalCount = model.signals(for: position.ticker).filter {
                    !model.signalUserState(for: $0.id).isRead
                }.count
                if signalCount > 0 {
                    Text("%d unread signals".bSmartLocalized(signalCount))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BSmartColor.pulse)
                }
            }

            Spacer(minLength: BSmartSpacing.small)

            if position.isPosition {
                positionMetrics(position)
            } else {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(position.currentPrice.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    intelligenceStatus(for: position.ticker)
                }
            }

        }
        .padding(.vertical, BSmartSpacing.xSmall)
        .contentShape(Rectangle())
    }

    private func positionMetrics(_ position: PortfolioPosition) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            if position.shares > 0 {
                Text(position.marketValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            } else if let weight = position.portfolioWeight {
                Text(weight.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            HStack(spacing: BSmartSpacing.small) {
                if position.averageCost > 0, position.shares > 0 {
                    Text(position.unrealizedGainPercent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                        .foregroundStyle(position.unrealizedGain >= 0 ? BSmartColor.brand : BSmartColor.bear)
                } else {
                    Text("Tracked")
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                if let weight = position.portfolioWeight {
                    Text(weight.formatted(.percent.precision(.fractionLength(0))))
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
        }
    }

    private func intelligenceStatus(for ticker: String) -> some View {
        let accountCount = model.accountUpdates(for: ticker).count
        let moneyCount = model.moneyMovements(for: ticker).count
        let sourceCount = (accountCount > 0 ? 1 : 0) + (moneyCount > 0 ? 1 : 0)
        let label = sourceCount > 0
            ? "%d evidence sources".bSmartLocalized(sourceCount)
            : "Monitoring".bSmartLocalized
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(sourceCount > 0 ? BSmartColor.brand : BSmartColor.secondaryText)
    }

    private var declaredAllocationLabel: String {
        guard model.declaredPortfolioWeight > 0 else { return "Not entered".bSmartLocalized }
        return model.declaredPortfolioWeight.formatted(.percent.precision(.fractionLength(0)))
    }
}
