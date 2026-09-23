import SwiftUI

struct PopularOpinionsView: View {
    var demo: TradeFeedDemoData?
    var refresh: Int
    var isActive: Bool = true
    @State private var sort: DiscoveryRankingSort = .traders
    @State private var window: DiscoveryRankingWindow = .week

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DiscoveryRankingFilters(sort: $sort, window: $window)
            ForEach(DiscoveryRankingKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title.bSmartLocalized).font(.title3.weight(.bold))
                    DiscoveryRankingList(query: .init(kind: kind, sort: sort, window: window),
                                         demo: demo, preview: true, refresh: refresh, isActive: isActive)
                }
            }
        }.padding(.top, 12).padding(.bottom, 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.popular")
    }
}

struct DiscoveryRankingDetailView: View {
    let kind: DiscoveryRankingKind
    let demo: TradeFeedDemoData?
    @State private var sort: DiscoveryRankingSort
    @State private var window: DiscoveryRankingWindow
    @State private var refresh = 0

    init(kind: DiscoveryRankingKind, initialSort: DiscoveryRankingSort, initialWindow: DiscoveryRankingWindow,
         demo: TradeFeedDemoData?) {
        self.kind = kind; self.demo = demo
        _sort = State(initialValue: initialSort); _window = State(initialValue: initialWindow)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                DiscoveryRankingFilters(sort: $sort, window: $window)
                DiscoveryRankingList(query: .init(kind: kind, sort: sort, window: window),
                                     demo: demo, preview: false, refresh: refresh)
            }.padding(20)
        }
        .refreshable { refresh += 1 }
        .navigationTitle(kind.title.bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage().bSmartPage().accessibilityIdentifier("discovery.ranking.\(kind.rawValue)")
    }
}

private struct DiscoveryRankingFilters: View {
    @Binding var sort: DiscoveryRankingSort
    @Binding var window: DiscoveryRankingWindow
    @State private var selection: Selection?

    private enum Selection: String, Identifiable {
        case sort, window
        var id: String { rawValue }
        var title: String { self == .sort ? "Sort by" : "Time period" }
    }

    var body: some View {
        HStack(spacing: 20) {
            Button { selection = .sort } label: {
                Label(sort.title.bSmartLocalized, systemImage: "arrow.up.arrow.down").frame(minHeight: 44)
            }.accessibilityIdentifier("discovery.rankings.sort")
            Spacer(minLength: 0)
            Button { selection = .window } label: {
                HStack(spacing: 5) {
                    Text(window.title.bSmartLocalized)
                    Image(systemName: "chevron.down").font(.caption)
                }.frame(minHeight: 44)
            }.accessibilityIdentifier("discovery.rankings.window")
        }.font(.subheadline.weight(.medium)).foregroundStyle(BSmartColor.primaryText)
        .buttonStyle(.plain)
        .sheet(item: $selection) { panel in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(panel.title.bSmartLocalized).font(.title3.weight(.bold))
                        Spacer()
                        Button { selection = nil } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.accessibilityLabel("Close".bSmartLocalized)
                    }
                    if panel == .sort {
                        ForEach(DiscoveryRankingSort.allCases, id: \.self) { value in
                            option(value.title, selected: sort == value, id: "sort.\(value.rawValue)") {
                                sort = value
                            }
                        }
                    } else {
                        ForEach(DiscoveryRankingWindow.allCases, id: \.self) { value in
                            option(value.title, selected: window == value, id: "window.\(value.rawValue)") {
                                window = value
                            }
                        }
                    }
                }.padding(20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BSmartColor.primaryText)
            .presentationBackground(BSmartColor.surface)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func option(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            selection = nil
        } label: {
            HStack(spacing: 12) {
                Text(title.bSmartLocalized).font(.body.weight(selected ? .semibold : .regular))
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .foregroundStyle(selected ? BSmartColor.brand : BSmartColor.secondaryText)
            .padding(.horizontal, 16).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? BSmartColor.brand.opacity(0.1) : BSmartColor.elevated,
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("discovery.option.\(id)")
    }
}

private struct DiscoveryRankingList: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = DiscoveryRankingsStore()
    let query: DiscoveryRankingQuery
    let demo: TradeFeedDemoData?
    let preview: Bool
    let refresh: Int
    var isActive = true
    private var limit: Int { preview ? 3 : 20 }
    private var taskID: String {
        "\(query)-\(isActive)-\(router.selection)-\(account.identity?.id.uuidString ?? "none")-\(account.feedRevision)-\(refresh)-\(phase == .background)"
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(store.items.prefix(preview ? 3 : store.items.count).enumerated()), id: \.element.id) { index, item in
                DiscoveryRankingRow(item: item, rank: index + 1, kind: query.kind, sort: query.sort, preview: preview)
                    .padding(.vertical, preview ? 13 : 18)
                Divider().overlay(BSmartColor.line)
            }
            if store.loading && store.items.isEmpty {
                BSmartSkeletonRows(style: .ranking, count: preview ? 3 : 6)
            } else if store.failed {
                VStack(spacing: 8) {
                    Text("Trade statistics unavailable".bSmartLocalized).font(.subheadline)
                    Button("Retry".bSmartLocalized) { Task { await load(reset: !store.hasLoaded) } }.frame(minHeight: 44)
                }.foregroundStyle(BSmartColor.secondaryText).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if store.hasLoaded && store.items.isEmpty {
                Text("No verified trades in this period".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
            } else if !preview && store.nextOffset != nil && !store.loading {
                Button("Load more".bSmartLocalized) { Task { await load(reset: false) } }
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            if preview && store.hasLoaded && !store.items.isEmpty {
                BSmartDetailNavigationLink(id: "discovery.more.\(query.kind.rawValue)") {
                    DiscoveryRankingDetailView(kind: query.kind, initialSort: query.sort,
                                               initialWindow: query.window, demo: demo)
                } label: {
                    HStack(spacing: 5) {
                        Text("More".bSmartLocalized)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BSmartColor.brand)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discovery.more.\(query.kind.rawValue)")
            }
        }
        .task(id: taskID) { await load(reset: true) }
        .onDisappear { store.clear() }
    }

    private func load(reset: Bool) async {
        guard isActive, router.selection == .feed, phase != .background,
              demo != nil || account.identity != nil else { store.clear(); return }
        await store.load(query: query, limit: limit, reset: reset) { offset, anchor in
            if let demo { return try demo.rankings(query: query, offset: offset, limit: limit, asOf: anchor ?? Date()) }
            return try await NativeTradeFeedClient(account: account).rankings(query: query, offset: offset, limit: limit, asOf: anchor)
        }
    }
}

private struct DiscoveryRankingRow: View {
    @EnvironmentObject private var model: AppModel
    let item: DiscoveryRankingItem
    let rank: Int
    let kind: DiscoveryRankingKind
    let sort: DiscoveryRankingSort
    let preview: Bool

    var body: some View {
        BSmartDetailNavigationLink(id: "discovery.\(kind.rawValue).\(item.id)") {
            if kind == .opinions {
                SmartAccountEvidenceDetailView(update: item.opinion)
            } else {
                SmartAccountDetailView(account: model.smartAccountProfile(for: item.opinion))
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(String(format: "%02d", rank))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(rank == 1 ? BSmartColor.brand : BSmartColor.primaryText)
                    .frame(width: 38, height: 38, alignment: .topLeading)
                VStack(alignment: .leading, spacing: kind == .opinions ? 10 : 8) {
                    HStack(alignment: .top, spacing: 8) {
                        author
                        Spacer(minLength: 4)
                        metrics
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BSmartColor.tertiaryText)
                            .padding(.top, 16)
                    }
                    if kind == .opinions {
                        HStack(spacing: 7) {
                            BSmartAssetMark(ticker: item.opinion.ticker, size: 22)
                            Text(item.opinion.ticker).font(.headline.weight(.bold)).lineLimit(1)
                            Text(item.opinion.direction.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.opinion.direction.color)
                        }
                        Text(TodaySourceHeadline.account(item.opinion).text)
                            .font(.subheadline)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .lineSpacing(2)
                            .lineLimit(preview ? 2 : 3)
                            .multilineTextAlignment(.leading)
                    }
                    if !preview && kind == .opinions {
                        OpinionTradeSplitBar(longTraders: item.longTraders, shortTraders: item.shortTraders, compact: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .foregroundStyle(BSmartColor.primaryText)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityIdentifier(kind == .opinions ? "feed.popular.opinion.\(item.opinion.id)" : "feed.popular.investor.\(item.id)")
    }

    private var author: some View {
        HStack(spacing: 9) {
            BSmartAvatar(url: item.opinion.authorAvatarURL, name: item.opinion.authorName, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.opinion.authorName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    SmartPlatformMark(platform: item.opinion.platform, size: 11)
                    Text("Top \(max(1, Int(ceil(item.opinion.platformPercentile * 100))))%")
                        .foregroundStyle(BSmartColor.brand)
                }
                .font(.caption2.weight(.medium))
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(sort.title.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.secondaryText)
            Text(selectedValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BSmartColor.brand)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(secondaryTitle + " " + secondaryValue)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: 124, alignment: .trailing)
        .layoutPriority(1)
    }

    private var selectedValue: String {
        sort == .traders ? item.totalTraders.formatted() : item.volumeLabel
    }

    private var secondaryTitle: String {
        (sort == .traders ? DiscoveryRankingSort.volume : .traders).title.bSmartLocalized
    }

    private var secondaryValue: String {
        sort == .traders ? item.volumeLabel : item.totalTraders.formatted()
    }

}
