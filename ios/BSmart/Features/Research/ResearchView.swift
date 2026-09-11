import SwiftUI

struct AllTickersView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    var isActive: Bool = true
    var onSearchFocusChanged: (Bool) -> Void = { _ in }

    var body: some View {
        let catalog = model.tickerCatalog(markets: trading.marketCatalog)
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = TickerDirectorySections(
            catalog: catalog,
            trendingSymbols: TodayViewpointPackage.packages(from: model.smartAccountUpdates, maximumPackages: 10).map(\.ticker),
            query: search
        )
        LazyVStack(alignment: .leading, spacing: 16) {
            searchField
            if !sections.trending.isEmpty {
                Text("Trending Tickers".bSmartLocalized)
                    .font(.headline)
                    .accessibilityIdentifier("portfolio.trending.title")
                tickerRows(sections.trending)
            }
            HStack {
                Text("All tickers".bSmartLocalized).font(.headline)
                Spacer()
                Text("\(sections.matchCount) / \(catalog.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(BSmartColor.secondaryText)
                if trading.isLoadingCatalog { ProgressView().tint(BSmartColor.brand) }
            }
            if let error = trading.errorMessage, !trading.isLoadingCatalog {
                HStack {
                    Text(error).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                    Button { Task { await trading.loadFullCatalog() } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Retry".bSmartLocalized)
                }
            }
            if sections.matchCount == 0 && !trading.isLoadingCatalog {
                ContentUnavailableView.search(text: search)
            }
            tickerRows(sections.remaining)
        }
        .background(BSmartColor.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portfolio.all-tickers")
        .onChange(of: searchFocused) { _, focused in onSearchFocusChanged(focused) }
        .onChange(of: isActive) { _, active in if !active { searchFocused = false } }
        .onDisappear { searchFocused = false; onSearchFocusChanged(false) }
        .task { if trading.marketCatalog.isEmpty { await trading.loadFullCatalog() } }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(BSmartColor.tertiaryText)
            TextField("Ticker or company".bSmartLocalized, text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .accessibilityIdentifier("portfolio.ticker-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear".bSmartLocalized)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func tickerRows(_ entries: [AppTickerCatalogEntry]) -> some View {
        ForEach(entries) { entry in
            BSmartDetailNavigationLink(id: "ticker-\(entry.symbol)") {
                TickerDestinationView(symbol: entry.symbol)
            } label: {
                BSmartMarketRow(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("portfolio.ticker.\(entry.symbol)")
            Divider().overlay(BSmartColor.line)
        }
    }
}
