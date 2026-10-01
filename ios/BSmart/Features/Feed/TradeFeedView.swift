import SwiftUI

struct TradeFeedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.bSmartFloatingNavigationFrame) private var floatingNavigationFrame
    @Environment(\.bSmartPageIsActive) private var isPageActive
    @StateObject private var cloudProfile = AccountProfileStore()
    @StateObject private var localProfile = LocalUserProfileStore()
    @State private var rankingRefresh = 0
    @State private var cachedSnapshot: InvestorAbilityLeaderboard?
    @State private var builtKey: RankingKey?

    private struct RankingKey: Hashable {
        let revision: Int
        let refresh: Int
        let accountID: UUID?
        let name: String
        let avatarURL: URL?
    }

    private struct RankingTaskKey: Hashable {
        let ranking: RankingKey
        let active: Bool
    }

    private var rankingKey: RankingKey {
        .init(revision: model.directoryRevision, refresh: rankingRefresh,
              accountID: account.identity?.id, name: ownName, avatarURL: profile?.avatarURL)
    }

    private var profile: AccountProfile? {
        cloudProfile.accountID == account.identity?.id ? cloudProfile.profile : nil
    }

    private var ownActorID: String {
        "bsmart:\(account.identity?.id.uuidString.lowercased() ?? "preview-guest")"
    }

    private var ownName: String {
        if account.identity == nil { return localProfile.profile.displayName }
        return profile?.username ?? "bSmart Investor".bSmartLocalized
    }

    nonisolated private static func makeSnapshot(accounts: [SmartAccountProfile], profiles: [TodaySubjectProfile],
                                                 key: RankingKey) -> InvestorAbilityLeaderboard {
        var subjects = Dictionary(uniqueKeysWithValues: TodaySubjectFeedSnapshot.bundled.subjects.map { ($0.id, $0) })
        for subject in profiles { subjects[subject.id] = subject }
        let source = InvestorAbilityLeaderboard.bundledResearch.map {
            $0.replacingSubjectResearch(with: Array(subjects.values))
        } ?? .mock(accounts: accounts, subjects: Array(subjects.values))
        return source.includingMockUser(
            id: key.accountID?.uuidString.lowercased() ?? "preview-guest",
            name: key.name, avatarURL: key.avatarURL
        ).balancedMock()
    }

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
        let snapshot = cachedSnapshot
        return NavigationStack {
            DiscoverContent(content: {
                if let snapshot {
                    AbilityLeaderboardView(refresh: rankingRefresh, snapshotOverride: snapshot)
                } else {
                    BSmartSkeletonRows(style: .simple, count: 6)
                }
            }, refresh: {
                rankingRefresh += 1
            })
            .overlay(alignment: .bottom) {
                GeometryReader { viewport in
                    VStack {
                        Spacer().allowsHitTesting(false)
                        if let item = snapshot?.items.first(where: { $0.actorId == ownActorID }) {
                            ownPosition(item)
                                .padding(.horizontal, 12)
                                .padding(.bottom, BSmartFloatingNavigationLayout.bottomSpacing(
                                    viewport: viewport.frame(in: .global), navigationFrame: floatingNavigationFrame
                                ))
                        }
                    }
                }
            }
            .navigationTitle("Leaderboard".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .background(BSmartColor.ink)
            .accessibilityIdentifier("feed.screen")
        }
        .bSmartPage()
        .onAppear { localProfile.load(accountID: account.identity?.id) }
        .onChange(of: account.identity?.id) { _, id in localProfile.load(accountID: id) }
        .task(id: "\(account.identity?.id.uuidString ?? "guest"):\(account.feedRevision):\(isPageActive)") {
            guard isPageActive else { return }
            await cloudProfile.load(account: account)
        }
        .task(id: RankingTaskKey(ranking: rankingKey, active: isPageActive)) {
            guard isPageActive, builtKey != rankingKey else { return }
            let key = rankingKey
            let accounts = model.smartAccounts
            let subjects = model.subjectActivitySnapshot.subjects
            let worker = Task.detached(priority: .userInitiated) {
                Self.makeSnapshot(accounts: accounts, profiles: subjects, key: key)
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, isPageActive, key == rankingKey else { return }
            cachedSnapshot = result
            builtKey = key
        }
    }

    private func ownPosition(_ item: InvestorAbilityItem) -> some View {
        Button { router.selection = .portfolio } label: {
            HStack(spacing: 12) {
                Text("#\(item.rank ?? 1)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(BSmartColor.brand)
                    .frame(width: 58, alignment: .leading)
                if account.identity == nil {
                    UserProfileAvatar(data: localProfile.profile.avatarData, size: 42)
                } else {
                    BSmartAvatar(url: profile?.avatarURL, name: ownName, size: 42)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(ownName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                    Text("Your position".bSmartLocalized)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.brand)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(item.scoreLabel)
                        .font(.headline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(BSmartColor.brand)
                    Text("Mock points".bSmartLocalized)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            .padding(.horizontal, BSmartSpacing.large)
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BSmartColor.strongLine, lineWidth: 0.75))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityIdentifier("leaderboard.current-user")
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
