import SwiftUI

struct FeedPublicProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    let profileID: UUID
    var demo: TradeFeedDemoData? = nil
    @State private var profile: FeedPublicProfile?
    @State private var failed = false
    @State private var requestID = UUID()
    @StateObject private var store = TradeFeedStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let profile {
                    HStack(spacing: 16) {
                        BSmartAvatar(url: profile.avatarURL, name: profile.nickname, size: 68)
                        Text(profile.nickname).font(.title2.weight(.semibold))
                            .accessibilityIdentifier("feed.profile.nickname")
                    }
                    Text("Public trades".bSmartLocalized).font(.headline)
                    TradeFeedContents(store: store, reload: refresh,
                                      loadMore: { await loadMore() }, demo: demo)
                } else if failed {
                    Text("Public profile unavailable".bSmartLocalized).font(.headline)
                    Button("Retry".bSmartLocalized) { Task { await refresh() } }
                } else { ProgressView().frame(maxWidth: .infinity).padding(50) }
            }.padding(20)
        }
        .refreshable { await refresh() }
        .navigationTitle(demo == nil ? "Profile".bSmartLocalized : "Profile".bSmartLocalized + " · Demo")
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage().bSmartPage()
        .accessibilityIdentifier("feed.profile.screen")
        .task { await refresh() }
        .onDisappear { clear() }
        .onChange(of: phase) { _, phase in
            if phase == .active { Task { await refresh() } }
            else if phase == .background { clear() }
        }
    }

    private func clear() { requestID = UUID(); profile = nil; store.clear() }

    private func refresh() async {
        let token = UUID()
        requestID = token
        failed = false
        do {
            let value: FeedPublicProfile
            if let demo { value = try demo.profile(id: profileID) }
            else { value = try await model.fetchPublicTrader(profileID: profileID) }
            try Task.checkCancellation()
            guard requestID == token else { return }
            profile = value
            await loadTrades(reset: true)
        } catch {
            guard requestID == token else { return }
            profile = nil; store.clear(); failed = !Task.isCancelled
        }
    }

    private func loadMore() async {
        await loadTrades(reset: false)
    }

    private func loadTrades(reset: Bool) async {
        await store.load(reset: reset) { offset in
            if let demo { return try demo.page(offset: offset, profileID: profileID) }
            return try await model.fetchTradeFeed(offset: offset, profileID: profileID)
        }
    }
}
