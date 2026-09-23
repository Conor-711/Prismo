import SwiftUI

struct AllTickersView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @State private var query = ""
    @State private var catalog: [AppTickerCatalogEntry] = []
    @State private var filter: TickerDirectoryFilter = .all
    @State private var sort: TickerDirectorySort = .volume
    @State private var sections = TickerDirectorySections(catalog: [])
    @State private var showsSortOptions = false
    var isActive: Bool = true
    var onSearchFocusChanged: (Bool) -> Void = { _ in }

    var body: some View {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        LazyVStack(alignment: .leading, spacing: 12) {
            TickerDirectorySearchField(isActive: isActive, onQueryChanged: { query = $0 },
                                       onFocusChanged: onSearchFocusChanged)
            filterPicker
            HStack {
                Text("All tickers".bSmartLocalized).font(.headline)
                Spacer()
                if !trading.isLoadingCatalog || !sections.entries.isEmpty {
                    Text("\(sections.entries.count) / \(catalog.count)")
                        .font(.caption).monospacedDigit().foregroundStyle(BSmartColor.secondaryText)
                }
                sortPicker
            }
            if showsSortOptions { sortOptions }
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
            if sections.entries.isEmpty && !trading.isLoadingCatalog {
                ContentUnavailableView.search(text: search)
            }
            if trading.isLoadingCatalog && sections.entries.isEmpty {
                BSmartSkeletonRows(style: .simple, count: 6)
            } else {
                tickerRows(sections.entries)
            }
        }
        .background(BSmartColor.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("portfolio.all-tickers")
        .onChange(of: isActive, initial: true) { _, active in
            if active { refreshDirectory() } else { showsSortOptions = false }
        }
        .onChange(of: model.lastDataRefreshAt) { _, _ in refreshDirectory() }
        .onChange(of: trading.marketCatalog) { _, _ in
            refreshDirectory()
        }
        .onChange(of: filter) { _, _ in updateResults() }
        .onChange(of: sort) { _, _ in updateResults() }
        .onChange(of: query) { _, _ in updateResults() }
        .task { if trading.marketCatalog.isEmpty { await trading.loadFullCatalog() } }
    }

    private func refreshDirectory() {
        guard isActive else { return }
        catalog = model.tickerCatalog(markets: trading.marketCatalog)
        updateResults()
    }

    private func updateResults() {
        sections = TickerDirectorySections(catalog: catalog, query: query, filter: filter, sort: sort)
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TickerDirectoryFilter.allCases) { option in
                    Button { filter = option } label: {
                        Text(option.title.bSmartLocalized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(filter == option ? BSmartColor.primaryText : BSmartColor.secondaryText)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(filter == option ? BSmartColor.recessed : BSmartColor.ink,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(BSmartColor.line, lineWidth: filter == option ? 1 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                    .accessibilityIdentifier("portfolio.ticker-filter.\(option.rawValue)")
                }
            }
        }
    }

    private var sortPicker: some View {
        Button { showsSortOptions.toggle() } label: {
            HStack(spacing: 5) {
                Text(sort.title.bSmartLocalized)
                Image(systemName: showsSortOptions ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityLabel("Sort by %@".bSmartLocalized(sort.title.bSmartLocalized))
        .accessibilityIdentifier("portfolio.ticker-sort")
    }

    private var sortOptions: some View {
        VStack(spacing: 0) {
            ForEach(TickerDirectorySort.allCases) { option in
                Button {
                    sort = option
                    showsSortOptions = false
                } label: {
                    HStack(spacing: 10) {
                        Text(option.title.bSmartLocalized)
                        Spacer()
                        if sort == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(BSmartColor.brand)
                        }
                    }
                    .font(.system(size: 14, weight: sort == option ? .semibold : .medium))
                    .foregroundStyle(BSmartColor.primaryText)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sort == option ? .isSelected : [])
                .accessibilityIdentifier("portfolio.ticker-sort.\(option.rawValue)")
                if option != TickerDirectorySort.allCases.last {
                    Divider().overlay(BSmartColor.line).padding(.leading, 14)
                }
            }
        }
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BSmartColor.line, lineWidth: 0.75))
    }

    @ViewBuilder private func tickerRows(_ entries: [AppTickerCatalogEntry]) -> some View {
        ForEach(entries) { entry in
            BSmartDetailNavigationLink(id: "ticker-\(entry.symbol)") {
                TickerDestinationView(symbol: entry.symbol)
            } label: {
                BSmartMarketRow(entry: entry, compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("portfolio.ticker.\(entry.symbol)")
        }
    }
}

private struct TickerDirectorySearchField: View {
    let isActive: Bool
    let onQueryChanged: (String) -> Void
    let onFocusChanged: (Bool) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium)).foregroundStyle(BSmartColor.secondaryText)
            TextField("Ticker or company".bSmartLocalized, text: $text)
                .font(.body).focused($focused).submitLabel(.search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit { focused = false }
                .accessibilityIdentifier("portfolio.ticker-search")
            if !text.isEmpty {
                Button { text = ""; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 28, height: 36)
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                .accessibilityLabel("Clear".bSmartLocalized)
            }
            if focused {
                Button { focused = false } label: {
                    Image(systemName: "keyboard.chevron.compact.down").frame(width: 28, height: 36)
                }
                .buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                .accessibilityLabel("Dismiss keyboard".bSmartLocalized)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(minHeight: 48)
        .background(BSmartKeyboardInputRegion())
        .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.softDivider, lineWidth: 0.75) }
        .task(id: text) {
            if !text.isEmpty {
                do { try await Task.sleep(for: .milliseconds(120)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            onQueryChanged(text)
        }
        .onChange(of: focused) { _, value in onFocusChanged(value) }
        .onChange(of: isActive) { _, active in if !active { focused = false } }
        .onDisappear { focused = false; onFocusChanged(false) }
    }
}
