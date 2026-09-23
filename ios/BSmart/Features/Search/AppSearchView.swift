import SwiftUI

struct AppSearchView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var trading: HyperliquidTradingStore
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = AppSearchStore()
    @State private var query = ""
    @State private var category = AppSearchCategory.all
    @State private var overview = AppSearchOverviewData()
    @State private var indexRevision = 0
    @State private var visibleLimit = 30
    @State private var selection: AppSearchItem?
    @FocusState private var focused: Bool

    private var active: Bool { router.selection == .search && phase == .active }
    private var text: String { AppSearchQuery(query).text }
    private var canSearchUsers: Bool { account.identity != nil || preview != nil }
    private var preview: TradeFeedDemoData? {
        #if DEBUG
        if model.isUsingDemoData && ProcessInfo.processInfo.arguments.contains("--ui-search-fixture") {
            return AppSearchPreview.data
        }
        #endif
        return nil
    }
    private struct CatalogKey: Hashable {
        let active: Bool
        let refreshed: Date?
        let markets, evidence: Int
    }
    private struct QueryKey: Hashable {
        let active: Bool
        let query: String
        let revision: Int
        let account: UUID?
    }
    private var catalogKey: CatalogKey {
        CatalogKey(active: active, refreshed: model.lastDataRefreshAt,
                   markets: trading.marketCatalog.count,
                   evidence: model.smartAccountEvidenceByAuthor.values.reduce(0) { $0 + $1.count })
    }
    private var queryKey: QueryKey {
        QueryKey(active: active, query: query, revision: indexRevision, account: account.identity?.id)
    }

    var body: some View {
        NavigationStack {
            page
                .background(BSmartColor.ink)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $selection) { AppSearchDestination(item: $0, preview: preview) }
        }
        .bSmartPage()
        .accessibilityIdentifier("search.screen")
        .task(id: active) {
            if active && trading.marketCatalog.isEmpty { await trading.loadFullCatalog() }
        }
        .task(id: catalogKey) { await refreshIndex() }
        .task(id: queryKey) { await runSearch() }
        .onChange(of: account.identity?.id, initial: true) { old, id in
            store.setAccount(id)
            if old != id { query = ""; category = .all; selection = nil }
        }
        .onChange(of: query) { _, _ in visibleLimit = 30 }
        .onChange(of: category) { _, _ in visibleLimit = 30; focused = false }
        .onDisappear { focused = false; store.cancel() }
    }

    private var page: some View {
        VStack(spacing: 0) {
            searchField.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            if !text.isEmpty { filters }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if text.isEmpty || category == .all || category == .tickers { marketStatus }
                    if text.count > 80 {
                        Text("Search is limited to 80 characters".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                    } else if text.isEmpty {
                        history
                        AppSearchOverview(data: overview, open: open)
                        userSection(overview: true)
                    } else {
                        results
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 110)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { focused = false })
            .accessibilityIdentifier("search.scroll")
        }
    }

    private func refreshIndex() async {
        guard active else { return }
        let items = model.searchItems(markets: trading.marketCatalog)
        overview = AppSearchOverviewData(items: items,
            trendingSymbols: TodayViewpointPackage.packages(from: model.smartAccountUpdates, maximumPackages: 6).map(\.ticker))
        await store.replaceIndex(items: items)
        guard !Task.isCancelled else { return }
        indexRevision += 1
    }

    private func runSearch() async {
        guard active else { focused = false; store.cancel(); return }
        if canSearchUsers {
            await store.search(query, fetchUsers: { query, offset in try await fetchUsers(query, offset) })
        } else {
            await store.search(query, fetchUsers: nil)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.body.weight(.medium)).foregroundStyle(BSmartColor.secondaryText)
            TextField("Search tickers, views, people".bSmartLocalized, text: $query)
                .font(.body).focused($focused).submitLabel(.search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onSubmit { store.remember(query); focused = false }
                .accessibilityIdentifier("search.input")
            if !query.isEmpty {
                Button { query = ""; category = .all; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 28, height: 36)
                }.buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityLabel("Clear".bSmartLocalized).accessibilityIdentifier("search.clear")
            }
            if focused {
                Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 28, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss keyboard".bSmartLocalized)
                    .accessibilityIdentifier("search.dismiss-keyboard")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(minHeight: 48)
        .background(BSmartKeyboardInputRegion())
        .background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.softDivider, lineWidth: 0.75) }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(AppSearchCategory.allCases) { value in
                    Button { category = value } label: {
                        Text(value.title.bSmartLocalized).font(.subheadline.weight(value == category ? .bold : .medium))
                            .foregroundStyle(value == category ? BSmartColor.primaryText : BSmartColor.secondaryText)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if value == category { Rectangle().fill(BSmartColor.brand).frame(height: 2) }
                            }
                    }.buttonStyle(.plain).accessibilityAddTraits(value == category ? .isSelected : [])
                        .accessibilityIdentifier("search.filter.\(value.rawValue)")
                }
            }.padding(.horizontal, 20)
        }.overlay(alignment: .bottom) { Divider().overlay(BSmartColor.softDivider) }
    }

    @ViewBuilder private var results: some View {
        if store.searching {
            BSmartSkeletonRows(style: .simple, count: 5).accessibilityIdentifier("search.loading")
        } else {
            ForEach(AppSearchCategory.allCases.filter { $0 != .all && $0 != .users && (category == .all || category == $0) }) { group in
                let items = store.results.filter { $0.category == group }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionHeader(group.title, more: items.count > 5 && category == .all ? group : nil)
                        rows(Array(items.prefix(category == .all ? 5 : visibleLimit)))
                        if category != .all && items.count > visibleLimit {
                            Button("Load more".bSmartLocalized) { visibleLimit += 30 }
                                .padding(.vertical, 12).accessibilityIdentifier("search.load-more")
                        }
                    }.accessibilityElement(children: .contain).accessibilityIdentifier("search.section.\(group.rawValue)")
                }
            }
            if category == .all || category == .users { userSection(overview: false) }
            if noResults { ContentUnavailableView.search(text: text).accessibilityIdentifier("search.empty") }
        }
    }

    private var noResults: Bool {
        guard !store.searching else { return false }
        if category == .all || category == .tickers,
           trading.isLoadingCatalog || (trading.marketCatalog.isEmpty && trading.errorMessage != nil) { return false }
        let local = store.results.filter { category == .all || $0.category == category }
        if category != .all && category != .users { return local.isEmpty }
        return local.isEmpty && store.users.isEmpty && !store.usersLoading && !store.usersFailed && canSearchUsers
    }

    @ViewBuilder private var marketStatus: some View {
        if trading.marketCatalog.isEmpty {
            if trading.isLoadingCatalog {
                BSmartSkeletonRows(style: .simple, count: 1)
                    .accessibilityIdentifier("search.markets.loading")
            } else if trading.errorMessage != nil {
                HStack {
                    Text("Market search unavailable".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                    Button { Task { await trading.loadFullCatalog() } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }.accessibilityLabel("Retry".bSmartLocalized).accessibilityIdentifier("search.markets.retry")
                }
            }
        }
    }

    @ViewBuilder private func userSection(overview: Bool) -> some View {
        if !store.users.isEmpty || store.usersLoading || store.usersFailed || (!overview && !canSearchUsers) {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader(overview ? "Community" : "Users", more: !overview && store.users.count > 5 && category == .all ? .users : nil)
                rows(Array(store.users.prefix(overview ? 3 : category == .all ? 5 : store.users.count)).map(AppSearchItem.user))
                if store.usersLoading && store.users.isEmpty { BSmartSkeletonRows(style: .chat, count: 2) }
                if store.usersFailed {
                    HStack {
                        Text("User search unavailable".bSmartLocalized).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        Spacer()
                        Button { Task { await store.retryUsers(fetch: fetchUsers) } } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                        }.accessibilityLabel("Retry".bSmartLocalized).accessibilityIdentifier("search.users.retry")
                    }
                } else if !canSearchUsers {
                    NavigationLink("Sign in to search users".bSmartLocalized) { TradingAccountView() }
                        .font(.subheadline).padding(.vertical, 12)
                } else if !overview && category == .users && store.nextUserOffset != nil && !store.usersLoading {
                    Button("Load more".bSmartLocalized) { Task { await store.moreUsers(fetch: fetchUsers) } }
                        .padding(.vertical, 12).accessibilityIdentifier("search.users.more")
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("search.section.users")
        }
    }

    private func sectionHeader(_ title: String, more: AppSearchCategory?) -> some View {
        HStack {
            Text(title.bSmartLocalized).font(.headline)
            Spacer()
            if let more {
                Button { category = more; focused = false } label: { Image(systemName: "chevron.right").frame(width: 40, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("View all".bSmartLocalized)
            }
        }.padding(.bottom, 6)
    }
    private func rows(_ items: [AppSearchItem]) -> some View {
        ForEach(items) { item in
            Button { open(item) } label: { AppSearchResultRow(item: item) }
                .buttonStyle(.plain).accessibilityIdentifier("search.result.\(item.id)")
            if item.category != .opinions { Divider().overlay(BSmartColor.softDivider) }
        }
    }
    @ViewBuilder private var history: some View {
        if !store.recentQueries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent searches".bSmartLocalized).font(.headline)
                    Spacer()
                    Button { store.clearHistory() } label: { Image(systemName: "trash").frame(width: 40, height: 40) }
                        .accessibilityLabel("Clear search history".bSmartLocalized).accessibilityIdentifier("search.history.clear")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(store.recentQueries, id: \.self) { value in
                            Button { query = value; category = .all } label: {
                                Label(value, systemImage: "clock.arrow.circlepath").font(.subheadline).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    private func open(_ item: AppSearchItem) {
        focused = false; store.remember(query); selection = item
    }
    private func fetchUsers(_ query: String, _ offset: Int) async throws -> PublicProfileSearchPage {
        if let preview {
            let found = AppSearchIndex(items: preview.items.map { .user($0.trader) }).search(query)
            let people = found.compactMap { item -> FeedPublicProfile? in if case .user(let p) = item { return p }; return nil }
            return .init(items: Array(people.dropFirst(offset).prefix(20)), nextOffset: nil)
        }
        return try await PublicProfileSearchClient(account: account).search(query: query, offset: offset)
    }
}

#if DEBUG
private enum AppSearchPreview { static let data = try? TradeFeedDemoData.load() }
#endif
