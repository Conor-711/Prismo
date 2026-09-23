import Foundation

enum PortfolioBootstrapStrategy {
    case localOnly
    case remoteFallback
}

private struct BSmartCacheSnapshot: Codable {
    let savedAt: Date
    let dataAsOf: Date?
    let dailyDigestSnapshot: DailyDigestSnapshot?
    let signals: [PortfolioSignal]
    let smartAccountUpdates: [SmartAccountUpdate]
    let smartMoneyMovements: [SmartMoneyMovement]
    let intelligence: [TickerIntelligence]
    let smartAccounts: [SmartAccountProfile]
    let smartMoney: [SmartMoneySignal]
    let smartAccountFreshness: BSmartDataFreshness?
    let smartMoneyFreshness: BSmartDataFreshness?
    let portfolioHistory: [PortfolioValuePoint]?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var positions: [PortfolioPosition] = []
    @Published private(set) var signals: [PortfolioSignal] = []
    @Published private(set) var smartAccountUpdates: [SmartAccountUpdate] = []
    @Published private(set) var smartMoneyMovements: [SmartMoneyMovement] = []
    @Published private(set) var intelligence: [TickerIntelligence] = []
    @Published private(set) var smartAccounts: [SmartAccountProfile] = []
    @Published private(set) var smartAccountEvidenceByAuthor: [String: [SmartAccountUpdate]] = [:]
    private var accountEvidenceRequests: [String: UUID] = [:]
    private var lastAccountEvidenceRefreshAt: Date?
    @Published private(set) var loadingSmartAccountEvidenceIDs: Set<String> = []
    @Published private(set) var smartMoney: [SmartMoneySignal] = []
    @Published private(set) var smartMoneyEvidenceByAccount: [String: [SmartMoneyRepresentativeEvidence]] = [:]
    @Published private(set) var loadingSmartMoneyEvidenceIDs: Set<String> = []
    @Published private(set) var dailyDigestSnapshot: DailyDigestSnapshot?
    @Published private(set) var signalUserStates: [UUID: SignalUserState] = [:]
    @Published private(set) var readTodayActivityIDs: Set<UUID> = []
    @Published private(set) var followedSmartAccountIDs: Set<String> = []
    @Published private(set) var followedSmartMoneyIDs: Set<String> = []
    @Published private(set) var linkedBrokerageAccounts: [LinkedBrokerageAccount] = []
    @Published private(set) var portfolioHistory: [PortfolioValuePoint] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingLiveIntelligence = false
    @Published private(set) var hasFinishedInitialLoad = false
    @Published private(set) var hasResolvedAccountState = true
    @Published private(set) var accountStateError: String?
    @Published private(set) var hasCompletedPortfolioSetup = false
    @Published private(set) var lastDataRefreshAt: Date?
    @Published private(set) var smartAccountFreshness: BSmartDataFreshness?
    @Published private(set) var smartMoneyFreshness: BSmartDataFreshness?
    @Published private(set) var errorMessage: String?
    let isUsingDemoData: Bool

    private let client: BSmartAPIClient
    func fetchTradeFeed(offset: Int, profileID: UUID? = nil) async throws -> TradeFeedPage {
        try await client.fetchTradeFeed(offset: offset, profileID: profileID)
    }
    func fetchPublicTrader(profileID: UUID) async throws -> FeedPublicProfile {
        try await client.fetchPublicTrader(profileID: profileID)
    }
    func fetchOpinionTraders(opinionID: UUID, offset: Int) async throws -> OpinionTradersPage {
        try await client.fetchOpinionTraders(opinionID: opinionID, offset: offset)
    }
    private let bootstrapFallbackClient: BSmartAPIClient?
    private let accountPreferences: AccountPreferencesProviding?
    private let directMrCollieClient: DirectMrCollieAnswering?
    private let syncCoordinator: BSmartSyncCoordinator?
    private let defaults: UserDefaults
    private let portfolioBootstrapStrategy: PortfolioBootstrapStrategy
    private let savedPortfolioKey = "bsmart.portfolio.v1"
    private let completedPortfolioSetupKey = "bsmart.portfolio-setup-complete.v1"
    private let accountOnboardingCompletionPrefix = "bsmart.initial-onboarding-complete.v2"
    private let savedSignalStatesKey = "bsmart.signal-user-states.v1"
    private let readTodayActivityIDsKey = "bsmart.today-read-activities.v1"
    private let savedClientCacheKey = "bsmart.client-cache.v1"
    private let followedSmartAccountsKey = "bsmart.followed-smart-accounts.v1"
    private let followedSmartMoneyKey = "bsmart.followed-smart-money.v1"
    private let followedOwnerKey = "bsmart.followed-intelligence-owner.v1"
    private let pendingFollowsPrefix = "bsmart.pending-follows.v1"
    private let remoteFollowsMigratedPrefix = "bsmart.remote-follows-migrated.v1"
    private let linkedBrokerageAccountsKey = "bsmart.linked-brokerages.v1"
    private let valuationHistoryKey = "bsmart.portfolio-valuations.v1"
    private var remotePortfolioContext: String?
    private var activeAccountID: UUID?
    private var hasLoaded = false
    private var loadGeneration = UUID()
    private var remoteLoadTask: Task<Void, Never>?
    private var isSyncingFollows = false
    private var pendingFollows: [String: PendingFollow] = [:]

    private struct PendingFollow: Codable, Equatable {
        let kind: AccountFollowKind
        let id: String
        let following: Bool
    }

    init(
        client: BSmartAPIClient = BundleBSmartAPIClient(),
        bootstrapFallbackClient: BSmartAPIClient? = nil,
        accountPreferences: AccountPreferencesProviding? = nil,
        directMrCollieClient: DirectMrCollieAnswering? = nil,
        defaults: UserDefaults = .standard,
        portfolioBootstrapStrategy: PortfolioBootstrapStrategy = .remoteFallback,
        syncCoordinator: BSmartSyncCoordinator? = nil,
        isUsingDemoData: Bool = false
    ) {
        self.client = client
        self.bootstrapFallbackClient = bootstrapFallbackClient
        self.accountPreferences = accountPreferences
        self.directMrCollieClient = directMrCollieClient
        self.defaults = defaults
        self.portfolioBootstrapStrategy = portfolioBootstrapStrategy
        self.syncCoordinator = syncCoordinator
        self.isUsingDemoData = isUsingDemoData
        linkedBrokerageAccounts = Self.restoreLinkedBrokerageAccounts(
            from: defaults,
            key: linkedBrokerageAccountsKey
        )
    }

    var valuedHeldPositions: [PortfolioPosition] {
        heldPositions.filter { $0.shares > 0 && $0.currentPrice > 0 }
    }

    var returnEligiblePositions: [PortfolioPosition] {
        valuedHeldPositions.filter { $0.averageCost > 0 }
    }

    var hasAnyPortfolioValuation: Bool {
        !valuedHeldPositions.isEmpty
    }

    var hasCompletePortfolioValuation: Bool {
        !heldPositions.isEmpty && valuedHeldPositions.count == heldPositions.count
    }

    var hasAnyPortfolioReturn: Bool {
        !returnEligiblePositions.isEmpty
    }

    var hasCompletePortfolioReturn: Bool {
        !heldPositions.isEmpty && returnEligiblePositions.count == heldPositions.count
    }

    var declaredPortfolioWeight: Double {
        heldPositions.compactMap(\.portfolioWeight).reduce(0, +)
    }

    var portfolioValue: Double {
        valuedHeldPositions.reduce(0) { $0 + $1.marketValue }
    }

    var portfolioCostBasis: Double {
        returnEligiblePositions.reduce(0) { $0 + $1.costBasis }
    }

    var portfolioGain: Double {
        returnEligiblePositions.reduce(0) { $0 + $1.unrealizedGain }
    }

    var portfolioGainPercent: Double {
        guard portfolioCostBasis != 0 else { return 0 }
        return portfolioGain / portfolioCostBasis
    }

    var heldPositions: [PortfolioPosition] {
        positions.filter(\.isPosition)
    }

    var watchlist: [PortfolioPosition] {
        positions.filter { !$0.isPosition }
    }

    var personalizedPortfolioSignals: [PersonalizedPortfolioSignal] {
        trackedSignals
            .filter { !signalUserState(for: $0.id).isIgnored }
            .map { signal in
                PersonalizedPortfolioSignal(
                    signal: signal,
                    personalization: personalization(for: signal)
                )
            }
            .sorted { lhs, rhs in
                if lhs.personalization.relevanceScore != rhs.personalization.relevanceScore {
                    return lhs.personalization.relevanceScore > rhs.personalization.relevanceScore
                }
                return lhs.signal.occurredAt > rhs.signal.occurredAt
            }
    }

    var personalizedDailyDigestSignals: [PersonalizedPortfolioSignal] {
        let source = dailyDigestSnapshot?.signals ?? trackedSignals
        let trackedTickers = Set(positions.map { $0.ticker.uppercased() })
        return source
            .filter { trackedTickers.contains($0.ticker.uppercased()) }
            .map { signal in
                PersonalizedPortfolioSignal(
                    signal: signal,
                    personalization: personalization(for: signal)
                )
            }
            .sorted { lhs, rhs in
                if lhs.personalization.relevanceScore != rhs.personalization.relevanceScore {
                    return lhs.personalization.relevanceScore > rhs.personalization.relevanceScore
                }
                return lhs.signal.occurredAt > rhs.signal.occurredAt
            }
    }

    var portfolioSignals: [PortfolioSignal] {
        personalizedPortfolioSignals.map(\.signal)
    }

    var ignoredPortfolioSignals: [PortfolioSignal] {
        trackedSignals
            .filter { signalUserState(for: $0.id).isIgnored }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var savedSignals: [PortfolioSignal] {
        signals
            .filter { signalUserState(for: $0.id).isSaved }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var unreadPortfolioSignalCount: Int {
        portfolioSignals.filter { !signalUserState(for: $0.id).isRead }.count
    }

    var followedIntelligenceSignals: [PortfolioSignal] {
        let trackedTickers = Set(positions.map { $0.ticker.uppercased() })
        return signals
            .filter { !trackedTickers.contains($0.ticker.uppercased()) }
            .filter { !signalUserState(for: $0.id).isIgnored }
            .filter(signalReferencesFollowedActor)
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var opportunitySignals: [PortfolioSignal] {
        let trackedTickers = Set(positions.map { $0.ticker.uppercased() })
        return signals
            .filter { !trackedTickers.contains($0.ticker.uppercased()) }
            .filter { !signalUserState(for: $0.id).isIgnored }
            .filter { $0.priority == .critical || $0.priority == .important }
            .sorted { lhs, rhs in
                let lhsPriority = priorityValue(lhs.priority)
                let rhsPriority = priorityValue(rhs.priority)
                if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                return lhs.occurredAt > rhs.occurredAt
            }
    }

    private var trackedSignals: [PortfolioSignal] {
        let trackedTickers = Set(positions.map { $0.ticker.uppercased() })
        return signals.filter { trackedTickers.contains($0.ticker.uppercased()) }
    }

    func activateAccountContext(_ accountID: UUID?) {
        guard activeAccountID != accountID else { return }
        activeAccountID = accountID
        restoreFollowedIntelligence()
        restorePendingFollows()
        hasCompletedPortfolioSetup = restoredInitialOnboardingCompletion()
        hasResolvedAccountState = accountID == nil || accountPreferences == nil
        accountStateError = nil
    }

    func requireInitialOnboarding(for accountID: UUID) {
        activeAccountID = accountID
        defaults.set(false, forKey: onboardingCompletionKey(for: accountID))
        hasCompletedPortfolioSetup = false
    }

    func restoreAccountState() async {
        guard let accountID = activeAccountID, let accountPreferences else {
            hasResolvedAccountState = true
            return
        }
        accountStateError = nil
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.activeAccountID == accountID,
                  !self.hasResolvedAccountState else { return }
            self.accountStateError = "Account data is taking longer than expected. Please try again.".bSmartLocalized
        }
        defer { timeout.cancel() }
        do {
            var remote = try await accountPreferences.load(accountID: accountID)
            guard activeAccountID == accountID else { return }
            let localCompleted = restoredInitialOnboardingCompletion()
            if localCompleted && !remote.onboardingCompleted {
                remote = try await accountPreferences.completeOnboarding(accountID: accountID)
            }
            guard activeAccountID == accountID else { return }

            let migratedKey = remoteFollowsMigratedPrefix + "." + accountID.uuidString.lowercased()
            if !defaults.bool(forKey: migratedKey) {
                for id in followedSmartAccountIDs where !remote.followedAuthors.contains(id) {
                    queueFollow(.author, id: id, following: true, synchronize: false)
                }
                for id in followedSmartMoneyIDs where !remote.followedMoney.contains(id) {
                    queueFollow(.money, id: id, following: true, synchronize: false)
                }
                defaults.set(true, forKey: migratedKey)
            }
            followedSmartAccountIDs = Set(remote.followedAuthors)
            followedSmartMoneyIDs = Set(remote.followedMoney)
            for follow in pendingFollows.values {
                if follow.kind == .author {
                    if follow.following { followedSmartAccountIDs.insert(follow.id) }
                    else { followedSmartAccountIDs.remove(follow.id) }
                } else {
                    if follow.following { followedSmartMoneyIDs.insert(follow.id) }
                    else { followedSmartMoneyIDs.remove(follow.id) }
                }
            }
            persistFollowedIntelligence()
            hasCompletedPortfolioSetup = remote.onboardingCompleted
            defaults.set(remote.onboardingCompleted, forKey: activeOnboardingCompletionKey)
            hasResolvedAccountState = true
            accountStateError = nil
            Task { await synchronizePendingFollows() }
        } catch {
            guard activeAccountID == accountID else { return }
            if defaults.object(forKey: activeOnboardingCompletionKey) != nil {
                hasResolvedAccountState = true
            } else {
                hasResolvedAccountState = false
                accountStateError = error.localizedDescription
            }
        }
    }

    func completeInitialOnboardingRemotely() async throws {
        if let accountID = activeAccountID, let accountPreferences {
            _ = try await accountPreferences.completeOnboarding(accountID: accountID)
            guard activeAccountID == accountID else { throw CancellationError() }
        }
        completeInitialOnboarding()
    }

    func load() async {
        guard !hasLoaded else { return }
        remoteLoadTask?.cancel()
        loadGeneration = UUID()
        let generation = loadGeneration
        hasLoaded = true
        isLoading = true
        errorMessage = nil

        let localPortfolio = restoredPortfolio()
        positions = localPortfolio ?? []
        hasCompletedPortfolioSetup = restoredInitialOnboardingCompletion()
            || (activeAccountID == nil && !positions.isEmpty)
        restoreSignalUserStates()
        restoreReadTodayActivities()
        restoreFollowedIntelligence()
        let restoredCache = restoreClientCache()
        if restoredCache {
            refreshCurrentPrices()
            hasFinishedInitialLoad = true
        }

        var hasBootstrap = restoredCache
        if !restoredCache, let bootstrapFallbackClient {
            do {
                try await loadSnapshot(from: bootstrapFallbackClient, localPortfolio: localPortfolio, persist: false)
                hasBootstrap = true
                hasFinishedInitialLoad = true
            } catch {
                // The network path below remains available if bundled content cannot load.
            }
        }
        let task = Task { await finishRemoteLoad(localPortfolio: localPortfolio,
                                                 hasBootstrap: hasBootstrap, generation: generation) }
        remoteLoadTask = task
        if hasBootstrap, bootstrapFallbackClient != nil {
            return
        }

        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, generation == loadGeneration, !hasFinishedInitialLoad else { return }
            errorMessage = "Loading is taking longer than expected. Please try again.".bSmartLocalized
            hasFinishedInitialLoad = true
            hasLoaded = false
        }
        await task.value
        watchdog.cancel()
    }

    private func finishRemoteLoad(localPortfolio: [PortfolioPosition]?, hasBootstrap: Bool,
                                  generation: UUID) async {
        defer { if generation == loadGeneration { remoteLoadTask = nil } }
        do {
            try await loadSnapshot(from: client, localPortfolio: localPortfolio)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            refreshSourceFreshness()
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            hasLoaded = false
            errorMessage = error.localizedDescription
        }

        isLoading = false
        hasFinishedInitialLoad = true
    }

    private func loadSnapshot(
        from source: BSmartAPIClient,
        localPortfolio: [PortfolioPosition]?,
        persist: Bool = true
    ) async throws {
        try await (source as? BSmartContentRefreshing)?.prepareContentRefresh()
        try Task.checkCancellation()
        async let loadedPortfolio = source.fetchPortfolio()
        async let loadedPortfolioHistory = fetchPortfolioHistoryIfAvailable(from: source)
        async let loadedSignals = source.fetchSignals()
        async let loadedAccountUpdates = source.fetchSmartAccountUpdates()
        async let loadedMoneyMovements = source.fetchSmartMoneyMovements()
        async let loadedIntelligence = source.fetchTickerIntelligence()
        async let loadedAccounts = source.fetchSmartAccounts()
        async let loadedMoney = source.fetchSmartMoney()
        async let loadedDigest = fetchDailyDigestIfAvailable(from: source)

        let remotePortfolio = try await loadedPortfolio
        try Task.checkCancellation()
        remotePortfolioContext = PortfolioValuationHistory.context(for: remotePortfolio)
        positions = localPortfolio
            ?? (portfolioBootstrapStrategy == .remoteFallback ? remotePortfolio : [])
        hasCompletedPortfolioSetup = restoredInitialOnboardingCompletion()
            || (activeAccountID == nil && !positions.isEmpty)
        let history = await loadedPortfolioHistory
        portfolioHistory = PortfolioValuationHistory.context(for: positions) == remotePortfolioContext ? history : []
        signals = (try await loadedSignals).sorted { $0.occurredAt > $1.occurredAt }
        smartAccountUpdates = (try await loadedAccountUpdates).sorted { $0.publishedAt > $1.publishedAt }
        smartMoneyMovements = (try await loadedMoneyMovements).sorted { $0.observedAt > $1.observedAt }
        intelligence = (try await loadedIntelligence).sorted { $0.ticker < $1.ticker }
        refreshCurrentPrices()
        smartAccounts = (try await loadedAccounts).sorted { $0.score > $1.score }
        smartMoney = (try await loadedMoney).sorted { $0.changedAt > $1.changedAt }
        dailyDigestSnapshot = await loadedDigest
        lastDataRefreshAt = resolvedLatestDataAsOf()
        if persist {
            persistClientCache()
        }
        enqueueLocalStateBootstrap()
    }

    func retry() async {
        hasLoaded = false
        if signals.isEmpty { hasFinishedInitialLoad = false }
        await load()
    }

    func refreshLiveIntelligence() async {
        guard hasFinishedInitialLoad, !isLoading, !isRefreshingLiveIntelligence else { return }
        isRefreshingLiveIntelligence = true
        defer { isRefreshingLiveIntelligence = false }

        do {
            try await (client as? BSmartContentRefreshing)?.prepareContentRefresh()
            async let loadedSignals = client.fetchSignals()
            async let loadedPortfolioHistory = fetchPortfolioHistoryIfAvailable()
            async let loadedAccountUpdates = client.fetchSmartAccountUpdates()
            async let loadedMoneyMovements = client.fetchSmartMoneyMovements()
            async let loadedIntelligence = client.fetchTickerIntelligence()
            async let loadedMoney = client.fetchSmartMoney()
            async let loadedAccounts = client.fetchSmartAccounts()

            let refreshed = try await (
                loadedSignals,
                loadedAccountUpdates,
                loadedMoneyMovements,
                loadedIntelligence,
                loadedMoney,
                loadedAccounts
            )
            let accountsChanged = Set(smartAccounts) != Set(refreshed.5)
                || Set(smartAccountUpdates) != Set(refreshed.1)
            signals = refreshed.0.sorted { $0.occurredAt > $1.occurredAt }
            smartAccountUpdates = refreshed.1.sorted { $0.publishedAt > $1.publishedAt }
            smartMoneyMovements = refreshed.2.sorted { $0.observedAt > $1.observedAt }
            intelligence = refreshed.3.sorted { $0.ticker < $1.ticker }
            smartMoney = refreshed.4.sorted { $0.changedAt > $1.changedAt }
            smartAccounts = refreshed.5.sorted { $0.score > $1.score }
            let history = await loadedPortfolioHistory
            if PortfolioValuationHistory.context(for: positions) == remotePortfolioContext {
                portfolioHistory = history
            }
            refreshSourceFreshness()
            refreshCurrentPrices()
            lastDataRefreshAt = resolvedLatestDataAsOf()
            errorMessage = nil
            persistClientCache()
            // A newly published ranking may also change historical representative works.
            if accountsChanged || lastAccountEvidenceRefreshAt.map({ Date().timeIntervalSince($0) >= 300 }) != false {
                lastAccountEvidenceRefreshAt = Date()
                let activeIDs = Set(smartAccounts.map(\.id))
                smartAccountEvidenceByAuthor = smartAccountEvidenceByAuthor.filter { activeIDs.contains($0.key) }
                accountEvidenceRequests = accountEvidenceRequests.filter { activeIDs.contains($0.key) }
                loadingSmartAccountEvidenceIDs.formIntersection(activeIDs)
                for account in smartAccounts where smartAccountEvidenceByAuthor[account.id] != nil
                    || loadingSmartAccountEvidenceIDs.contains(account.id) {
                    await loadSmartAccountEvidence(for: account, refresh: true)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func completePortfolioSetup() -> Bool {
        guard !positions.isEmpty || !linkedBrokerageAccounts.isEmpty else { return false }
        completeInitialOnboarding()
        return true
    }

    func completeInitialOnboarding() {
        hasCompletedPortfolioSetup = true
        defaults.set(true, forKey: activeOnboardingCompletionKey)
    }

    private var activeOnboardingCompletionKey: String {
        guard let activeAccountID else { return completedPortfolioSetupKey }
        return onboardingCompletionKey(for: activeAccountID)
    }

    private func onboardingCompletionKey(for accountID: UUID) -> String {
        "\(accountOnboardingCompletionPrefix).\(accountID.uuidString.lowercased())"
    }

    private func restoredInitialOnboardingCompletion() -> Bool {
        let key = activeOnboardingCompletionKey
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return false
    }

    func addPosition(
        ticker: String,
        companyName: String,
        shares: Double,
        averageCost: Double
    ) {
        _ = savePortfolioEntry(
            id: nil,
            ticker: ticker,
            companyName: companyName,
            kind: .position,
            shares: shares,
            averageCost: averageCost,
            portfolioWeight: nil
        )
    }

    @discardableResult
    func savePortfolioEntry(
        id: UUID?,
        ticker: String,
        companyName: String,
        kind: PortfolioEntryKind,
        shares: Double?,
        averageCost: Double?,
        portfolioWeight: Double?
    ) -> Bool {
        let normalizedTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedShares = shares ?? 0
        let normalizedCost = averageCost ?? 0
        if let portfolioWeight, !(0...1).contains(portfolioWeight) { return false }
        let normalizedWeight = portfolioWeight.flatMap { $0 > 0 ? $0 : nil }
        guard !normalizedTicker.isEmpty, normalizedShares >= 0, normalizedCost >= 0 else { return false }
        if kind == .position, normalizedShares == 0, normalizedWeight == nil { return false }

        let existingIndex = id.flatMap { entryId in positions.firstIndex { $0.id == entryId } }
            ?? positions.firstIndex { $0.ticker == normalizedTicker }
        let changesHoldings = kind == .position || existingIndex.map { positions[$0].isPosition } == true
        let normalizedCompanyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownCompanyName = intelligence.first { $0.ticker == normalizedTicker }?.companyName
        let knownPrice = intelligence.first { $0.ticker == normalizedTicker }?.currentPrice
            ?? existingIndex.map { positions[$0].currentPrice }
            ?? normalizedCost
        let position = PortfolioPosition(
            id: existingIndex.map { positions[$0].id } ?? UUID(),
            ticker: normalizedTicker,
            companyName: normalizedCompanyName.isEmpty
                ? knownCompanyName ?? normalizedTicker
                : normalizedCompanyName,
            shares: kind == .position ? normalizedShares : 0,
            averageCost: kind == .position ? normalizedCost : 0,
            currentPrice: knownPrice,
            entryKind: kind,
            portfolioWeight: kind == .position ? normalizedWeight : nil
        )
        if let existingIndex {
            positions[existingIndex] = position
        } else {
            positions.append(position)
        }
        if changesHoldings { portfolioHistory = [] }
        persistPortfolio()
        enqueuePortfolioUpsert(position)
        return true
    }

    /// Holdings are already tracked; following must never overwrite their cost or quantity.
    func setTickerFollowed(_ followed: Bool, ticker: String, companyName: String) {
        let symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return }
        let existing = position(for: symbol)
        guard existing?.isPosition != true else { return }
        if followed {
            guard existing == nil else { return }
            _ = savePortfolioEntry(id: nil, ticker: symbol, companyName: companyName,
                                   kind: .watchlist, shares: nil, averageCost: nil, portfolioWeight: nil)
        } else if let existing {
            positions.removeAll { $0.id == existing.id }
            persistPortfolio()
            enqueuePortfolioDelete(existing.id)
        }
    }

    func deletePositions(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let removed = positions.remove(at: index)
            enqueuePortfolioDelete(removed.id)
        }
        portfolioHistory = []
        persistPortfolio()
    }

    func deletePosition(id: UUID) {
        positions.removeAll { $0.id == id }
        portfolioHistory = []
        persistPortfolio()
        enqueuePortfolioDelete(id)
    }

    func resetLocalAppData() async {
        positions = []
        signalUserStates = [:]
        readTodayActivityIDs = []
        followedSmartAccountIDs = []
        followedSmartMoneyIDs = []
        linkedBrokerageAccounts = []
        portfolioHistory = []
        hasCompletedPortfolioSetup = false

        [
            savedPortfolioKey,
            completedPortfolioSetupKey,
            savedSignalStatesKey,
            readTodayActivityIDsKey,
            savedClientCacheKey,
            followedSmartAccountsKey,
            followedSmartMoneyKey,
            linkedBrokerageAccountsKey
        ].forEach(defaults.removeObject(forKey:))
        defaults.removeObject(forKey: activeOnboardingCompletionKey)
        defaults.removeObject(forKey: valuationHistoryKey)
        defaults.removeObject(forKey: followedKey(followedSmartAccountsKey))
        defaults.removeObject(forKey: followedKey(followedSmartMoneyKey))
        if let pendingFollowsKey { defaults.removeObject(forKey: pendingFollowsKey) }
        pendingFollows = [:]

        await syncCoordinator?.clearPendingOperations()
    }

    func linkedBrokerageAccount(for provider: BrokerageProvider) -> LinkedBrokerageAccount? {
        linkedBrokerageAccounts.first { $0.provider == provider }
    }

    @discardableResult
    func connectBrokeragePrototype(
        provider: BrokerageProvider,
        detectedHoldingCount: Int,
        importedPositionCount: Int
    ) -> LinkedBrokerageAccount {
        let now = Date()
        let existing = linkedBrokerageAccount(for: provider)
        let account = LinkedBrokerageAccount(
            id: existing?.id ?? UUID(),
            provider: provider,
            connectedAt: existing?.connectedAt ?? now,
            lastSyncedAt: now,
            detectedHoldingCount: max(0, detectedHoldingCount),
            importedPositionCount: max(0, importedPositionCount),
            isPrototype: true
        )

        if let index = linkedBrokerageAccounts.firstIndex(where: { $0.provider == provider }) {
            linkedBrokerageAccounts[index] = account
        } else {
            linkedBrokerageAccounts.append(account)
            linkedBrokerageAccounts.sort { $0.provider.displayName < $1.provider.displayName }
        }
        persistLinkedBrokerageAccounts()
        return account
    }

    func refreshBrokeragePrototype(_ provider: BrokerageProvider) {
        guard let index = linkedBrokerageAccounts.firstIndex(where: { $0.provider == provider }) else { return }
        linkedBrokerageAccounts[index].lastSyncedAt = Date()
        persistLinkedBrokerageAccounts()
    }

    func disconnectBrokerage(_ provider: BrokerageProvider) {
        linkedBrokerageAccounts.removeAll { $0.provider == provider }
        persistLinkedBrokerageAccounts()
    }

    func signalUserState(for signalId: UUID) -> SignalUserState {
        signalUserStates[signalId] ?? SignalUserState(signalId: signalId)
    }

    func markSignalRead(_ signalId: UUID, isRead: Bool = true) {
        updateSignalUserState(signalId) { $0.isRead = isRead }
    }

    func isTodayActivityRead(_ activityID: UUID) -> Bool {
        readTodayActivityIDs.contains(activityID)
    }

    func markTodayActivityRead(_ activityID: UUID, isRead: Bool = true) {
        if isRead {
            readTodayActivityIDs.insert(activityID)
        } else {
            readTodayActivityIDs.remove(activityID)
        }
        persistReadTodayActivities()
    }

    func toggleSignalSaved(_ signalId: UUID) {
        let willSave = !signalUserState(for: signalId).isSaved
        updateSignalUserState(signalId) {
            $0.isSaved.toggle()
            if $0.isSaved { $0.isIgnored = false }
        }
        if willSave {
            trackSignalAction(.signalSaved, signalId: signalId)
        }
    }

    func ignoreSignal(_ signalId: UUID) {
        updateSignalUserState(signalId) {
            $0.isIgnored = true
            $0.isSaved = false
        }
        trackSignalAction(.signalIgnored, signalId: signalId)
    }

    func restoreIgnoredSignal(_ signalId: UUID) {
        updateSignalUserState(signalId) { $0.isIgnored = false }
    }

    func setSignalFeedback(_ feedback: SignalFeedback?, for signalId: UUID) {
        updateSignalUserState(signalId) { $0.feedback = feedback }
        if feedback != nil {
            trackSignalAction(.signalFeedback, signalId: signalId)
        }
    }

    func trackSignalOpened(_ signal: PortfolioSignal) {
        enqueueTelemetry(ClientTelemetryEvent(
            name: .signalOpened,
            signalId: signal.id,
            ticker: signal.ticker,
            context: .signalDetail
        ))
    }

    func trackEvidenceOpened(_ evidence: PortfolioSignalEvidence, in signal: PortfolioSignal) {
        enqueueTelemetry(ClientTelemetryEvent(
            name: .evidenceOpened,
            signalId: signal.id,
            ticker: signal.ticker,
            evidenceId: evidence.id,
            source: evidence.source,
            context: .signalDetail
        ))
    }

    func trackDailyDigestOpened() {
        enqueueTelemetry(ClientTelemetryEvent(
            name: .dailyDigestOpened,
            context: .dailyDigest
        ))
    }

    func isFollowingSmartAccount(_ id: String) -> Bool {
        followedSmartAccountIDs.contains(id)
    }

    func toggleSmartAccountFollow(_ id: String) {
        if followedSmartAccountIDs.contains(id) {
            followedSmartAccountIDs.remove(id)
        } else {
            followedSmartAccountIDs.insert(id)
        }
        persistFollowedIntelligence()
        queueFollow(.author, id: id, following: followedSmartAccountIDs.contains(id))
    }

    func isFollowingSmartMoney(_ id: String) -> Bool {
        followedSmartMoneyIDs.contains(id)
    }

    func toggleSmartMoneyFollow(_ id: String) {
        if followedSmartMoneyIDs.contains(id) {
            followedSmartMoneyIDs.remove(id)
        } else {
            followedSmartMoneyIDs.insert(id)
        }
        persistFollowedIntelligence()
        queueFollow(.money, id: id, following: followedSmartMoneyIDs.contains(id))
    }

    func intelligence(for ticker: String) -> TickerIntelligence? {
        intelligence.first { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
    }

    func signals(for ticker: String) -> [PortfolioSignal] {
        signals.filter { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
    }

    func accountUpdates(for ticker: String) -> [SmartAccountUpdate] {
        smartAccountUpdates.filter { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
    }

    func moneyMovements(for ticker: String) -> [SmartMoneyMovement] {
        smartMoneyMovements.filter { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
    }

    func accountUpdate(id: UUID) -> SmartAccountUpdate? {
        smartAccountUpdates.first { $0.id == id }
    }

    func moneyMovement(id: UUID) -> SmartMoneyMovement? {
        smartMoneyMovements.first { $0.id == id }
    }

    func accountUpdates(for account: SmartAccountProfile) -> [SmartAccountUpdate] {
        smartAccountUpdates.filter { $0.authorId == account.id }
    }

    func smartAccountProfile(for update: SmartAccountUpdate) -> SmartAccountProfile {
        if let account = smartAccounts.first(where: {
            $0.id.caseInsensitiveCompare(update.authorId) == .orderedSame
        }) {
            return account
        }

        if let account = smartAccounts.first(where: {
            $0.name.caseInsensitiveCompare(update.authorName) == .orderedSame
                && $0.platform.caseInsensitiveCompare(update.platform) == .orderedSame
        }) {
            return account
        }

        return SmartAccountProfile(
            id: update.authorId,
            name: update.authorName,
            handle: update.authorName,
            platform: update.platform,
            score: update.score,
            scoreChange: 0,
            specialty: "Cross-sector equities",
            horizon: update.horizon,
            recentTicker: update.ticker,
            platformPercentile: update.platformPercentile,
            confidence: "observing",
            topTickers: [update.ticker],
            style: "Mixed",
            avatarURL: update.authorAvatarURL,
            followersCount: update.authorFollowersCount,
            verified: update.authorVerified
        )
    }

    func accountEvidence(for account: SmartAccountProfile) -> [SmartAccountUpdate] {
        smartAccountEvidenceByAuthor[account.id] ?? accountUpdates(for: account)
    }

    func representativeAccountEvidence(
        for account: SmartAccountProfile,
        limit: Int = 3
    ) -> [SmartAccountUpdate] {
        guard limit > 0 else { return [] }
        let candidates = accountEvidence(for: account)
            .filter { update in
                guard update.priceEvidence != nil,
                      update.settlement?.status.lowercased() == "settled",
                      (update.representativeTickerContribution ?? update.settlement?.contribution ?? 0) > 0
                else { return false }
                return update.evidenceRole?.lowercased() != "latest"
            }
            .sorted { lhs, rhs in
                let lhsRank = lhs.representativeTickerRank ?? .max
                let rhsRank = rhs.representativeTickerRank ?? .max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                let lhsContribution = lhs.representativeTickerContribution
                    ?? lhs.settlement?.contribution
                    ?? -.infinity
                let rhsContribution = rhs.representativeTickerContribution
                    ?? rhs.settlement?.contribution
                    ?? -.infinity
                if lhsContribution != rhsContribution {
                    return lhsContribution > rhsContribution
                }

                let lhsExcess = max(
                    abs(lhs.settlement?.marketExcessReturnPercent ?? 0),
                    abs(lhs.settlement?.industryExcessReturnPercent ?? 0)
                )
                let rhsExcess = max(
                    abs(rhs.settlement?.marketExcessReturnPercent ?? 0),
                    abs(rhs.settlement?.industryExcessReturnPercent ?? 0)
                )
                if lhsExcess != rhsExcess {
                    return lhsExcess > rhsExcess
                }
                return lhs.publishedAt > rhs.publishedAt
            }

        var seenTickers = Set<String>()
        var works: [SmartAccountUpdate] = []
        for candidate in candidates {
            let ticker = candidate.ticker.uppercased()
            guard seenTickers.insert(ticker).inserted else { continue }
            works.append(candidate)
            if works.count == limit { break }
        }
        return works
    }

    func isLoadingAccountEvidence(_ account: SmartAccountProfile) -> Bool {
        loadingSmartAccountEvidenceIDs.contains(account.id)
    }

    func loadSmartAccountEvidence(for account: SmartAccountProfile, refresh: Bool = false) async {
        if !refresh {
            guard smartAccountEvidenceByAuthor[account.id] == nil,
                  !loadingSmartAccountEvidenceIDs.contains(account.id) else { return }
        }

        let requestID = UUID()
        accountEvidenceRequests[account.id] = requestID

        loadingSmartAccountEvidenceIDs.insert(account.id)
        defer {
            if accountEvidenceRequests[account.id] == requestID {
                loadingSmartAccountEvidenceIDs.remove(account.id)
                accountEvidenceRequests.removeValue(forKey: account.id)
            }
        }
        do {
            var evidence = try await client.fetchSmartAccountEvidence(accountID: account.id)
            if evidence.isEmpty, isUsingDemoData, !refresh, let bootstrapFallbackClient {
                evidence = try await bootstrapFallbackClient.fetchSmartAccountEvidence(accountID: account.id)
            }
            guard accountEvidenceRequests[account.id] == requestID else { return }
            smartAccountEvidenceByAuthor[account.id] = evidence.sorted { $0.publishedAt > $1.publishedAt }
        } catch {
            guard !Task.isCancelled, !refresh, accountEvidenceRequests[account.id] == requestID else { return }
            let bundledEvidence = try? await bootstrapFallbackClient?.fetchSmartAccountEvidence(
                accountID: account.id
            )
            // A transport failure is not evidence of an empty history. Permit a later retry.
            if let bundledEvidence, !bundledEvidence.isEmpty, accountEvidenceRequests[account.id] == requestID {
                smartAccountEvidenceByAuthor[account.id] = bundledEvidence.sorted { $0.publishedAt > $1.publishedAt }
            }
        }
    }

    func moneyMovements(for signal: SmartMoneySignal) -> [SmartMoneyMovement] {
        smartMoneyMovements.filter { $0.accountId == signal.id }
    }

    func moneyEvidence(for signal: SmartMoneySignal) -> [SmartMoneyRepresentativeEvidence] {
        smartMoneyEvidenceByAccount[signal.id] ?? []
    }

    func isLoadingMoneyEvidence(_ signal: SmartMoneySignal) -> Bool {
        loadingSmartMoneyEvidenceIDs.contains(signal.id)
    }

    func loadSmartMoneyEvidence(for signal: SmartMoneySignal) async {
        guard smartMoneyEvidenceByAccount[signal.id] == nil,
              !loadingSmartMoneyEvidenceIDs.contains(signal.id)
        else { return }

        loadingSmartMoneyEvidenceIDs.insert(signal.id)
        defer { loadingSmartMoneyEvidenceIDs.remove(signal.id) }
        do {
            var evidence = try await client.fetchSmartMoneyEvidence(accountID: signal.id)
            if evidence.isEmpty, let bootstrapFallbackClient {
                evidence = try await bootstrapFallbackClient.fetchSmartMoneyEvidence(accountID: signal.id)
            }
            smartMoneyEvidenceByAccount[signal.id] = evidence.sorted {
                $0.representativeRank < $1.representativeRank
            }
        } catch {
            let bundledEvidence = try? await bootstrapFallbackClient?.fetchSmartMoneyEvidence(
                accountID: signal.id
            )
            smartMoneyEvidenceByAccount[signal.id] = (bundledEvidence ?? []).sorted {
                $0.representativeRank < $1.representativeRank
            }
        }
    }

    func position(for ticker: String) -> PortfolioPosition? {
        positions.first { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
    }

    func positionWeight(for ticker: String) -> Double {
        guard let position = position(for: ticker), position.isPosition else { return 0 }
        if let declaredWeight = position.portfolioWeight { return declaredWeight }
        guard portfolioValue > 0 else { return 0 }
        return position.marketValue / portfolioValue
    }

    func personalization(for signal: PortfolioSignal) -> PortfolioSignalPersonalization {
        PortfolioSignalPersonalizer.personalize(
            signal: signal,
            position: position(for: signal.ticker),
            resolvedWeight: positionWeight(for: signal.ticker)
        )
    }

    func queryMrCollie(
        _ question: String,
        locale: String,
        conversation: [MrCollieConversationTurn] = []
    ) async throws -> MrCollieResponse {
        let query = MrCollieQuery(
            question: question,
            locale: locale,
            conversation: conversation
        )
        if let directMrCollieClient {
            return try await directMrCollieClient.answer(
                query: query,
                portfolio: positions,
                signals: signals,
                smartAccountUpdates: smartAccountUpdates,
                smartMoneyMovements: smartMoneyMovements,
                intelligence: intelligence
            )
        }
        return try await client.queryMrCollie(query)
    }

    var canQueryMrCollieRemotely: Bool {
        directMrCollieClient != nil || !isUsingDemoData
    }

    private func priorityValue(_ priority: SignalPriority) -> Int {
        switch priority {
        case .critical: 3
        case .important: 2
        case .notable: 1
        }
    }

    private func updateSignalUserState(
        _ signalId: UUID,
        change: (inout SignalUserState) -> Void
    ) {
        var state = signalUserState(for: signalId)
        change(&state)
        state.updatedAt = Date()
        signalUserStates[signalId] = state
        persistSignalUserStates()
        enqueueSignalState(state)
    }

    private func persistPortfolio() {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        defaults.set(data, forKey: savedPortfolioKey)
        recordPortfolioValuation()
    }

    private func recordPortfolioValuation() {
        let context = PortfolioValuationHistory.context(for: positions)
        let saved = defaults.data(forKey: valuationHistoryKey).flatMap {
            try? JSONDecoder().decode(PortfolioValuationHistory.self, from: $0)
        }
        let prior = saved?.context == context ? saved?.points ?? [] : []
        // Server history belongs to its portfolio, never to a user's different manual basket.
        let imported = context == remotePortfolioContext ? portfolioHistory : []
        let now = Date()
        let combined = PortfolioValuationHistory.normalized(imported + prior, now: now)
        let values = hasCompletePortfolioValuation
            ? PortfolioValuationHistory.recording(portfolioValue, at: now, in: combined)
            : combined
        portfolioHistory = values
        let snapshot = PortfolioValuationHistory(context: context, points: values)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: valuationHistoryKey) }
    }

    private func restoredPortfolio() -> [PortfolioPosition]? {
        guard let data = defaults.data(forKey: savedPortfolioKey) else { return nil }
        return try? JSONDecoder().decode([PortfolioPosition].self, from: data)
    }

    private func persistLinkedBrokerageAccounts() {
        guard let data = try? JSONEncoder().encode(linkedBrokerageAccounts) else { return }
        defaults.set(data, forKey: linkedBrokerageAccountsKey)
    }

    private static func restoreLinkedBrokerageAccounts(
        from defaults: UserDefaults,
        key: String
    ) -> [LinkedBrokerageAccount] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([LinkedBrokerageAccount].self, from: data)) ?? []
    }

    private func persistSignalUserStates() {
        let states = signalUserStates.values.sorted { $0.updatedAt < $1.updatedAt }
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: savedSignalStatesKey)
    }

    private func persistReadTodayActivities() {
        defaults.set(readTodayActivityIDs.map(\.uuidString).sorted(), forKey: readTodayActivityIDsKey)
    }

    private func restoreReadTodayActivities() {
        readTodayActivityIDs = Set(
            (defaults.stringArray(forKey: readTodayActivityIDsKey) ?? []).compactMap(UUID.init(uuidString:))
        )
    }

    private func persistFollowedIntelligence() {
        defaults.set(followedSmartAccountIDs.sorted(), forKey: followedKey(followedSmartAccountsKey))
        defaults.set(followedSmartMoneyIDs.sorted(), forKey: followedKey(followedSmartMoneyKey))
    }

    private func restoreFollowedIntelligence() {
        followedSmartAccountIDs = Set(defaults.stringArray(forKey: followedKey(followedSmartAccountsKey)) ?? [])
        followedSmartMoneyIDs = Set(defaults.stringArray(forKey: followedKey(followedSmartMoneyKey)) ?? [])
    }

    private func followedKey(_ base: String) -> String {
        guard let activeAccountID else { return base }
        let account = activeAccountID.uuidString.lowercased()
        let scoped = base + "." + account
        if defaults.object(forKey: scoped) == nil {
            let owner = defaults.string(forKey: followedOwnerKey)
            if owner == nil || owner == account {
                defaults.set(defaults.stringArray(forKey: base) ?? [], forKey: scoped)
                if owner == nil { defaults.set(account, forKey: followedOwnerKey) }
            }
        }
        return scoped
    }

    private var pendingFollowsKey: String? {
        activeAccountID.map { pendingFollowsPrefix + "." + $0.uuidString.lowercased() }
    }

    private func restorePendingFollows() {
        guard let pendingFollowsKey, let data = defaults.data(forKey: pendingFollowsKey) else {
            pendingFollows = [:]
            return
        }
        pendingFollows = (try? JSONDecoder().decode([String: PendingFollow].self, from: data)) ?? [:]
    }

    private func persistPendingFollows() {
        guard let pendingFollowsKey else { return }
        defaults.set(try? JSONEncoder().encode(pendingFollows), forKey: pendingFollowsKey)
    }

    private func queueFollow(_ kind: AccountFollowKind, id: String, following: Bool,
                             synchronize: Bool = true) {
        guard activeAccountID != nil, accountPreferences != nil else { return }
        pendingFollows[kind.rawValue + ":" + id] = PendingFollow(kind: kind, id: id, following: following)
        persistPendingFollows()
        if synchronize { Task { await synchronizePendingFollows() } }
    }

    func synchronizePendingFollows() async {
        guard !isSyncingFollows, let accountID = activeAccountID, let accountPreferences else { return }
        isSyncingFollows = true
        defer { isSyncingFollows = false }
        while let key = pendingFollows.keys.sorted().first, let follow = pendingFollows[key] {
            do {
                _ = try await accountPreferences.setFollowing(follow.following, kind: follow.kind,
                                                               id: follow.id, accountID: accountID)
                guard activeAccountID == accountID else { return }
                if pendingFollows[key] == follow {
                    pendingFollows.removeValue(forKey: key)
                    persistPendingFollows()
                }
            } catch { return }
        }
    }

    private func signalReferencesFollowedActor(_ signal: PortfolioSignal) -> Bool {
        signal.evidence.contains { evidence in
            switch evidence.source {
            case .smartAccount:
                guard let update = accountUpdate(id: evidence.referenceId) else { return false }
                return followedSmartAccountIDs.contains(update.authorId)
            case .smartMoney:
                guard let movement = moneyMovement(id: evidence.referenceId) else { return false }
                return followedSmartMoneyIDs.contains(movement.accountId)
            }
        }
    }

    private func restoreSignalUserStates() {
        guard let data = defaults.data(forKey: savedSignalStatesKey),
              let states = try? JSONDecoder().decode([SignalUserState].self, from: data)
        else { return }
        signalUserStates = Dictionary(
            states.map { ($0.signalId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func persistClientCache() {
        let snapshot = BSmartCacheSnapshot(
            savedAt: Date(),
            dataAsOf: lastDataRefreshAt,
            dailyDigestSnapshot: dailyDigestSnapshot,
            signals: signals,
            smartAccountUpdates: smartAccountUpdates,
            smartMoneyMovements: smartMoneyMovements,
            intelligence: intelligence,
            smartAccounts: smartAccounts,
            smartMoney: smartMoney,
            smartAccountFreshness: smartAccountFreshness,
            smartMoneyFreshness: smartMoneyFreshness,
            portfolioHistory: portfolioHistory
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: savedClientCacheKey)
    }

    @discardableResult
    private func restoreClientCache() -> Bool {
        guard let data = defaults.data(forKey: savedClientCacheKey),
              let snapshot = try? JSONDecoder().decode(BSmartCacheSnapshot.self, from: data)
        else { return false }
        signals = snapshot.signals.sorted { $0.occurredAt > $1.occurredAt }
        dailyDigestSnapshot = snapshot.dailyDigestSnapshot
        smartAccountUpdates = snapshot.smartAccountUpdates.sorted { $0.publishedAt > $1.publishedAt }
        smartMoneyMovements = snapshot.smartMoneyMovements.sorted { $0.observedAt > $1.observedAt }
        intelligence = snapshot.intelligence.sorted { $0.ticker < $1.ticker }
        smartAccounts = snapshot.smartAccounts.sorted { $0.score > $1.score }
        smartMoney = snapshot.smartMoney.sorted { $0.changedAt > $1.changedAt }
        smartAccountFreshness = snapshot.smartAccountFreshness
        smartMoneyFreshness = snapshot.smartMoneyFreshness
        portfolioHistory = (snapshot.portfolioHistory ?? []).sorted { $0.timestamp < $1.timestamp }
        lastDataRefreshAt = snapshot.dataAsOf ?? snapshot.savedAt
        return true
    }

    private func fetchDailyDigestIfAvailable(
        from source: BSmartAPIClient? = nil
    ) async -> DailyDigestSnapshot? {
        do {
            return try await (source ?? client).fetchDailyDigest()
        } catch {
            return nil
        }
    }

    private func fetchPortfolioHistoryIfAvailable(
        from source: BSmartAPIClient? = nil
    ) async -> [PortfolioValuePoint] {
        do {
            return try await (source ?? client).fetchPortfolioHistory()
        } catch {
            return []
        }
    }

    private func resolvedLatestDataAsOf() -> Date {
        if let provider = client as? BSmartDataFreshnessProviding,
           let serverDataAsOf = provider.latestDataAsOf {
            return serverDataAsOf
        }

        let candidates = signals.map(\.dataAsOf)
            + intelligence.map(\.dataAsOf)
            + smartAccountUpdates.compactMap { $0.processedAt ?? $0.ingestedAt ?? $0.publishedAt }
            + smartMoneyMovements.map(\.observedAt)
            + smartMoney.compactMap { $0.sourceUpdatedAt ?? $0.changedAt }
            + [dailyDigestSnapshot?.dataAsOf].compactMap { $0 }
        return candidates.max() ?? Date()
    }

    private func refreshSourceFreshness() {
        guard let provider = client as? BSmartDataFreshnessProviding else { return }
        smartAccountFreshness = provider.freshness(for: .smartAccount) ?? smartAccountFreshness
        smartMoneyFreshness = provider.freshness(for: .smartMoney) ?? smartMoneyFreshness
    }

    private func refreshCurrentPrices() {
        let priceByTicker = Dictionary(
            intelligence.map { ($0.ticker.uppercased(), $0.currentPrice) },
            uniquingKeysWith: { _, latest in latest }
        )
        positions = positions.map { position in
            var updated = position
            if let currentPrice = priceByTicker[position.ticker.uppercased()] {
                updated.currentPrice = currentPrice
            }
            return updated
        }
        persistPortfolio()
    }

    private func enqueueLocalStateBootstrap() {
        guard let syncCoordinator else { return }
        let portfolio = positions
        let states = Array(signalUserStates.values)
        Task {
            await syncCoordinator.bootstrap(portfolio: portfolio, signalStates: states)
        }
    }

    private func enqueuePortfolioUpsert(_ position: PortfolioPosition) {
        guard let syncCoordinator else { return }
        Task { await syncCoordinator.enqueuePortfolioUpsert(position) }
    }

    private func enqueuePortfolioDelete(_ id: UUID) {
        guard let syncCoordinator else { return }
        Task { await syncCoordinator.enqueuePortfolioDelete(id: id) }
    }

    private func enqueueSignalState(_ state: SignalUserState) {
        guard let syncCoordinator else { return }
        Task { await syncCoordinator.enqueueSignalState(state) }
    }

    private func trackSignalAction(_ name: ClientTelemetryName, signalId: UUID) {
        let signal = signals.first { $0.id == signalId }
        enqueueTelemetry(ClientTelemetryEvent(
            name: name,
            signalId: signalId,
            ticker: signal?.ticker,
            context: .signalDetail
        ))
    }

    private func enqueueTelemetry(_ event: ClientTelemetryEvent) {
        guard let syncCoordinator else { return }
        Task { await syncCoordinator.enqueueTelemetry(event) }
    }
}
