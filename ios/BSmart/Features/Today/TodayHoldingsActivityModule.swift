import SwiftUI

struct TodayHoldingsActivityModule: View {
    var body: some View {
        TodayHoldingsActivityContent(isPreview: true)
            .accessibilityIdentifier("today.holdings.module")
    }
}

struct TodayHoldingsActivityCollectionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            TodayHoldingsActivityContent(isPreview: false)
                .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .refreshable { await model.refreshLiveIntelligence() }
        .navigationTitle("For your holdings".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("holdings.collection")
    }
}

private struct TodayHoldingsActivityContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let isPreview: Bool
    @State private var snapshot = TodayHoldingsActivity()
    @State private var source: TodayActivityFilter = .all
    @State private var ticker: String?
    @State private var isAddingPosition = false

    private var displayed: [TodayActivity] {
        isPreview ? snapshot.preview(source: source) : snapshot.filtered(source: source, ticker: ticker)
    }

    private var displayedTickers: [String] {
        var seen = Set<String>()
        return displayed.map { TodayHoldingsActivity.symbol($0.ticker) }
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if isPreview {
                BSmartDetailNavigationLink(id: "today-holdings-library") {
                    TodayHoldingsActivityCollectionView()
                } label: {
                    TodayEditorialSectionTitle(title: "For your holdings", showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.holdings.title")
            }
            if !snapshot.tickers.isEmpty {
                filters
            }

            if model.isLoading && snapshot.activities.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 90)
            } else if snapshot.tickers.isEmpty {
                emptyState(title: "Add holdings to see relevant updates", symbol: "chart.pie") {
                    Button { isAddingPosition = true } label: {
                        Label("Add holding".bSmartLocalized, systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(BSmartColor.brand)
                    .accessibilityIdentifier("holdings.add")
                }
            } else if displayed.isEmpty {
                emptyState(title: "No matching updates in the last 30 days", symbol: "text.bubble") {
                    if source != .all || ticker != nil {
                        Button("Clear filters".bSmartLocalized) { source = .all; ticker = nil }
                            .tint(BSmartColor.brand)
                    }
                }
                .accessibilityIdentifier("holdings.empty")
            } else {
                ForEach(displayedTickers, id: \.self) { symbol in
                    VStack(alignment: .leading, spacing: 10) {
                        TodayHoldingGroupHeader(ticker: symbol, weight: snapshot.weights[symbol])
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(displayed.filter { TodayHoldingsActivity.symbol($0.ticker) == symbol }) { activity in
                            TodayHoldingsActivityRow(activity: activity, weight: nil, showsTicker: false)
                        }
                    }
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("holdings.group.\(symbol)")
                }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: model.positions) { rebuild() }
        .onChange(of: model.smartAccountUpdates) { rebuild() }
        .onChange(of: model.smartMoneyMovements) { rebuild() }
        .onChange(of: scenePhase) { if scenePhase == .active { rebuild() } }
        .sheet(isPresented: $isAddingPosition) {
            AddPositionView().environmentObject(model)
        }
    }

    private var filters: some View {
        VStack(spacing: 14) {
            Picker("Sources".bSmartLocalized, selection: $source) {
                ForEach(TodayActivityFilter.allCases) { filter in
                    Text(filter == .all ? "All sources".bSmartLocalized : filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("holdings.source-filter")
            if !isPreview {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        tickerButton(nil)
                        ForEach(snapshot.tickers, id: \.self) { tickerButton($0) }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func tickerButton(_ value: String?) -> some View {
        Button { ticker = value } label: {
            HStack(spacing: 6) {
                if let value { BSmartAssetMark(ticker: value, size: 22) }
                Text(value ?? "All holdings".bSmartLocalized)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .foregroundStyle(ticker == value ? BSmartColor.brand : BSmartColor.secondaryText)
            .background(ticker == value ? BSmartColor.brand.opacity(0.10) : BSmartColor.surface,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ticker == value ? BSmartColor.brand : BSmartColor.line))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("holdings.ticker.\(value ?? "all")")
        .accessibilityAddTraits(ticker == value ? .isSelected : [])
    }

    private func emptyState<Content: View>(title: String, symbol: String,
                                          @ViewBuilder action: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title.bSmartLocalized, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
            action()
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rebuild() {
        snapshot = .make(positions: model.positions, accountUpdates: model.smartAccountUpdates,
                         moneyMovements: model.smartMoneyMovements)
        if let ticker, !snapshot.tickers.contains(ticker) { self.ticker = nil }
    }
}
