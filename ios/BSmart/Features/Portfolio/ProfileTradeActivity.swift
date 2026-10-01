import SwiftUI

struct ProfileTradeActivity: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.bSmartPageIsActive) private var isPageActive
    var refresh: Int = 0
    var isActive = true
    private var active: Bool { isActive && isPageActive }
    @StateObject private var store = TradeFeedStore()

    var body: some View {
        Group {
            if account.identity == nil {
                NavigationLink { TradingAccountView() } label: {
                    Text("Sign in to view real trades".bSmartLocalized)
                }.padding(24)
            } else {
                TradeFeedContents(store: store, reload: { await load(reset: true) },
                                  loadMore: { await load(reset: false) })
            }
        }
        .accessibilityIdentifier("profile.trade-activity")
        .onChange(of: account.identity?.id) { _, _ in store.clear() }
        .task(id: "\(account.identity?.id.uuidString ?? "guest")-\(account.feedRevision)-\(refresh)-\(active)") {
            guard active else { return }
            await load(reset: true)
        }
        .onChange(of: phase) { _, phase in
            if phase == .active && active { Task { await load(reset: true) } }
            else if phase == .background { store.clear() }
        }
        .onDisappear { store.clear() }
    }

    private func load(reset: Bool) async {
        guard active, account.identity != nil else { store.clear(); return }
        await store.load(reset: reset) { offset in
            try await NativeTradeFeedClient(account: account).page(offset: offset, mine: true)
        }
    }
}
