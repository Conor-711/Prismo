import SwiftUI

struct TodayHoldingsActivityModule: View {
    var refreshID: UUID? = nil

    var body: some View {
        TodayHoldingsActivityContent(isPreview: true, refreshID: refreshID)
    }
}

struct TodayHoldingsActivityCollectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var refreshID = UUID()

    var body: some View {
        ScrollView {
            TodayHoldingsActivityContent(isPreview: false, refreshID: refreshID)
                .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .refreshable {
            await model.refreshLiveIntelligence()
            refreshID = UUID()
        }
        .navigationTitle("For your holdings".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("holdings.collection")
    }
}

private struct TodayHoldingsActivityContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    let isPreview: Bool
    let refreshID: UUID?
    @State private var snapshot = TodayHoldingsActivity()
    @State private var livePositions: [TradingPositionRow] = []
    @State private var liveScope: String?
    @State private var liveError: String?
    @State private var isLoadingLivePositions = false
    @State private var holdingsRequest = UUID()
    @State private var source: TodayActivityFilter = .all
    @State private var ticker: String?
    @State private var isAddingPosition = false

    private var displayed: [TodayActivity] {
        isPreview ? snapshot.preview(source: .accounts) : snapshot.filtered(source: source, ticker: ticker)
    }

    private var displayedTickers: [String] {
        if !isPreview && source == .all {
            return ticker.map { [$0] } ?? snapshot.tickers
        }
        var seen = Set<String>()
        return displayed.map { TodayHoldingsActivity.symbol($0.ticker) }
            .filter { seen.insert($0).inserted }
    }

    private var scope: String { account.identity?.id.uuidString ?? (account.isTestSession ? "test" : "guest") }

    var body: some View {
        Group {
            if isPreview {
                VStack(alignment: .leading, spacing: 12) { contentItems }
            } else {
                LazyVStack(alignment: .leading, spacing: 12) { contentItems }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: model.positions) { rebuild() }
        .onChange(of: model.smartAccountUpdates) { rebuild() }
        .onChange(of: model.smartMoneyMovements) { rebuild() }
        .onChange(of: scenePhase) { if scenePhase == .active { rebuild() } }
        .task(id: "\(scope)-\(account.walletSessionRevision)-\(router.selection == .today)-\(scenePhase == .active)-\(refreshID?.uuidString ?? "")") {
            if liveScope != scope {
                liveScope = scope
                livePositions = []
                liveError = nil
                rebuild()
            }
            guard router.selection == .today, scenePhase == .active else {
                holdingsRequest = UUID()
                isLoadingLivePositions = false
                return
            }
            await refreshHoldings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bSmartTradeFilled)) { _ in
            guard router.selection == .today, scenePhase == .active else { return }
            Task { await refreshHoldings() }
        }
        .sheet(isPresented: $isAddingPosition) {
            AddPositionView().environmentObject(model)
        }
    }

    @ViewBuilder private var contentItems: some View {
            if isPreview {
                BSmartDetailNavigationLink(id: "today-holdings-library") {
                    TodayHoldingsActivityCollectionView()
                } label: {
                    TodayEditorialSectionTitle(title: "For your holdings", showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.holdings.title")
            }
            if !isPreview && !snapshot.tickers.isEmpty {
                filters
            }
            if !snapshot.inAppSides.isEmpty {
                inAppPositions
            }
            if isLoadingLivePositions && !snapshot.tickers.isEmpty {
                ProgressView("Loading holdings".bSmartLocalized)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("holdings.live.loading")
            }
            if let liveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(liveError).font(.caption)
                    Spacer(minLength: 4)
                    Button { Task { await refreshHoldings() } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 36, height: 36)
                    }
                    .disabled(isLoadingLivePositions)
                    .accessibilityLabel("Refresh".bSmartLocalized)
                }
                .foregroundStyle(BSmartColor.bear)
                .accessibilityIdentifier("holdings.live.error")
            }

            if (model.isLoading || isLoadingLivePositions) && snapshot.tickers.isEmpty {
                BSmartSkeletonRows(style: .simple, count: 3)
                    .accessibilityIdentifier("holdings.live.loading")
            } else if liveError != nil && snapshot.tickers.isEmpty {
                EmptyView()
            } else if snapshot.tickers.isEmpty {
                emptyState(title: "Add holdings to see relevant updates", symbol: "chart.pie") {
                    Button { isAddingPosition = true } label: {
                        Label("Add holding".bSmartLocalized, systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(BSmartColor.brand)
                    .accessibilityIdentifier("holdings.add")
                }
            } else if displayedTickers.isEmpty {
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
                        TodayHoldingGroupHeader(ticker: symbol, weight: snapshot.weights[symbol],
                                                inAppSide: snapshot.inAppSides[symbol])
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        let activities = displayed.filter { TodayHoldingsActivity.symbol($0.ticker) == symbol }
                        if activities.isEmpty {
                            Text("No matching updates in the last 30 days".bSmartLocalized)
                                .font(.subheadline)
                                .foregroundStyle(BSmartColor.secondaryText)
                        } else {
                            ForEach(activities) { activity in
                                TodayHoldingsActivityRow(activity: activity, weight: nil, showsTicker: false)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("holdings.group.\(symbol)")
                }
            }
    }

    private var inAppPositions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(snapshot.inAppSides.keys.sorted()), id: \.self) { symbol in
                    HStack(spacing: 6) {
                        BSmartAssetMark(ticker: symbol, size: 20)
                        Text(symbol).font(.caption.weight(.bold))
                        if let side = snapshot.inAppSides[symbol] {
                            Text(side.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(side == .both ? BSmartColor.secondaryText :
                                                 side == .short ? BSmartColor.bear : BSmartColor.bull)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BSmartColor.line))
                    .accessibilityIdentifier("holdings.live.\(symbol)")
                }
            }
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
                         moneyMovements: model.smartMoneyMovements, tradingPositions: livePositions)
        if let ticker, !snapshot.tickers.contains(ticker) { self.ticker = nil }
    }

    private func refreshHoldings() async {
        let request = UUID()
        holdingsRequest = request
        let currentScope = scope
        liveError = nil
        guard let accountID = account.identity?.id else {
            livePositions = []
            rebuild()
            return
        }
        isLoadingLivePositions = true
        defer { if holdingsRequest == request { isLoadingLivePositions = false } }
        do {
            let registration = try await account.walletRegistration()
            guard !Task.isCancelled, holdingsRequest == request, scope == currentScope,
                  registration.accountId == accountID else { return }
            guard let address = registration.address else {
                livePositions = []
                rebuild()
                return
            }
            let positions = TradingPositionsStore(service: account)
            let showPartial = livePositions.isEmpty
            await positions.refresh(wallet: .init(accountID: accountID, address: address, recoveryVerified: false),
                                    verifiedRegistration: registration, onProgress: { partial in
                guard showPartial, !Task.isCancelled, holdingsRequest == request,
                      scope == currentScope else { return }
                livePositions = partial
                rebuild()
            })
            guard !Task.isCancelled, holdingsRequest == request, scope == currentScope else { return }
            livePositions = positions.rows
            liveError = positions.errorMessage
        } catch {
            guard !Task.isCancelled, holdingsRequest == request, scope == currentScope else { return }
            liveError = "Positions could not be loaded. Your positions have not changed.".bSmartLocalized
        }
        rebuild()
    }
}
