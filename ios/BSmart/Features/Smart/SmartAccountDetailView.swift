import SwiftUI

struct SmartAccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    let account: SmartAccountProfile
    @State private var collapsed = false
    @State private var showsAllViews = false
    @State private var showsChatShare = false

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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    SmartAccountPortraitHeader(account: account, width: geometry.size.width) { next in
                        if next != collapsed { collapsed = next }
                    }
                    VStack(alignment: .leading, spacing: 28) {
                        identity
                        SubjectTradeStatsSection(subject: .init(account: account))
                        SmartAccountRepresentativeWorks(
                            works: model.representativeAccountEvidence(for: account), updates: updates,
                            isLoading: model.isLoadingAccountEvidence(account))
                        separator
                        SmartAccountLatestViewsSection(
                            updates: insights.latestViews, limit: showsAllViews ? nil : 3,
                            onViewAll: { showsAllViews = true })
                        separator
                        SmartAccountCurrentViewsSection(insights: insights)
                        separator
                        SmartAccountAboutSection(account: account, updates: updates)
                    }
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 28)
                    .frame(maxWidth: 680)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: "account.profile.scroll")
        }
        .ignoresSafeArea(.container, edges: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { followDock }
        .navigationTitle(collapsed ? account.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(collapsed ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(collapsed ? nil : .dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BSmartIconButton(symbol: "paperplane.fill", accessibilityLabel: "Share",
                                 color: BSmartColor.brand) { showsChatShare = true }
                    .accessibilityIdentifier("smart.account.share")
            }
        }
        .sheet(isPresented: $showsChatShare) { ShareToChatSheet(content: sharedContent) }
        .bSmartDetailPage().bSmartPage()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.account.detail")
        .task(id: account.id) { await model.loadSmartAccountEvidence(for: account) }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 10) {
            SmartPlatformMark(platform: account.platform, size: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.handle).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let followers = account.followersCount {
                    Text("%@ followers".bSmartLocalized(followers.formatted()))
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
            }
            Spacer(minLength: 4)
            SmartAccountTopRankBadge(account: account)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.account.identity")
    }

    private var followDock: some View {
        Button { model.toggleSmartAccountFollow(account.id) } label: {
            Label((model.isFollowingSmartAccount(account.id) ? "Tracking" : "Track").bSmartLocalized,
                  systemImage: model.isFollowingSmartAccount(account.id) ? "checkmark" : "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(model.isFollowingSmartAccount(account.id) ? BSmartColor.primaryText : BSmartColor.onAccent)
                .background(model.isFollowingSmartAccount(account.id) ? BSmartColor.elevated : BSmartColor.brand,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("smart.account.follow")
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .background(BSmartColor.ink)
        .overlay(alignment: .top) { separator }
    }

    private var separator: some View { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }
}
