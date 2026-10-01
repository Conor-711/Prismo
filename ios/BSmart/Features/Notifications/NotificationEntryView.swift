import SwiftUI

struct NotificationEntryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var inbox = ActivityNotificationStore()
    @State private var liveTickers = Set<String>()
    @State private var liveScope: String?
    @State private var holdingsError: String?
    @State private var loadingHoldings = false
    @State private var holdingsRequest = UUID()
    @State private var followers: [SocialPerson] = []
    @State private var followersScope: String?
    @State private var loadingFollowers = false
    @State private var followersError: String?
    @State private var followersRequest = UUID()
    @State private var followersRevision = 0
    @State private var builtKey: BuildKey?
    @State private var showingPushInbox = false
    private var scope: String { account.identity?.id.uuidString ?? (account.isTestSession ? "test" : "guest") }
    private var isActive: Bool { scenePhase == .active && router.selection == .today }

    private struct BuildKey: Hashable {
        let scope: String
        let feedRevision: Int
        let directoryRevision: Int
        let evidenceRevision: Int
        let followedAccounts: Set<String>
        let followedMoney: Set<String>
        let heldTickers: Set<String>
        let followersRevision: Int
        let timeWindow: Int
    }
    private struct BuildTaskKey: Hashable {
        let active: Bool
        let content: BuildKey
    }
    private var buildKey: BuildKey {
        BuildKey(scope: scope, feedRevision: model.todayFeedRevision,
            directoryRevision: model.directoryRevision, evidenceRevision: model.accountEvidenceRevision,
            followedAccounts: model.followedSmartAccountIDs,
            followedMoney: BSmartProductVisibility.onchainSmartMoney ? model.followedSmartMoneyIDs : [],
            heldTickers: Set(model.heldPositions.map { ActivityNotification.symbol($0.ticker) })
                .union(liveScope == scope ? liveTickers : []),
            followersRevision: followersRevision, timeWindow: Int(Date().timeIntervalSince1970 / 30))
    }

    private var entryLink: some View {
        BSmartDetailNavigationLink(id: "today-notifications") {
            NotificationInboxView(inbox: inbox, loading: model.isRefreshingLiveIntelligence || loadingHoldings,
                                  error: model.errorMessage ?? holdingsError, refresh: refresh,
                                  followersLoading: loadingFollowers, followersError: followersError)
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(BSmartColor.primaryText)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if inbox.unreadCount > 0 {
                        Circle().fill(BSmartColor.bear).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(BSmartColor.ink, lineWidth: 2))
                            .offset(x: -5, y: 5)
                    }
                }
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityLabel("Notifications".bSmartLocalized)
        .accessibilityValue("%d unread".bSmartLocalized(inbox.unreadCount))
        .accessibilityIdentifier("today.notifications")
    }

    var body: some View {
        entryLink
        .navigationDestination(isPresented: $showingPushInbox) {
            NotificationInboxView(inbox: inbox, loading: model.isRefreshingLiveIntelligence || loadingHoldings,
                                  error: model.errorMessage ?? holdingsError, refresh: refresh,
                                  followersLoading: loadingFollowers, followersError: followersError)
        }
        .task(id: "\(scope)-\(isActive)") {
            inbox.activate(scope: scope)
            if liveScope != scope {
                builtKey = nil
                liveScope = scope
                liveTickers = []
                holdingsError = nil
                loadingHoldings = false
            }
            guard isActive else { holdingsRequest = UUID(); loadingHoldings = false; return }
            await refreshHoldings()
            openPendingInbox()
        }
        .onChange(of: router.pendingNotificationInbox) { openPendingInbox() }
        .task(id: BuildTaskKey(active: isActive, content: buildKey)) {
            guard isActive else { return }
            await rebuild(key: buildKey)
        }
        .task(id: "followers-\(scope)-\(isActive)") {
            followersRequest = UUID()
            loadingFollowers = false
            if followersScope != scope {
                followersScope = scope
                followers = []
                followersRevision &+= 1
                followersError = nil
            }
            guard isActive else { return }
            while !Task.isCancelled {
                await refreshFollowers()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    private func openPendingInbox() {
        guard router.pendingNotificationInbox else { return }
        router.consumeNotificationInbox()
        showingPushInbox = true
    }

    private func rebuild(key: BuildKey) async {
        guard builtKey != key else { return }
        inbox.activate(scope: key.scope)
        let updates = model.smartAccountUpdates
        let evidence = Array(model.smartAccountEvidenceByAuthor.values)
        let movements = BSmartProductVisibility.onchainSmartMoney ? model.smartMoneyMovements : []
        let profiles = model.smartAccounts
        let followers = followersScope == key.scope ? followers : []
        let worker = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return [ActivityNotification]() }
            return ActivityNotification.build(updates: updates + evidence.flatMap { $0 },
                movements: movements, followedAccounts: key.followedAccounts,
                followedMoney: key.followedMoney, heldTickers: key.heldTickers,
                profiles: profiles, followers: followers)
        }
        let items = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, isActive, buildKey == key else { return }
        builtKey = key
        inbox.replace(items)
    }

    private func refresh() async {
        async let content: Void = model.refreshLiveIntelligence()
        async let positions: Void = refreshHoldings()
        async let follows: Void = refreshFollowers()
        _ = await (content, positions, follows)
    }

    private func refreshFollowers() async {
        let request = UUID(); followersRequest = request
        let currentScope = scope
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-follow-notification-fixture") {
            followersScope = currentScope
            if followers.isEmpty {
                followers = [.init(profile: .init(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                    nickname: "Alice", avatarURL: nil, handle: "alice"), at: Date().addingTimeInterval(-60))]
                followersRevision &+= 1
            }
            return
        }
#endif
        guard let id = account.identity?.id else { return }
        loadingFollowers = true
        defer { if request == followersRequest { loadingFollowers = false } }
        do {
            let snapshot = try await NativeSocialClient(account: account).snapshot(accountID: id)
            guard !Task.isCancelled, request == followersRequest, scope == currentScope else { return }
            followersScope = currentScope
            if followers != snapshot.followers {
                followers = snapshot.followers
                followersRevision &+= 1
            }
            followersError = nil
        } catch {
            guard !Task.isCancelled, request == followersRequest, scope == currentScope else { return }
            followersError = "Follow notifications could not be refreshed.".bSmartLocalized
        }
    }

    private func refreshHoldings() async {
        let request = UUID(); holdingsRequest = request
        let currentScope = scope
        holdingsError = nil
        guard let id = account.identity?.id else { return }
        loadingHoldings = true
        defer { if holdingsRequest == request { loadingHoldings = false } }
        do {
            let registration = try await account.walletRegistration()
            guard !Task.isCancelled, request == holdingsRequest, scope == currentScope,
                  registration.accountId == id else { return }
            if let address = registration.address {
                // Holdings reads use the registered public address, never a key or signing lease.
                let positions = TradingPositionsStore(service: account)
                await positions.refresh(wallet: .init(accountID: id, address: address, recoveryVerified: false))
                guard !Task.isCancelled, request == holdingsRequest, scope == currentScope else { return }
                let latest = Set(positions.rows.map { ActivityNotification.symbol($0.symbol) })
                liveTickers = positions.errorMessage == nil ? latest : liveTickers.union(latest)
                holdingsError = positions.errorMessage
            } else {
                liveTickers = []
            }
        } catch {
            guard !Task.isCancelled, request == holdingsRequest, scope == currentScope else { return }
            holdingsError = "Holdings notifications could not be fully refreshed.".bSmartLocalized
        }
    }
}
