import SwiftUI

struct SubjectTradeStatsSection: View {
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var scenePhase
    let subject: TradeSubject
    @StateObject private var store = SubjectTradeStatsStore()
    @State private var showsDefinition = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Trades inspired".bSmartLocalized).font(.subheadline.weight(.semibold))
                Button { showsDefinition = true } label: {
                    Image(systemName: "info.circle").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityLabel("Counting method".bSmartLocalized)
                Spacer()
                if store.loading { BSmartSkeletonBar(width: 44, height: 23) }
                else if let stats = store.stats {
                    Text(stats.totalTrades.formatted()).font(.title2.weight(.bold)).monospacedDigit()
                        .accessibilityIdentifier("subject.trades.count")
                }
            }
            if account.identity == nil {
                NavigationLink(destination: TradingAccountView()) {
                    Label("Sign in to view real traders".bSmartLocalized, systemImage: "person.crop.circle")
                        .font(.subheadline).frame(minHeight: 44)
                }
            } else if store.failed {
                HStack {
                    Text("Trade statistics unavailable".bSmartLocalized).font(.subheadline)
                    Spacer()
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }.accessibilityLabel("Retry".bSmartLocalized)
                }.foregroundStyle(BSmartColor.secondaryText)
            } else if let stats = store.stats {
                OpinionTradeSplitBar(longTraders: stats.longTrades, shortTraders: stats.shortTrades)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject.trades")
        .alert("Counting method".bSmartLocalized, isPresented: $showsDefinition) {
            Button("Done".bSmartLocalized, role: .cancel) {}
        } message: {
            Text((subject.kind == .account
                  ? "One user trading ten different opinions counts as ten. Repeated trades through one opinion count once. Only verified executions are included."
                  : "One user trading ten different activity sources counts as ten. Repeated trades through one source count once. The tracked account's own trades are not included.").bSmartLocalized)
        }
        .task(id: "\(subject.kind)-\(subject.id)-\(subject.platform)-\(account.identity?.id.uuidString ?? "")-\(account.feedRevision)") {
            store.clear(); await load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
            else if phase == .background { store.clear() }
        }
        .onDisappear { store.clear() }
    }

    @MainActor private func load() async {
        guard account.identity != nil else { store.clear(); return }
        await store.load(subject: subject) { try await NativeTradeFeedClient(account: account).subjectStats(subject) }
    }
}
