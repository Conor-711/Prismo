import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @State private var isAddingEntry = false
    @State private var isShowingSettings = false
    @State private var editingEntry: PortfolioPosition?

    var body: some View {
        NavigationStack {
            List {
                if !model.heldPositions.isEmpty {
                    Section {
                        portfolioSummary
                            .listRowInsets(EdgeInsets(
                                top: BSmartSpacing.medium,
                                leading: BSmartSpacing.large,
                                bottom: BSmartSpacing.small,
                                trailing: BSmartSpacing.large
                            ))
                            .listRowBackground(BSmartColor.ink)
                            .listRowSeparator(.hidden)
                    }
                }

                entrySection(
                    title: "Positions",
                    entries: model.heldPositions,
                    emptyTitle: "No positions yet",
                    emptySymbol: "chart.pie"
                )

                entrySection(
                    title: "Watchlist",
                    entries: model.watchlist,
                    emptyTitle: "No watched tickers",
                    emptySymbol: "eye"
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BSmartColor.ink)
            .navigationTitle(language.localized("Portfolio"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("portfolio.screen")
            .navigationDestination(for: TickerIntelligence.self) { ticker in
                TickerIntelligenceView(ticker: ticker)
            }
            .navigationDestination(for: PortfolioSignal.self) { signal in
                EventDetailView(signal: signal)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
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
            .sheet(item: $editingEntry) { entry in
                AddPositionView(position: entry)
                    .environmentObject(model)
            }
        }
        .bSmartPage()
    }

    private var portfolioSummary: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            BSmartMetricStrip(metrics: [
                BSmartStripMetric(
                    id: "positions",
                    label: "Positions",
                    value: "\(model.heldPositions.count)"
                ),
                BSmartStripMetric(
                    id: "allocation",
                    label: model.hasAnyPortfolioValuation ? "Market value" : "Declared allocation",
                    value: model.hasAnyPortfolioValuation
                        ? model.portfolioValue.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                        : declaredAllocationLabel
                ),
                BSmartStripMetric(
                    id: "unread",
                    label: "Unread signals",
                    value: "\(model.unreadPortfolioSignalCount)",
                    color: model.unreadPortfolioSignalCount > 0 ? BSmartColor.bear : BSmartColor.primaryText
                ),
            ])

            if model.hasAnyPortfolioReturn {
                HStack(spacing: BSmartSpacing.small) {
                    Image(systemName: model.portfolioGain >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("Total return".bSmartLocalized)
                    Spacer()
                    Text(model.portfolioGain.formatted(.currency(code: "USD").precision(.fractionLength(0)).sign(strategy: .always())))
                    Text(model.portfolioGainPercent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.portfolioGain >= 0 ? BSmartColor.brand : BSmartColor.bear)
                .monospacedDigit()
                .padding(.horizontal, BSmartSpacing.xSmall)
            }
        }
    }

    private func entrySection(
        title: String,
        entries: [PortfolioPosition],
        emptyTitle: String,
        emptySymbol: String
    ) -> some View {
        Section(title.bSmartLocalized) {
            if entries.isEmpty {
                Label(emptyTitle.bSmartLocalized, systemImage: emptySymbol)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, BSmartSpacing.medium)
                    .listRowBackground(BSmartColor.ink)
            } else {
                ForEach(entries) { entry in
                    portfolioEntryRow(entry)
                    .listRowBackground(BSmartColor.surface)
                    .listRowSeparatorTint(BSmartColor.line)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.deletePosition(id: entry.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingEntry = entry
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(BSmartColor.sky)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func portfolioEntryRow(_ entry: PortfolioPosition) -> some View {
        HStack(spacing: BSmartSpacing.small) {
            if let ticker = model.intelligence(for: entry.ticker) {
                NavigationLink(value: ticker) {
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

            Menu {
                Button {
                    editingEntry = entry
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    model.deletePosition(id: entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .frame(width: 32, height: 36)
            }
            .accessibilityLabel("Actions for %@".bSmartLocalized(entry.ticker))
            .accessibilityIdentifier("portfolio.entry-actions.\(entry.ticker)")
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
                    relationshipLabel(for: position.ticker)
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

    private func relationshipLabel(for ticker: String) -> some View {
        let intelligence = model.intelligence(for: ticker)
        return Text((intelligence?.relationship.label ?? "Monitoring").bSmartLocalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(intelligence?.direction.color ?? BSmartColor.secondaryText)
    }

    private var declaredAllocationLabel: String {
        guard model.declaredPortfolioWeight > 0 else { return "Not entered".bSmartLocalized }
        return model.declaredPortfolioWeight.formatted(.percent.precision(.fractionLength(0)))
    }
}
