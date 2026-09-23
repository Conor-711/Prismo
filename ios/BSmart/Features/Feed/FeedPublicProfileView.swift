import SwiftUI

struct FeedPublicProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @Environment(\.scenePhase) private var phase
    let profileID: UUID
    var demo: TradeFeedDemoData? = nil
    @State private var profile: FeedPublicProfile?
    @State private var failed = false
    @State private var portfolio: FeedPublicPortfolio?
    @State private var portfolioFailed = false
    @State private var socialSnapshot: SocialSnapshot?
    @State private var socialFailed = false
    @State private var changingFollow = false
    @State private var messagePeer: FeedPublicProfile?
    @State private var requestID = UUID()
    @StateObject private var store = TradeFeedStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let profile {
                    header(profile)
                    if demo == nil, let portfolio {
                        if portfolio.status == .ready {
                            FeedPublicPortfolioView(portfolio: portfolio)
                            FeedPublicPositionsView(positions: portfolio.positions)
                        } else {
                            Label("No linked trading wallet".bSmartLocalized, systemImage: "wallet.pass")
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        }
                    } else if demo == nil && portfolioFailed {
                        HStack {
                            Text("On-chain account unavailable".bSmartLocalized)
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            Spacer()
                            Button("Retry".bSmartLocalized) { Task { await loadPortfolio() } }
                        }
                    } else if demo == nil {
                        BSmartSkeletonRows(style: .feed, count: 2)
                    }
                    Text("Trade history".bSmartLocalized).font(.headline)
                    TradeFeedContents(store: store, reload: refresh,
                                      loadMore: { await loadMore() }, demo: demo)
                } else if failed {
                    Text("Public profile unavailable".bSmartLocalized).font(.headline)
                    Button("Retry".bSmartLocalized) { Task { await refresh() } }
                } else { BSmartSkeletonRows(style: .profile, count: 1) }
            }.padding(20)
        }
        .refreshable { await refresh() }
        .navigationTitle(demo == nil ? "Profile".bSmartLocalized : "Profile".bSmartLocalized + " · Demo")
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage().bSmartPage()
        .accessibilityIdentifier("feed.profile.screen")
        .navigationDestination(item: $messagePeer) { peer in
            SocialChatView(room: .direct(peer), onActivity: {})
        }
        .task(id: "\(account.identity?.id.uuidString ?? "signed-out")-\(account.feedRevision)") { clear(); await refresh() }
        .onDisappear {
            if messagePeer == nil { clear() }
        }
        .onChange(of: phase) { _, phase in
            if phase == .active { Task { await refresh() } }
            else if phase == .background && messagePeer == nil { clear() }
        }
    }

    private func clear() {
        requestID = UUID(); profile = nil; portfolio = nil; socialSnapshot = nil; messagePeer = nil
        portfolioFailed = false; socialFailed = false; changingFollow = false; store.clear()
    }

    private func header(_ profile: FeedPublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 14) {
                BSmartAvatar(url: profile.avatarURL, name: profile.nickname, size: 72)
                Spacer(minLength: 8)
                if demo == nil {
                    Button { Task { await toggleFollow() } } label: {
                        Text((isFollowing ? "Following" : "Follow").bSmartLocalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isFollowing ? BSmartColor.primaryText : BSmartColor.onAccent)
                            .frame(minWidth: 92, minHeight: 42)
                            .background(isFollowing ? BSmartColor.elevated : BSmartColor.brand,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(socialSnapshot == nil || changingFollow)
                    .accessibilityIdentifier("feed.profile.follow")
                    Button { messagePeer = profile } label: {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 42, height: 42)
                            .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Message".bSmartLocalized)
                    .accessibilityIdentifier("feed.profile.message")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.nickname).font(.title2.weight(.semibold)).lineLimit(2)
                    .accessibilityIdentifier("feed.profile.nickname")
                if let handle = profile.handle {
                    Text("@" + handle).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        .lineLimit(1).accessibilityIdentifier("feed.profile.handle")
                }
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio).font(.subheadline).foregroundStyle(BSmartColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                }
            }
            if socialFailed && demo == nil {
                Button("Follow status unavailable. Retry".bSmartLocalized) { Task { await loadSocial() } }
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
            }
        }
    }

    private var isFollowing: Bool { socialSnapshot?.following.contains(where: { $0.id == profileID }) == true }

    private func refresh() async {
        let token = UUID()
        requestID = token
        failed = false
        do {
            let value: FeedPublicProfile
            if let demo { value = try demo.profile(id: profileID) }
            else { value = try await NativeTradeFeedClient(account: account).profile(profileID) }
            try Task.checkCancellation()
            guard requestID == token else { return }
            profile = value
            async let portfolioTask: Void = loadPortfolio()
            async let socialTask: Void = loadSocial()
            await loadTrades(reset: true)
            _ = await (portfolioTask, socialTask)
        } catch {
            guard requestID == token else { return }
            profile = nil; store.clear(); failed = !Task.isCancelled
        }
    }

    private func loadPortfolio() async {
        guard demo == nil, let id = account.identity?.id else { return }
        let token = requestID
        portfolioFailed = false
        do {
            let result = try await NativeTradeFeedClient(account: account).portfolio(profileID)
            guard !Task.isCancelled, account.identity?.id == id, requestID == token else { return }
            portfolio = result
        } catch {
            guard !Task.isCancelled, account.identity?.id == id, requestID == token else { return }
            portfolio = nil; portfolioFailed = true
        }
    }

    private func loadSocial() async {
        guard demo == nil, let id = account.identity?.id else { return }
        let token = requestID
        socialFailed = false
        do {
            let result = try await NativeSocialClient(account: account).snapshot(accountID: id)
            guard !Task.isCancelled, account.identity?.id == id, requestID == token else { return }
            socialSnapshot = result
        } catch {
            guard !Task.isCancelled, account.identity?.id == id, requestID == token else { return }
            socialFailed = true
        }
    }

    private func toggleFollow() async {
        guard let id = account.identity?.id, socialSnapshot != nil, !changingFollow else { return }
        let token = requestID
        let shouldFollow = !isFollowing
        changingFollow = true
        defer { changingFollow = false }
        do {
            let result = try await NativeSocialClient(account: account)
                .follow(profileID, enabled: shouldFollow, accountID: id)
            guard account.identity?.id == id, requestID == token else { return }
            socialSnapshot = result
            socialFailed = false
        } catch {
            if account.identity?.id == id && requestID == token { socialFailed = true }
        }
    }

    private func loadMore() async {
        await loadTrades(reset: false)
    }

    private func loadTrades(reset: Bool) async {
        await store.load(reset: reset) { offset in
            if let demo { return try demo.page(offset: offset, profileID: profileID) }
            return try await NativeTradeFeedClient(account: account).page(offset: offset, profileID: profileID)
        }
    }
}
