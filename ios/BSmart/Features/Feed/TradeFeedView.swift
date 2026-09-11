import SwiftUI

struct TradeFeedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TradeFeedStore()
    @State private var demo: TradeFeedDemoData?
    @State private var demoLoadFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                TradeFeedContents(store: store, reload: { await load(reset: true) },
                                  loadMore: { await load(reset: false) }, demo: demo)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
            }
            .refreshable { await load(reset: true) }
            .navigationTitle(demo == nil ? "Feed" : "Feed · Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(demo == nil ? "Demo" : "Live Feed".bSmartLocalized) {
                        do {
                            let next = demo == nil ? try TradeFeedDemoData.load() : nil
                            store.clear()
                            demo = next
                        } catch { demoLoadFailed = true }
                    }.accessibilityIdentifier("feed.demo.toggle")
                }
            }
            .alert("Demo unavailable".bSmartLocalized, isPresented: $demoLoadFailed) {
                Button("OK".bSmartLocalized, role: .cancel) { }
            }
            .background(BSmartColor.ink)
            .accessibilityIdentifier("feed.screen")
            .task(id: "\(router.selection == .feed)-\(demo != nil)") {
                if router.selection == .feed { await load(reset: true) } else { store.clear() }
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
        guard router.selection == .feed else { return }
        let snapshot = demo
        await store.load(reset: reset) { offset in
            if let snapshot { return try snapshot.page(offset: offset) }
            return try await model.fetchTradeFeed(offset: offset)
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
                    Text("Trade Feed unavailable".bSmartLocalized).font(.headline)
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
            if store.loading {
                ProgressView().frame(maxWidth: .infinity).padding(30)
            } else if store.hasLoaded && store.items.isEmpty && !store.failed {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble").font(.largeTitle)
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
