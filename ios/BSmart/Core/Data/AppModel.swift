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
    @Published private(set) var loadingSmartAccountEvidenceIDs: Set<String> = []
    @Published private(set) var smartMoney: [SmartMoneySignal] = []
    @Published private(set) var dailyDigestSnapshot: DailyDigestSnapshot?
    @Published private(set) var signalUserStates: [UUID: SignalUserState] = [:]
    @Published private(set) var followedSmartAccountIDs: Set<String> = []
    @Published private(set) var followedSmartMoneyIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingLiveIntelligence = false
    @Published private(set) var hasFinishedInitialLoad = false
    @Published private(set) var hasCompletedPortfolioSetup = false
    @Published private(set) var lastDataRefreshAt: Date?
    @Published private(set) var smartAccountFreshness: BSmartDataFreshness?
    @Published private(set) var smartMoneyFreshness: BSmartDataFreshness?
    @Published private(set) var errorMessage: String?
    let isUsingDemoData: Bool

    private let client: BSmartAPIClient
    private let syncCoordinator: BSmartSyncCoordinator?
    private let defaults: UserDefaults
    private let portfolioBootstrapStrategy: PortfolioBootstrapStrategy
    private let savedPortfolioKey = "bsmart.portfolio.v1"
    private let completedPortfolioSetupKey = "bsmart.portfolio-setup-complete.v1"
    private let savedSignalStatesKey = "bsmart.signal-user-states.v1"
    private let savedClientCacheKey = "bsmart.client-cache.v1"
    private let followedSmartAccountsKey = "bsmart.followed-smart-accounts.v1"
    private let followedSmartMoneyKey = "bsmart.followed-smart-money.v1"
    private var hasLoaded = false

    init(
        client: BSmartAPIClient = BundleBSmartAPIClient(),
        defaults: UserDefaults = .standard,
        portfolioBootstrapStrategy: PortfolioBootstrapStrategy = .remoteFallback,
        syncCoordinator: BSmartSyncCoordinator? = nil,
        isUsingDemoData: Bool = false
    ) {
        self.client = client
        self.defaults = defaults
        self.portfolioBootstrapStrategy = portfolioBootstrapStrategy
        self.syncCoordinator = syncCoordinator
        self.isUsingDemoData = isUsingDemoData
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

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        errorMessage = nil

        let localPortfolio = restoredPortfolio()
        positions = localPortfolio ?? []
        hasCompletedPortfolioSetup = defaults.bool(forKey: completedPortfolioSetupKey)
            || !positions.isEmpty
        restoreSignalUserStates()
        restoreFollowedIntelligence()
        if restoreClientCache() {
            refreshCurrentPrices()
            hasFinishedInitialLoad = true
        }

        do {
            async let loadedPortfolio = client.fetchPortfolio()
            async let loadedSignals = client.fetchSignals()
            async let loadedAccountUpdates = client.fetchSmartAccountUpdates()
            async let loadedMoneyMovements = client.fetchSmartMoneyMovements()
            async let loadedIntelligence = client.fetchTickerIntelligence()
            async let loadedAccounts = client.fetchSmartAccounts()
            async let loadedMoney = client.fetchSmartMoney()
            async let loadedDigest = fetchDailyDigestIfAvailable()

            let remotePortfolio = try await loadedPortfolio
            positions = localPortfolio
                ?? (portfolioBootstrapStrategy == .remoteFallback ? remotePortfolio : [])
            hasCompletedPortfolioSetup = defaults.bool(forKey: completedPortfolioSetupKey)
                || !positions.isEmpty
            signals = (try await loadedSignals).sorted { $0.occurredAt > $1.occurredAt }
            smartAccountUpdates = (try await loadedAccountUpdates).sorted { $0.publishedAt > $1.publishedAt }
            smartMoneyMovements = (try await loadedMoneyMovements).sorted { $0.observedAt > $1.observedAt }
            intelligence = (try await loadedIntelligence).sorted { $0.ticker < $1.ticker }
            refreshCurrentPrices()
            smartAccounts = (try await loadedAccounts).sorted { $0.score > $1.score }
            smartMoney = (try await loadedMoney).sorted { $0.changedAt > $1.changedAt }
            dailyDigestSnapshot = await loadedDigest
            refreshSourceFreshness()
            lastDataRefreshAt = resolvedLatestDataAsOf()
            persistClientCache()
            enqueueLocalStateBootstrap()
        } catch {
            hasLoaded = false
            errorMessage = error.localizedDescription
        }

        isLoading = false
        hasFinishedInitialLoad = true
    }

    func retry() async {
        hasLoaded = false
        if signals.isEmpty { hasFinishedInitialLoad = false }
        await load()
    }

    func refreshLiveIntelligence() async {
        guard hasFinishedInitialLoad, !isRefreshingLiveIntelligence else { return }
        isRefreshingLiveIntelligence = true
        defer { isRefreshingLiveIntelligence = false }

        do {
            async let loadedSignals = client.fetchSignals()
            async let loadedAccountUpdates = client.fetchSmartAccountUpdates()
            async let loadedMoneyMovements = client.fetchSmartMoneyMovements()
            async let loadedIntelligence = client.fetchTickerIntelligence()
            async let loadedMoney = client.fetchSmartMoney()

            let refreshed = try await (
                loadedSignals,
                loadedAccountUpdates,
                loadedMoneyMovements,
                loadedIntelligence,
                loadedMoney
            )
            signals = refreshed.0.sorted { $0.occurredAt > $1.occurredAt }
            smartAccountUpdates = refreshed.1.sorted { $0.publishedAt > $1.publishedAt }
            smartMoneyMovements = refreshed.2.sorted { $0.observedAt > $1.observedAt }
            intelligence = refreshed.3.sorted { $0.ticker < $1.ticker }
            smartMoney = refreshed.4.sorted { $0.changedAt > $1.changedAt }
            refreshSourceFreshness()
            refreshCurrentPrices()
            lastDataRefreshAt = resolvedLatestDataAsOf()
            errorMessage = nil
            persistClientCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func completePortfolioSetup() -> Bool {
        guard !positions.isEmpty else { return false }
        hasCompletedPortfolioSetup = true
        defaults.set(true, forKey: completedPortfolioSetupKey)
        return true
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
        persistPortfolio()
        enqueuePortfolioUpsert(position)
        return true
    }

    func deletePositions(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            let removed = positions.remove(at: index)
            enqueuePortfolioDelete(removed.id)
        }
        persistPortfolio()
    }

    func deletePosition(id: UUID) {
        positions.removeAll { $0.id == id }
        persistPortfolio()
        enqueuePortfolioDelete(id)
    }

    func resetLocalAppData() async {
        positions = []
        signalUserStates = [:]
        followedSmartAccountIDs = []
        followedSmartMoneyIDs = []
        hasCompletedPortfolioSetup = false

        [
            savedPortfolioKey,
            completedPortfolioSetupKey,
            savedSignalStatesKey,
            savedClientCacheKey,
            followedSmartAccountsKey,
            followedSmartMoneyKey
        ].forEach(defaults.removeObject(forKey:))

        await syncCoordinator?.clearPendingOperations()
    }

    func signalUserState(for signalId: UUID) -> SignalUserState {
        signalUserStates[signalId] ?? SignalUserState(signalId: signalId)
    }

    func markSignalRead(_ signalId: UUID, isRead: Bool = true) {
        updateSignalUserState(signalId) { $0.isRead = isRead }
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

    func accountEvidence(for account: SmartAccountProfile) -> [SmartAccountUpdate] {
        smartAccountEvidenceByAuthor[account.id] ?? accountUpdates(for: account)
    }

    func isLoadingAccountEvidence(_ account: SmartAccountProfile) -> Bool {
        loadingSmartAccountEvidenceIDs.contains(account.id)
    }

    func loadSmartAccountEvidence(for account: SmartAccountProfile) async {
        guard smartAccountEvidenceByAuthor[account.id] == nil,
              !loadingSmartAccountEvidenceIDs.contains(account.id)
        else { return }

        loadingSmartAccountEvidenceIDs.insert(account.id)
        defer { loadingSmartAccountEvidenceIDs.remove(account.id) }
        do {
            let evidence = try await client.fetchSmartAccountEvidence(accountID: account.id)
            smartAccountEvidenceByAuthor[account.id] = evidence.sorted { $0.publishedAt > $1.publishedAt }
        } catch {
            smartAccountEvidenceByAuthor[account.id] = accountUpdates(for: account)
            errorMessage = error.localizedDescription
        }
    }

    func moneyMovements(for signal: SmartMoneySignal) -> [SmartMoneyMovement] {
        smartMoneyMovements.filter { $0.accountId == signal.id }
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
    }

    private func restoredPortfolio() -> [PortfolioPosition]? {
        guard let data = defaults.data(forKey: savedPortfolioKey) else { return nil }
        return try? JSONDecoder().decode([PortfolioPosition].self, from: data)
    }

    private func persistSignalUserStates() {
        let states = signalUserStates.values.sorted { $0.updatedAt < $1.updatedAt }
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: savedSignalStatesKey)
    }

    private func persistFollowedIntelligence() {
        defaults.set(followedSmartAccountIDs.sorted(), forKey: followedSmartAccountsKey)
        defaults.set(followedSmartMoneyIDs.sorted(), forKey: followedSmartMoneyKey)
    }

    private func restoreFollowedIntelligence() {
        followedSmartAccountIDs = Set(defaults.stringArray(forKey: followedSmartAccountsKey) ?? [])
        followedSmartMoneyIDs = Set(defaults.stringArray(forKey: followedSmartMoneyKey) ?? [])
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
            smartMoneyFreshness: smartMoneyFreshness
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
        lastDataRefreshAt = snapshot.dataAsOf ?? snapshot.savedAt
        return true
    }

    private func fetchDailyDigestIfAvailable() async -> DailyDigestSnapshot? {
        do {
            return try await client.fetchDailyDigest()
        } catch {
            return nil
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
