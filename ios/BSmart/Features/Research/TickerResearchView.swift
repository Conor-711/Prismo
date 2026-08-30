import SwiftUI

private enum TickerIntelligenceSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Smart Activity"

    var id: Self { self }
}

struct TickerIntelligenceView: View {
    @EnvironmentObject private var model: AppModel
    let ticker: TickerIntelligence
    @State private var editingPosition: PortfolioPosition?
    @State private var isAddingTicker = false
    @State private var selection: TickerIntelligenceSection = .overview
    @State private var activitySnapshot: TickerSmartActivitySnapshot?

    private struct ActivityRevision: Hashable {
        let ticker: String
        let accountCount: Int
        let firstAccountID: UUID?
        let lastAccountID: UUID?
        let moneyCount: Int
        let firstMoneyID: UUID?
        let lastMoneyID: UUID?
        let price: Double
        let dataAsOf: Date
    }

    private var activityRevision: ActivityRevision {
        ActivityRevision(
            ticker: ticker.ticker,
            accountCount: model.smartAccountUpdates.count,
            firstAccountID: model.smartAccountUpdates.first?.id,
            lastAccountID: model.smartAccountUpdates.last?.id,
            moneyCount: model.smartMoneyMovements.count,
            firstMoneyID: model.smartMoneyMovements.first?.id,
            lastMoneyID: model.smartMoneyMovements.last?.id,
            price: ticker.currentPrice,
            dataAsOf: ticker.dataAsOf
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                quoteHeader
                sectionPicker

                switch selection {
                case .overview:
                    if let activitySnapshot {
                        overview(snapshot: activitySnapshot)
                    } else {
                        activityLoadingPlaceholder
                    }
                case .activity:
                    if let activitySnapshot {
                        TickerSmartActivityFeed(activities: activitySnapshot.activities)
                    } else {
                        activityLoadingPlaceholder
                    }
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .accessibilityIdentifier("ticker-intelligence.\(ticker.ticker)")
        .navigationTitle(ticker.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let position = model.position(for: ticker.ticker) {
                    Button {
                        editingPosition = position
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit tracked ticker")
                    .accessibilityIdentifier("ticker-intelligence.edit")
                } else {
                    Button {
                        isAddingTicker = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Add to portfolio or watchlist")
                    .accessibilityIdentifier("ticker-intelligence.track")
                }
            }
        }
        .sheet(item: $editingPosition) { position in
            AddPositionView(position: position)
                .environmentObject(model)
        }
        .sheet(isPresented: $isAddingTicker) {
            AddPositionView(
                prefilledTicker: ticker.ticker,
                prefilledCompanyName: ticker.companyName,
                initialKind: .watchlist
            )
            .environmentObject(model)
        }
        .task(id: activityRevision) {
            await rebuildActivitySnapshot(for: activityRevision)
        }
        .bSmartDetailPage()
        .bSmartPage()
    }

    private func overview(snapshot: TickerSmartActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.large) {
            TickerPriceSmartActivityPanel(
                ticker: ticker,
                model: snapshot.priceModel
            )

            TickerSmartActivityFeed(
                activities: snapshot.activities,
                title: "Recent Smart Activity",
                maximumItems: 4,
                showsFilter: false
            )

            Button {
                selection = .activity
            } label: {
                HStack {
                    Text("View all Smart Activity".bSmartLocalized)
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                }
                .foregroundStyle(BSmartColor.brand)
                .padding(.horizontal, BSmartSpacing.medium)
                .frame(minHeight: 44)
                .background(BSmartColor.brand.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .stroke(BSmartColor.brand.opacity(0.35), lineWidth: 0.6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ticker-intelligence.view-all-activity")
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(TickerIntelligenceSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.rawValue.bSmartLocalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(selection == section ? BSmartColor.pulse.opacity(0.09) : Color.clear)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == section ? BSmartColor.pulse : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    private var quoteHeader: some View {
        HStack(alignment: .center, spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: ticker.ticker, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(ticker.companyName)
                    .font(.headline)
                Text(
                    "Data as of %@".bSmartLocalized(
                        ticker.dataAsOf.bSmartDataTimestamp
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ticker.currentPrice.formatted(.currency(code: "USD")))
                    .font(.headline)
                    .monospacedDigit()
                Text(ticker.dayChangePercent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ticker.dayChangePercent >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    .monospacedDigit()
            }
        }
    }

    private var activityLoadingPlaceholder: some View {
        VStack(spacing: BSmartSpacing.medium) {
            ProgressView()
                .tint(BSmartColor.brand)
            Text("Preparing Smart Activity".bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .bSmartSurface()
        .accessibilityIdentifier("ticker-intelligence.activity-loading")
    }

    private func rebuildActivitySnapshot(for revision: ActivityRevision) async {
        let accountUpdates = model.accountUpdates(for: ticker.ticker)
        let moneyMovements = model.moneyMovements(for: ticker.ticker)
        let ticker = ticker

        let snapshot = await Task.detached(priority: .userInitiated) {
            TickerSmartActivitySnapshot(
                ticker: ticker,
                accountUpdates: accountUpdates,
                moneyMovements: moneyMovements
            )
        }.value

        guard !Task.isCancelled, activityRevision == revision else { return }
        activitySnapshot = snapshot
    }
}
