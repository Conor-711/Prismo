import SwiftUI

struct OpinionTradersSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let opinionID: UUID
    let ticker: String
    var referencePrice: Double? = nil
    var refresh = 0
    @State private var expanded = false
    @State private var page: OpinionTradersPage?
    @State private var traders: [OpinionTrader] = []
    @State private var loading = false
    @State private var failed = false
    @State private var demoAsOf = Date()

    var body: some View {
        Group {
            if page == nil {
                OpinionTradersDemoView(data: .init(ticker: ticker, referencePrice: referencePrice, now: demoAsOf)) {
                    Task { await load(reset: true) }
                }
            } else {
                liveContent
            }
        }
        .task(id: refresh) { await load(reset: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(reset: true) } }
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                expanded.toggle()
                if expanded { Task { await load(reset: true) } }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill").foregroundStyle(BSmartColor.brand)
                    if let page {
                        Text("%d people traded through this opinion".bSmartLocalized(page.totalTraders))
                            .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("opinion.traders.count")
                    } else {
                        Text("Real traders".bSmartLocalized).font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                    if loading { ProgressView() }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }.foregroundStyle(BSmartColor.primaryText).frame(minHeight: 44).contentShape(Rectangle())
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
                if page.totalTraders == 0 {
                    Text("No verified trades yet".bSmartLocalized).font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                ForEach(traders) { trader in
                    HStack(spacing: 12) {
                        BSmartAvatar(url: trader.avatarURL, name: trader.nickname, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trader.nickname).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(trader.tradedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
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
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(BSmartColor.line) }
    }

    @MainActor private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let offset = reset ? 0 : page?.nextOffset ?? 0
            let result = try await model.fetchOpinionTraders(opinionID: opinionID, offset: offset)
            try Task.checkCancellation()
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
            if !Task.isCancelled { failed = true }
        }
    }
}
