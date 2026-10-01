import SwiftUI

struct SmartAccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var viewer: AccountAccessStore
    @Environment(\.scenePhase) private var scenePhase
    let account: SmartAccountProfile
    var nativeProfile: FeedPublicProfile? = nil
    var nativeDemo: TradeFeedDemoData? = nil
    @StateObject private var nativeStore = NativeTraderDetailStore()
    @State private var collapsed = false
    @State private var showsAllViews = false
    @State private var showsChatShare = false
    @State private var messagePeer: FeedPublicProfile?

    private var publicProfile: FeedPublicProfile? { nativeProfile ?? account.nativePublicProfile }
    private var nativeClient: NativeTraderDetailClient { .init(account: viewer) }

    private var sharedContent: SocialSharedContent {
        let rank = account.resolvedRank > 0 ? "#\(account.resolvedRank) · " : ""
        return .init(kind: .investor, id: account.id,
                     title: SocialSharedContent.clipped(account.name, utf16Limit: 100),
                     detail: SocialSharedContent.clipped("\(rank)\(account.platform) · \(account.handle)", utf16Limit: 120),
                     summary: SocialSharedContent.clipped(account.description ?? account.specialty, utf16Limit: 300),
                     ticker: (account.resolvedTopTickers.first ?? model.accountEvidence(for: account).first?.ticker)?.uppercased(),
                     publishedAt: nil,
                     avatarURL: SocialSharedContent.shareableAvatarURL(account.avatarURL))
    }

    private var updates: [SmartAccountUpdate] { model.accountEvidence(for: account) }
    private var insights: SmartAccountProfileInsights {
        SmartAccountProfileInsights(account: account, evidenceUpdates: updates,
                                    recentUpdates: model.accountUpdates(for: account))
    }

    var body: some View {
        InvestorDetailScaffold(title: account.name, collapsed: $collapsed) { width in
            SmartAccountPortraitHeader(account: account, width: width) { next in
                if next != collapsed { collapsed = next }
            }
        } sections: {
            VStack(alignment: .leading, spacing: 28) {
                identity
                if let performance = account.nativePerformance {
                    nativeTrading(performance)
                }
                if let profileID = account.nativeProfileID {
                    NativeTraderDetailSections(store: nativeStore, profileID: profileID,
                                               client: nativeClient, demo: nativeDemo,
                                               refresh: refreshNative)
                }
                SubjectTradeStatsSection(subject: .init(account: account))
                SmartAccountRepresentativeWorks(
                    works: model.representativeAccountEvidence(for: account), updates: updates,
                    isLoading: model.isLoadingAccountEvidence(account))
                separator
                if account.nativeProfileID == nil {
                    SmartAccountLatestViewsSection(
                        updates: insights.latestViews, limit: showsAllViews ? nil : 3,
                        onViewAll: { showsAllViews = true })
                    separator
                    SmartAccountCurrentViewsSection(insights: insights)
                    separator
                }
                SmartAccountAboutSection(account: account, updates: updates)
            }
        } dock: {
            followDock
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Group {
                BSmartIconButton(symbol: "paperplane.fill", accessibilityLabel: "Share",
                                 color: BSmartColor.brand) { showsChatShare = true }
                    .accessibilityIdentifier("smart.account.share")
            }.buttonStyle(.bSmartToolbar) }
            .bSmartHideSystemBackground()
        }
        .sheet(isPresented: $showsChatShare) { ShareToChatSheet(content: sharedContent) }
        .navigationDestination(item: $messagePeer) { peer in
            SocialChatView(room: .direct(peer), onActivity: {})
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.account.detail")
        .task(id: account.id) { await model.loadSmartAccountEvidence(for: account) }
        .task(id: "\(account.id)-\(viewer.identity?.id.uuidString ?? "signed-out")-\(viewer.feedRevision)") {
            nativeStore.clear()
            await refreshNative()
        }
        .refreshable {
            if account.nativeProfileID != nil { await refreshNative() }
            else { await model.loadSmartAccountEvidence(for: account) }
        }
        .onChange(of: viewer.identity?.id) { _, _ in nativeStore.clear(); messagePeer = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNative() } }
            else if phase == .background { nativeStore.clear() }
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 10) {
            SmartPlatformMark(platform: account.platform, size: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.handle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .accessibilityIdentifier(account.nativeProfileID == nil ? "smart.account.handle" : "feed.profile.handle")
                if let followers = account.followersCount {
                    Text("%@ followers".bSmartLocalized(followers.formatted()))
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            Spacer(minLength: 4)
            SmartAccountTopRankBadge(account: account)
            if let publicProfile, nativeDemo == nil {
                BSmartIconButton(symbol: "bubble.left", accessibilityLabel: "Message") {
                    messagePeer = publicProfile
                }
                .accessibilityIdentifier("feed.profile.message")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.account.identity")
    }

    private var followDock: some View {
        Button {
            if let profileID = account.nativeProfileID, nativeDemo == nil {
                Task {
                    guard let viewerID = viewer.identity?.id else { return }
                    let following = await nativeStore.toggleFollow(profileID, viewerID: viewerID, client: nativeClient)
                    if let following, following != model.isFollowingSmartAccount(account.id) {
                        model.toggleSmartAccountFollow(account.id)
                    }
                }
            } else { model.toggleSmartAccountFollow(account.id) }
        } label: {
            Label((isFollowing ? "Tracking" : "Track").bSmartLocalized,
                  systemImage: isFollowing ? "checkmark" : "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(isFollowing ? BSmartColor.primaryText : BSmartColor.onAccent)
                .background(isFollowing ? BSmartColor.elevated : BSmartColor.brand,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.bSmartPlain)
        .disabled(account.nativeProfileID != nil && nativeDemo == nil
                  && (nativeStore.socialSnapshot == nil || nativeStore.changingFollow))
        .accessibilityIdentifier("smart.account.follow")
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .background(BSmartColor.ink)
        .overlay(alignment: .top) { separator }
    }

    private func nativeTrading(_ performance: NativeInvestorPerformance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verified trading".bSmartLocalized).font(.headline)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Win / loss".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    Text(performance.closedTrades > 0 ? "\(performance.wins) / \(performance.losses)" : "—")
                        .font(.title3.weight(.bold)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Realized return".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    Text(performance.realizedReturn.map {
                        $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
                    } ?? "—")
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .foregroundStyle((performance.realizedReturn ?? 0) >= 0 ? BSmartColor.bull : BSmartColor.bear)
                }
            }
            HStack(spacing: 8) {
                Text("Net P&L".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text(performance.netPnlUSD.formatted(.currency(code: "USD")
                    .precision(.fractionLength(2)).sign(strategy: .always())))
                    .foregroundStyle(performance.netPnlUSD >= 0 ? BSmartColor.bull : BSmartColor.bear)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            Text("Verified closes since recording began; return is net P&L divided by closed notional.".bSmartLocalized)
                .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("smart.account.native-performance")
    }

    private var separator: some View { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }

    private var isFollowing: Bool {
        if let profileID = account.nativeProfileID, nativeDemo == nil { return nativeStore.isFollowing(profileID) }
        return model.isFollowingSmartAccount(account.id)
    }

    private func refreshNative() async {
        guard let profileID = account.nativeProfileID else { return }
        await nativeStore.refresh(profileID: profileID, viewerID: viewer.identity?.id,
                                  client: nativeClient, demo: nativeDemo)
    }
}
