import SwiftUI

struct OpinionTradersSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var scenePhase
    let opinionID: UUID
    let ticker: String
    var referencePrice: Double? = nil
    var refresh = 0
    @State private var expansionOverride: Bool?
    @State private var page: OpinionTradersPage?
    @State private var traders: [OpinionTrader] = []
    @State private var loading = false
    @State private var failed = false
    @State private var demoAsOf = Date()
    @State private var showDemo = false
    @State private var requestID = UUID()

    private var expanded: Bool { expansionOverride ?? page?.hasTradeActivity ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if account.identity == nil && !usesTestFixture {
                NavigationLink {
                    TradingAccountView()
                } label: {
                    Label("Sign in to view real traders".bSmartLocalized, systemImage: "person.crop.circle")
                        .font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("opinion.traders.sign-in")
            } else {
                liveContent
            }
            if usesTestFixture {
                Button("Demo data".bSmartLocalized) {
                    demoAsOf = Date(); showDemo = true
                }.font(.caption).accessibilityIdentifier("opinion.traders.demo.open")
            }
        }
        .sheet(isPresented: $showDemo) {
            NavigationStack {
                ScrollView {
                    OpinionTradersDemoView(data: .init(ticker: ticker, referencePrice: referencePrice, now: demoAsOf)) {
                        demoAsOf = Date()
                    }.padding()
                }
                .navigationTitle("Demo data".bSmartLocalized)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done".bSmartLocalized) { showDemo = false }
                    }
                }
            }
        }
        .task(id: "\(opinionID)-\(refresh)-\(account.identity?.id.uuidString ?? "signed-out")-\(account.feedRevision)") {
            clear(); await load(reset: true)
        }
        .onChange(of: account.identity?.id) { _, _ in expansionOverride = nil }
        .onDisappear { clear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(reset: true) } }
            else if phase == .background { clear() }
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                expansionOverride = !expanded
                if expanded { Task { await load(reset: true) } }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Opinion-related trades".bSmartLocalized)
                            .font(.footnote.weight(.semibold))
                        Spacer(minLength: 8)
                        if loading { ProgressView() }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    ViewThatFits(in: .horizontal) {
                        tradeMetrics(stacked: false)
                        tradeMetrics(stacked: true)
                    }
                }
                .foregroundStyle(BSmartColor.primaryText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("opinion.traders.expand")
            if failed {
                HStack {
                    Text("Trade statistics unavailable".bSmartLocalized)
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                    Button { Task { await load(reset: true) } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }.accessibilityLabel("Retry".bSmartLocalized).accessibilityIdentifier("opinion.traders.retry")
                }
            }
            if expanded, let page {
                if let longs = page.longTraders, let shorts = page.shortTraders {
                    OpinionTradeSplitBar(longTraders: longs, shortTraders: shorts, compact: true)
                }
                if page.totalTraders == 0 {
                    Text("No verified trades yet".bSmartLocalized).font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                ForEach(traders) { trader in
                    HStack(spacing: 12) {
                        BSmartAvatar(url: trader.avatarURL, name: trader.nickname, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(trader.nickname).font(.subheadline.weight(.medium)).lineLimit(2)
                            if let handle = trader.handle {
                                Text("@" + handle).font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text((trader.side == .long ? "Long" : "Short").bSmartLocalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(trader.side == .long ? BSmartColor.bull : BSmartColor.bear)
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier("opinion.trader.\(trader.id.uuidString)")
                }
                if page.publicTraders < page.totalTraders {
                    Text("Some traders keep their profiles private.".bSmartLocalized)
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
                if page.nextOffset != nil {
                    Button("Load more".bSmartLocalized) { Task { await load(reset: false) } }
                        .disabled(loading).accessibilityIdentifier("opinion.traders.more")
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(BSmartColor.line) }
        .overlay(alignment: .bottom) { Divider().overlay(BSmartColor.line) }
    }

    private func tradeMetrics(stacked: Bool) -> some View {
        HStack(spacing: 12) {
            tradeMetric(label: "Traders", value: page.map { String($0.totalTraders) } ?? "—",
                        identifier: "opinion.traders.count", stacked: stacked)
            Rectangle().fill(BSmartColor.line).frame(width: 1, height: 16)
                .accessibilityHidden(true)
            tradeMetric(label: "Traded value", value: page?.totalNotionalLabel ?? "—",
                        identifier: "opinion.traders.volume", stacked: stacked)
        }
    }

    private func tradeMetric(label: String, value: String, identifier: String, stacked: Bool) -> some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 3) {
                    metricLabel(label)
                    metricValue(value, identifier: identifier)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    metricLabel(label).fixedSize()
                    Spacer(minLength: 0)
                    metricValue(value, identifier: identifier).fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricLabel(_ label: String) -> some View {
        Text(label.bSmartLocalized)
            .font(.caption).foregroundStyle(BSmartColor.secondaryText)
    }

    private func metricValue(_ value: String, identifier: String) -> some View {
        Text(value).font(.subheadline.weight(.semibold))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityIdentifier(identifier)
    }

    @MainActor private func load(reset: Bool) async {
        guard account.identity != nil || usesTestFixture else { return }
        guard !loading else { return }
        let token = UUID(), identity = account.identity?.id
        requestID = token
        loading = true
        defer { if requestID == token { loading = false } }
        do {
            let offset = reset ? 0 : page?.nextOffset ?? 0
            let result: OpinionTradersPage
            if usesTestFixture {
                result = try await model.fetchOpinionTraders(opinionID: opinionID, offset: offset)
            } else {
                result = try await NativeTradeFeedClient(account: account).traders(opinionID: opinionID, offset: offset)
            }
            try Task.checkCancellation()
            guard requestID == token, account.identity?.id == identity else { return }
            try result.validate(offset: offset)
            if reset { traders = result.traders } else {
                let newIDs = Set(result.traders.map(\.id))
                traders.removeAll { newIDs.contains($0.id) }
                traders.append(contentsOf: result.traders)
                traders.sort { $0.tradedAt > $1.tradedAt }
            }
            page = result
            failed = false
        } catch {
            guard requestID == token else { return }
            if reset { page = nil; traders = [] }
            if !Task.isCancelled { failed = true }
        }
    }

    private func clear() {
        requestID = UUID(); page = nil; traders = []; loading = false; failed = false
    }

    private var usesTestFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-opinion-traders-fixture")
        #else
        false
        #endif
    }
}
