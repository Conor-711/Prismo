import Foundation

@MainActor
protocol NativeTraderDetailProviding {
    func portfolio(_ profileID: UUID) async throws -> FeedPublicPortfolio
    func social(accountID: UUID) async throws -> SocialSnapshot
    func follow(_ profileID: UUID, enabled: Bool, accountID: UUID) async throws -> SocialSnapshot
    func trades(profileID: UUID, offset: Int) async throws -> TradeFeedPage
}

@MainActor
struct NativeTraderDetailClient: NativeTraderDetailProviding {
    let account: AccountAccessStore

    func portfolio(_ profileID: UUID) async throws -> FeedPublicPortfolio {
        try await NativeTradeFeedClient(account: account).portfolio(profileID)
    }
    func social(accountID: UUID) async throws -> SocialSnapshot {
        try await NativeSocialClient(account: account).snapshot(accountID: accountID)
    }
    func follow(_ profileID: UUID, enabled: Bool, accountID: UUID) async throws -> SocialSnapshot {
        try await NativeSocialClient(account: account).follow(profileID, enabled: enabled, accountID: accountID)
    }
    func trades(profileID: UUID, offset: Int) async throws -> TradeFeedPage {
        try await NativeTradeFeedClient(account: account).page(offset: offset, profileID: profileID)
    }
}

@MainActor
final class NativeTraderDetailStore: ObservableObject {
    @Published private(set) var portfolio: FeedPublicPortfolio?
    @Published private(set) var portfolioFailed = false
    @Published private(set) var socialSnapshot: SocialSnapshot?
    @Published private(set) var socialFailed = false
    @Published private(set) var changingFollow = false
    let trades = TradeFeedStore()
    private var requestID = UUID()
    private var scope: Scope?
    private struct Scope: Equatable { let profileID: UUID; let viewerID: UUID?; let isDemo: Bool }

    func clear() {
        requestID = UUID()
        scope = nil
        portfolio = nil
        portfolioFailed = false
        socialSnapshot = nil
        socialFailed = false
        changingFollow = false
        trades.clear()
    }

    func isFollowing(_ profileID: UUID) -> Bool {
        socialSnapshot?.following.contains { $0.id == profileID } == true
    }

    func refresh(profileID: UUID, viewerID: UUID?, client: any NativeTraderDetailProviding,
                 demo: TradeFeedDemoData? = nil) async {
        let nextScope = Scope(profileID: profileID, viewerID: viewerID, isDemo: demo != nil)
        if scope != nextScope { clear(); scope = nextScope }
        let token = UUID()
        requestID = token
        if let demo {
            await trades.load(reset: true) { try demo.page(offset: $0, profileID: profileID) }
            return
        }
        guard let viewerID else { clear(); return }
        async let portfolioTask: Void = loadPortfolio(profileID, client: client, token: token)
        async let socialTask: Void = loadSocial(viewerID, client: client, token: token)
        await loadTrades(profileID, client: client, reset: true)
        _ = await (portfolioTask, socialTask)
    }

    func retryPortfolio(_ profileID: UUID, client: any NativeTraderDetailProviding) async {
        guard scope?.profileID == profileID, scope?.viewerID != nil, scope?.isDemo == false else { return }
        await loadPortfolio(profileID, client: client, token: requestID)
    }

    func retrySocial(_ viewerID: UUID, client: any NativeTraderDetailProviding) async {
        guard scope?.viewerID == viewerID, scope?.isDemo == false else { return }
        await loadSocial(viewerID, client: client, token: requestID)
    }

    func toggleFollow(_ profileID: UUID, viewerID: UUID,
                      client: any NativeTraderDetailProviding) async -> Bool? {
        guard scope?.profileID == profileID, scope?.viewerID == viewerID, scope?.isDemo == false,
              socialSnapshot != nil, !changingFollow else { return nil }
        let token = requestID
        let following = !isFollowing(profileID)
        changingFollow = true
        defer { if requestID == token { changingFollow = false } }
        do {
            let result = try await client.follow(profileID, enabled: following, accountID: viewerID)
            guard !Task.isCancelled, requestID == token else { return nil }
            socialSnapshot = result
            socialFailed = false
            return isFollowing(profileID)
        } catch {
            if !Task.isCancelled, requestID == token { socialFailed = true }
            return nil
        }
    }

    func loadTrades(_ profileID: UUID, client: any NativeTraderDetailProviding, reset: Bool,
                    demo: TradeFeedDemoData? = nil) async {
        guard scope?.profileID == profileID else { return }
        await trades.load(reset: reset) { offset in
            if let demo { return try demo.page(offset: offset, profileID: profileID) }
            return try await client.trades(profileID: profileID, offset: offset)
        }
    }

    private func loadPortfolio(_ profileID: UUID, client: any NativeTraderDetailProviding, token: UUID) async {
        portfolioFailed = false
        do {
            let result = try await client.portfolio(profileID)
            try result.validate()
            guard !Task.isCancelled, requestID == token else { return }
            portfolio = result
        } catch {
            guard !Task.isCancelled, requestID == token else { return }
            portfolio = nil
            portfolioFailed = true
        }
    }

    private func loadSocial(_ viewerID: UUID, client: any NativeTraderDetailProviding, token: UUID) async {
        socialFailed = false
        do {
            let result = try await client.social(accountID: viewerID)
            try result.validate()
            guard !Task.isCancelled, requestID == token else { return }
            socialSnapshot = result
        } catch {
            guard !Task.isCancelled, requestID == token else { return }
            socialFailed = true
        }
    }
}
