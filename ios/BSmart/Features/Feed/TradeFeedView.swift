import SwiftUI

struct TradeFeedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TradeFeedStore()
    @State private var syncMessage: String?
    @State private var mode = DiscoverSection.popular
    @State private var popularRefresh = 0

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-feed-layout-preview") {
            FeedLayoutPreview()
        } else { liveContent }
        #else
        liveContent
        #endif
    }

    private var liveContent: some View {
        NavigationStack {
            DiscoverContent(selection: $mode, content: { section in
                if account.identity == nil {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle").font(.largeTitle)
                        NavigationLink { TradingAccountView() } label: {
                            Text("Sign in to view real trades".bSmartLocalized)
                        }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                } else {
                    if section == .popular {
                        PopularOpinionsView(demo: nil, refresh: popularRefresh, isActive: mode == .popular)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if let syncMessage {
                                Text(syncMessage.bSmartLocalized)
                                    .font(.footnote).foregroundStyle(BSmartColor.secondaryText)
                            }
                            TradeFeedContents(store: store, reload: { await load(reset: true) },
                                              loadMore: { await load(reset: false) })
                        }
                        .padding(.top, 12)
                    }
                }
            }, refresh: {
                if mode == .popular { popularRefresh += 1 }
                else { await load(reset: true) }
            })
            .navigationTitle("Discover".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .background(BSmartColor.ink)
            .accessibilityIdentifier("feed.screen")
            .task(id: "\(router.selection == .feed)-\(mode)-\(account.identity?.id.uuidString ?? "signed-out")-\(account.feedRevision)") {
                store.clear(); syncMessage = nil
                if router.selection == .feed { await load(reset: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && router.selection == .feed {
                    Task { await load(reset: true) }
                } else if phase == .background { store.clear() }
            }
        }
        .bSmartPage()
    }

    private func load(reset: Bool) async {
        guard router.selection == .feed, mode == .latest else { return }
        guard let identity = account.identity?.id else { store.clear(); return }
        if reset { syncMessage = nil }
        await store.load(reset: reset) { offset in
            return try await NativeTradeFeedClient(account: account).page(offset: offset)
        }
        guard !Task.isCancelled, account.identity?.id == identity,
              router.selection == .feed, mode == .latest, !store.failed else { return }
        if reset {
            do {
                let complete = try await NativeTradeFeedClient(account: account).synchronize(accountID: identity)
                guard !Task.isCancelled, account.identity?.id == identity,
                      router.selection == .feed, mode == .latest else { return }
                syncMessage = complete ? nil : "Trade verification is pending. Pull to refresh."
                if complete {
                    await store.load(reset: true) { try await NativeTradeFeedClient(account: account).page(offset: $0) }
                }
            } catch {
                if !Task.isCancelled, account.identity?.id == identity,
                   router.selection == .feed, mode == .latest {
                    syncMessage = "Trade verification could not refresh. Try again later."
                }
            }
        }
    }
}

struct TradeFeedContents: View {
    @ObservedObject var store: TradeFeedStore
    let reload: () async -> Void
    let loadMore: () async -> Void
    var demo: TradeFeedDemoData? = nil

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if store.failed {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark").font(.title2)
                    Text("Trade activity unavailable".bSmartLocalized).font(.headline)
                    Button("Retry".bSmartLocalized) { Task { await reload() } }
                        .frame(minHeight: 44).accessibilityIdentifier("feed.retry")
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .accessibilityIdentifier("feed.unavailable")
            }
            ForEach(store.items) { item in
                TradeFeedRow(item: item, onTradeDismiss: { Task { await reload() } }, demo: demo)
                    .padding(.vertical, 22)
                Divider().overlay(BSmartColor.line)
            }
            if store.loading && store.items.isEmpty {
                BSmartSkeletonRows(style: .feed, count: 3)
            } else if store.hasLoaded && store.items.isEmpty && !store.failed {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.stack").font(.largeTitle)
                    Text("No public trades yet".bSmartLocalized).font(.headline)
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 70)
                .accessibilityIdentifier("feed.empty")
            } else if store.nextOffset != nil {
                Button("Load more".bSmartLocalized) { Task { await loadMore() } }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityIdentifier("feed.more")
            }
        }
    }
}
