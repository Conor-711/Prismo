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
    @State private var showingPushInbox = false
    private var scope: String { account.identity?.id.uuidString ?? (account.isTestSession ? "test" : "guest") }

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
        .buttonStyle(.plain)
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
        .task(id: "\(scope)-\(scenePhase == .active)") {
            inbox.activate(scope: scope)
            if liveScope != scope {
                liveScope = scope
                liveTickers = []
                holdingsError = nil
                loadingHoldings = false
            }
            guard scenePhase == .active else { holdingsRequest = UUID(); return }
            rebuild()
            await refreshHoldings()
            openPendingInbox()
        }
        .onChange(of: router.pendingNotificationInbox) { openPendingInbox() }
        .onChange(of: model.smartAccountUpdates) { rebuild() }
        .onChange(of: model.smartMoneyMovements) { rebuild() }
        .onChange(of: model.smartAccountEvidenceByAuthor) { rebuild() }
        .onChange(of: model.smartAccounts) { rebuild() }
        .onChange(of: model.followedSmartAccountIDs) { rebuild() }
        .onChange(of: model.followedSmartMoneyIDs) { rebuild() }
        .onChange(of: model.positions) { rebuild() }
        .task(id: "followers-\(scope)-\(scenePhase == .active)-\(router.selection == .today)") {
            followersRequest = UUID()
            loadingFollowers = false
            if followersScope != scope {
                followersScope = scope
                followers = []
                followersError = nil
                rebuild()
            }
            guard scenePhase == .active, router.selection == .today else { return }
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

    private func rebuild() {
        inbox.activate(scope: scope)
        let updates = model.smartAccountUpdates + model.smartAccountEvidenceByAuthor.values.flatMap { $0 }
        let held = Set(model.heldPositions.map { ActivityNotification.symbol($0.ticker) })
            .union(liveScope == scope ? liveTickers : [])
        inbox.replace(ActivityNotification.build(updates: updates, movements: model.smartMoneyMovements,
            followedAccounts: model.followedSmartAccountIDs, followedMoney: model.followedSmartMoneyIDs,
            heldTickers: held, profiles: model.smartAccounts,
            followers: followersScope == scope ? followers : []))
    }

    private func refresh() async {
        async let content: Void = model.refreshLiveIntelligence()
        async let positions: Void = refreshHoldings()
        async let follows: Void = refreshFollowers()
        _ = await (content, positions, follows)
        rebuild()
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
            }
            rebuild()
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
            followers = snapshot.followers
            followersError = nil
            rebuild()
        } catch {
            guard !Task.isCancelled, request == followersRequest, scope == currentScope else { return }
            followersError = "Follow notifications could not be refreshed.".bSmartLocalized
        }
    }

    private func refreshHoldings() async {
        let request = UUID(); holdingsRequest = request
        let currentScope = scope
        holdingsError = nil
        guard let id = account.identity?.id else { rebuild(); return }
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
        rebuild()
    }
}
