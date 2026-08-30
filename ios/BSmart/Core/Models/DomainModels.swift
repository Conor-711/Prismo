import Foundation

enum BSmartLiveDataSource: String, Codable, CaseIterable, Hashable {
    case smartAccount
    case smartMoney
}

struct BSmartDataFreshness: Codable, Hashable {
    let checkedAt: Date
    let latestContentAt: Date?
    let itemCount: Int

    var hasNoNewQualifiedContent: Bool {
        guard let latestContentAt else { return itemCount == 0 }
        return checkedAt.timeIntervalSince(latestContentAt) > 15 * 60
    }
}

enum PortfolioEntryKind: String, Codable, CaseIterable {
    case position
    case watchlist

    var label: String {
        switch self {
        case .position: "Position".bSmartLocalized
        case .watchlist: "Watchlist".bSmartLocalized
        }
    }
}

struct PortfolioPosition: Identifiable, Codable, Hashable {
    let id: UUID
    var ticker: String
    var companyName: String
    var shares: Double
    var averageCost: Double
    var currentPrice: Double
    var entryKind: PortfolioEntryKind?
    var portfolioWeight: Double?

    init(
        id: UUID,
        ticker: String,
        companyName: String,
        shares: Double,
        averageCost: Double,
        currentPrice: Double,
        entryKind: PortfolioEntryKind? = nil,
        portfolioWeight: Double? = nil
    ) {
        self.id = id
        self.ticker = ticker
        self.companyName = companyName
        self.shares = shares
        self.averageCost = averageCost
        self.currentPrice = currentPrice
        self.entryKind = entryKind
        self.portfolioWeight = portfolioWeight
    }

    var resolvedKind: PortfolioEntryKind { entryKind ?? (shares > 0 ? .position : .watchlist) }
    var isPosition: Bool { resolvedKind == .position }
    var marketValue: Double { shares * currentPrice }
    var costBasis: Double { shares * averageCost }
    var unrealizedGain: Double { marketValue - costBasis }
    var unrealizedGainPercent: Double {
        guard costBasis != 0 else { return 0 }
        return unrealizedGain / costBasis
    }
}

struct PortfolioValuePoint: Identifiable, Codable, Hashable {
    var id: Date { timestamp }
    let timestamp: Date
    let value: Double
}

enum SignalFeedback: String, Codable, CaseIterable {
    case useful
    case notRelevant = "not_relevant"
    case tooLate = "too_late"
    case unclear

    var label: String {
        switch self {
        case .useful: "Useful".bSmartLocalized
        case .notRelevant: "Not relevant".bSmartLocalized
        case .tooLate: "Too late".bSmartLocalized
        case .unclear: "Unclear".bSmartLocalized
        }
    }

    var symbol: String {
        switch self {
        case .useful: "hand.thumbsup"
        case .notRelevant: "scope"
        case .tooLate: "clock"
        case .unclear: "questionmark.circle"
        }
    }
}

struct SignalUserState: Identifiable, Codable, Hashable {
    var id: UUID { signalId }
    let signalId: UUID
    var isRead: Bool
    var isSaved: Bool
    var isIgnored: Bool
    var feedback: SignalFeedback?
    var updatedAt: Date

    init(
        signalId: UUID,
        isRead: Bool = false,
        isSaved: Bool = false,
        isIgnored: Bool = false,
        feedback: SignalFeedback? = nil,
        updatedAt: Date = Date()
    ) {
        self.signalId = signalId
        self.isRead = isRead
        self.isSaved = isSaved
        self.isIgnored = isIgnored
        self.feedback = feedback
        self.updatedAt = updatedAt
    }
}

enum SignalPriority: String, Codable, CaseIterable {
    case critical
    case important
    case notable

    var label: String {
        switch self {
        case .critical: "Critical".bSmartLocalized
        case .important: "Important".bSmartLocalized
        case .notable: "Notable".bSmartLocalized
        }
    }
}

enum SignalDirection: String, Codable, CaseIterable {
    case bullish
    case neutral
    case bearish
    case mixed

    var label: String {
        switch self {
        case .bullish: "Bullish".bSmartLocalized
        case .neutral: "Neutral".bSmartLocalized
        case .bearish: "Bearish".bSmartLocalized
        case .mixed: "Mixed".bSmartLocalized
        }
    }
}

enum SmartAccountLifecycle: String, Codable, CaseIterable {
    case new
    case strengthened
    case weakened
    case reversed
    case closed
    case invalidated

    var label: String {
        switch self {
        case .new: "New view".bSmartLocalized
        case .strengthened: "Strengthened".bSmartLocalized
        case .weakened: "Weakened".bSmartLocalized
        case .reversed: "Reversed".bSmartLocalized
        case .closed: "Closed".bSmartLocalized
        case .invalidated: "Invalidated".bSmartLocalized
        }
    }
}

enum SmartMoneyAction: String, Codable, CaseIterable {
    case opened
    case increased
    case reduced
    case closed
    case flipped

    var label: String {
        switch self {
        case .opened: "Opened".bSmartLocalized
        case .increased: "Increased".bSmartLocalized
        case .reduced: "Reduced".bSmartLocalized
        case .closed: "Closed".bSmartLocalized
        case .flipped: "Flipped".bSmartLocalized
        }
    }
}

enum PortfolioSignalKind: String, Codable, CaseIterable {
    case smartAccountNewView = "smart_account_new_view"
    case smartAccountShift = "smart_account_shift"
    case smartAccountConsensus = "smart_account_consensus"
    case smartMoneyMovement = "smart_money_movement"
    case confirmation
    case divergence
    case accountLeads = "account_leads"
    case moneyLeads = "money_leads"

    var label: String {
        switch self {
        case .smartAccountNewView: "New Smart Account view".bSmartLocalized
        case .smartAccountShift: "View changed".bSmartLocalized
        case .smartAccountConsensus: "Account consensus".bSmartLocalized
        case .smartMoneyMovement: "Smart Money moved".bSmartLocalized
        case .confirmation: "Confirmed".bSmartLocalized
        case .divergence: "Divergence".bSmartLocalized
        case .accountLeads: "Accounts lead".bSmartLocalized
        case .moneyLeads: "Money leads".bSmartLocalized
        }
    }
}

enum SignalEvidenceSource: String, Codable, CaseIterable {
    case smartAccount = "smart_account"
    case smartMoney = "smart_money"

    var label: String {
        switch self {
        case .smartAccount: "Smart Account".bSmartLocalized
        case .smartMoney: "Smart Money".bSmartLocalized
        }
    }

    var symbol: String {
        switch self {
        case .smartAccount: "person.wave.2"
        case .smartMoney: "wallet.bifold"
        }
    }
}

enum SignalDataStatus: String, Codable, CaseIterable {
    case current
    case delayed

    var label: String {
        switch self {
        case .current: "Data current".bSmartLocalized
        case .delayed: "Data delayed".bSmartLocalized
        }
    }
}

struct SmartAccountUpdate: Identifiable, Codable, Hashable {
    let id: UUID
    let ticker: String
    let companyName: String
    let authorId: String
    let authorName: String
    let platform: String
    let score: Double
    let platformPercentile: Double
    let direction: SignalDirection
    let lifecycle: SmartAccountLifecycle
    let horizon: String
    let targetPrice: Double?
    let thesis: String
    let invalidation: String?
    let publishedAt: Date
    let evidenceURL: URL?
    var authorAvatarURL: URL? = nil
    var authorFollowersCount: Int? = nil
    var authorVerified: Bool? = nil
    var originalText: String? = nil
    var priceEvidence: SmartAccountPriceEvidence? = nil
    var sourcePostId: String? = nil
    var sourceURL: URL? = nil
    var ingestedAt: Date? = nil
    var processedAt: Date? = nil
    var translatedText: String? = nil
    var translatedTextZH: String? = nil
    var translatedTextEN: String? = nil
    var evidenceSpan: String? = nil
    var authorScoreAsOf: Date? = nil
    var callScoringVersion: String? = nil
    var evidenceRole: String? = nil
    var settlement: SmartAccountSettlementEvidence? = nil
    var representativeTickerContribution: Double? = nil
    var representativeCallCount: Int? = nil
    var representativeTickerRank: Int? = nil
    var activityTitle: String? = nil
    var activityTitleZH: String? = nil
    var activityTitleEN: String? = nil
}

struct PriceCandle: Identifiable, Codable, Hashable {
    var id: String { day }
    let day: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
}

struct SmartAccountPriceEvidence: Codable, Hashable {
    let ticker: String
    let viewDay: String
    let viewPrice: Double
    let latestDay: String
    let latestPrice: Double
    let responsePercent: Double?
    let source: String
    let candles: [PriceCandle]
    var opinionMarkers: [SmartAccountOpinionMarker]? = nil
}

struct SmartAccountOpinionMarker: Identifiable, Codable, Hashable {
    let id: UUID
    let publishedAt: Date
    let viewDay: String
    let viewPrice: Double
    let direction: SignalDirection
    let contribution: Double
    let horizon: String
    let thesis: String
    let evidenceURL: URL?
}

struct SmartAccountSettlementEvidence: Codable, Hashable {
    let status: String
    let horizon: String
    let entryDay: String?
    let exitDay: String?
    let entryPrice: Double?
    let exitPrice: Double?
    let tickerReturnPercent: Double?
    let marketBenchmarkReturnPercent: Double?
    let marketExcessReturnPercent: Double?
    let actualHit: Bool?
    let contribution: Double?
    let industryBenchmarkTicker: String?
    let industryBenchmarkReturnPercent: Double?
    let industryExcessReturnPercent: Double?
    let industryActualHit: Bool?
    let settlementVersion: String?
}

struct SmartMoneyMovement: Identifiable, Codable, Hashable {
    let id: UUID
    let ticker: String
    let companyName: String
    let accountId: String
    let accountLabel: String
    var accountDisplayName: String? = nil
    var avatarVariant: Int? = nil
    let accountScore: Double
    let market: String
    let action: SmartMoneyAction
    let direction: SignalDirection
    let notionalBefore: Double
    let notionalAfter: Double
    let notionalChange: Double
    let leverage: Double?
    let observedAt: Date
    let evidenceURL: URL?
    var price: Double? = nil
    var sizeBefore: Double? = nil
    var sizeAfter: Double? = nil
}

struct SmartMoneyRepresentativeEvidence: Identifiable, Codable, Hashable {
    let id: UUID
    let accountId: String
    let accountDisplayName: String
    let avatarVariant: Int?
    let ticker: String
    let market: String
    let representativeRank: Int
    let cumulativeEntryNotional: Double
    let entryCount: Int
    let assetNetPnl: Double
    let latestEntryAt: Date
    let priceEvidence: SmartMoneyPriceEvidence
}

struct SmartMoneyPriceEvidence: Codable, Hashable {
    let market: String
    let interval: String
    let source: String
    let candles: [SmartMoneyCandle]
    let entryMarkers: [SmartMoneyEntryMarker]
}

struct SmartMoneyCandle: Identifiable, Codable, Hashable {
    var id: Date { timestamp }
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

struct SmartMoneyEntryMarker: Identifiable, Codable, Hashable {
    let id: UUID
    let observedAt: Date
    let price: Double
    let priceBasis: String
    let direction: SignalDirection
    let action: SmartMoneyAction
    let entryNotional: Double
    let evidenceURL: URL?
}

struct PortfolioSignalEvidence: Identifiable, Codable, Hashable {
    let id: UUID
    let source: SignalEvidenceSource
    let referenceId: UUID
    let actorName: String
    var avatarVariant: Int? = nil
    let title: String
    let detail: String
    let metric: String?
    let observedAt: Date
    let sourceURL: URL?
}

struct PortfolioSignal: Identifiable, Codable, Hashable {
    let id: UUID
    let ticker: String
    let companyName: String
    let title: String
    let summary: String
    let occurredAt: Date
    let dataAsOf: Date
    let priority: SignalPriority
    let kind: PortfolioSignalKind
    let direction: SignalDirection
    let smartMoneyCoverage: SmartMoneyCoverage
    let conclusion: String
    let positionImpact: String
    let nextStep: String
    let evidence: [PortfolioSignalEvidence]
    var dataStatus: SignalDataStatus? = nil
    var limitations: [String]? = nil

    var resolvedDataStatus: SignalDataStatus { dataStatus ?? .current }
    var resolvedLimitations: [String] { limitations ?? [] }

    func evidence(for source: SignalEvidenceSource) -> [PortfolioSignalEvidence] {
        evidence.filter { $0.source == source }
    }
}

struct DailyDigestSnapshot: Identifiable, Codable, Hashable {
    let id: UUID
    let generatedAt: Date
    let dataAsOf: Date
    let periodStart: Date
    let periodEnd: Date
    let title: String
    let summary: String
    let signals: [PortfolioSignal]
}

struct MrCollieQuery: Codable, Hashable {
    let question: String
    let locale: String
    let conversation: [MrCollieConversationTurn]
}

struct MrCollieConversationTurn: Codable, Hashable {
    enum Role: String, Codable, Hashable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct MrCollieEvidence: Identifiable, Codable, Hashable {
    let id: String
    let source: String
    let sourceType: SignalEvidenceSource
    let title: String
    let detail: String
    let metric: String?
    let observedAt: Date?
}

struct MrCollieResponse: Codable, Hashable {
    let question: String
    let title: String
    let summary: String
    let context: String?
    let nextStep: String
    let ticker: String?
    let signalId: UUID?
    let evidence: [MrCollieEvidence]
    let generatedAt: Date
    let dataAsOf: Date
    let contextVersion: String
    let model: String
}

struct SmartAccountSnapshot: Codable, Hashable {
    let direction: SignalDirection
    let headline: String
    let detail: String
    let qualifiedAuthorCount: Int
    let latestUpdateAt: Date?
}

struct SmartMoneySnapshot: Codable, Hashable {
    let coverage: SmartMoneyCoverage
    let direction: SignalDirection
    let headline: String
    let detail: String
    let qualifiedAccountCount: Int
    let latestMovementAt: Date?
}

struct TickerIntelligence: Identifiable, Codable, Hashable {
    var id: String { ticker }
    let ticker: String
    let companyName: String
    let currentPrice: Double
    let dayChangePercent: Double
    let dataAsOf: Date
    let relationship: PortfolioSignalKind
    let direction: SignalDirection
    let conclusion: String
    let latestSignalId: UUID?
    let smartAccount: SmartAccountSnapshot
    let smartMoney: SmartMoneySnapshot
}

// Legacy v1 event types remain decodable while clients migrate to PortfolioSignal.
enum EventSeverity: String, Codable, CaseIterable {
    case critical
    case important
    case notable

    var label: String {
        switch self {
        case .critical: "Critical".bSmartLocalized
        case .important: "Important".bSmartLocalized
        case .notable: "Notable".bSmartLocalized
        }
    }
}

enum EventKind: String, Codable {
    case confirmation
    case divergence
    case smartAccountView = "smart_account_view"
    case smartMoneyMovement = "smart_money_movement"

    var label: String {
        switch self {
        case .confirmation: "Confirmed".bSmartLocalized
        case .divergence: "Divergence".bSmartLocalized
        case .smartAccountView: "Smart Account".bSmartLocalized
        case .smartMoneyMovement: "Smart Money".bSmartLocalized
        }
    }
}

enum SmartMoneyCoverage: String, Codable {
    case available
    case unavailable

    var label: String {
        switch self {
        case .available: "Capital data available".bSmartLocalized
        case .unavailable: "No capital verification".bSmartLocalized
        }
    }

    var detail: String {
        switch self {
        case .available:
            "Public tokenized-equity positioning is available for this ticker.".bSmartLocalized
        case .unavailable:
            "Smart Account evidence is available, but public capital data does not meet the minimum coverage threshold.".bSmartLocalized
        }
    }
}

enum EvidenceSource: String, Codable, CaseIterable {
    case smartAccount = "smart_account"
    case smartMoney = "smart_money"
    case market
    case fundamental

    var label: String {
        switch self {
        case .smartAccount: "Smart Account".bSmartLocalized
        case .smartMoney: "Smart Money".bSmartLocalized
        case .market: "Market".bSmartLocalized
        case .fundamental: "Fundamental".bSmartLocalized
        }
    }

    var symbol: String {
        switch self {
        case .smartAccount: "person.wave.2"
        case .smartMoney: "wallet.bifold"
        case .market: "chart.xyaxis.line"
        case .fundamental: "newspaper"
        }
    }
}

struct EventEvidence: Identifiable, Codable, Hashable {
    let id: UUID
    let source: EvidenceSource
    let title: String
    let detail: String
    let metric: String?
    let sourceURL: URL?
}

struct InvestmentEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let ticker: String
    let companyName: String
    let title: String
    let summary: String
    let occurredAt: Date
    let severity: EventSeverity
    let kind: EventKind
    let smartMoneyCoverage: SmartMoneyCoverage
    let conclusion: String
    let positionImpact: String
    let nextStep: String
    let evidence: [EventEvidence]
}

struct CuratedOpinion: Identifiable, Codable, Hashable {
    let id: UUID
    let authorName: String
    let platform: String
    let score: Double
    let stance: String
    let summary: String
    let publishedAt: Date
}

struct SmartAccountProfile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let handle: String
    let platform: String
    let score: Double
    let scoreChange: Double
    let specialty: String
    let horizon: String
    let recentTicker: String?
    var rank: Int? = nil
    var platformRank: Int? = nil
    var platformPercentile: Double? = nil
    var confidence: String? = nil
    var effectiveSamples: Double? = nil
    var settledCalls: Int? = nil
    var activeDays: Int? = nil
    var coveredTickers: Int? = nil
    var topTickers: [String]? = nil
    var style: String? = nil
    var marketSelectionScore: Double? = nil
    var industrySelectionScore: Double? = nil
    var rationale: String? = nil
    var avatarURL: URL? = nil
    var profileURL: URL? = nil
    var followersCount: Int? = nil
    var postsCount: Int? = nil
    var verified: Bool? = nil
    var description: String? = nil

    var resolvedRank: Int { rank ?? platformRank ?? 0 }
    var resolvedPlatformRank: Int { platformRank ?? rank ?? 0 }
    var resolvedPlatformPercentile: Double { platformPercentile ?? 0.5 }
    var resolvedConfidence: String { confidence ?? "observing" }
    var resolvedEffectiveSamples: Double { effectiveSamples ?? 0 }
    var resolvedSettledCalls: Int { settledCalls ?? 0 }
    var resolvedActiveDays: Int { activeDays ?? 0 }
    var resolvedCoveredTickers: Int { coveredTickers ?? 0 }
    var resolvedTopTickers: [String] { topTickers ?? recentTicker.map { [$0] } ?? [] }
    var resolvedStyle: String { style ?? "Mixed" }
}

struct SmartMoneySignal: Identifiable, Codable, Hashable {
    let id: String
    let walletLabel: String
    var displayName: String? = nil
    var avatarVariant: Int? = nil
    let score: Double
    let ticker: String
    let direction: String
    let notionalValue: Double
    let changedAt: Date
    var scoreSource: String? = nil
    var source: String? = nil
    var sourceUpdatedAt: Date? = nil
    var sourceURL: URL? = nil
    var address: String? = nil
    var rank: Int? = nil
    var tier: String? = nil
    var style: String? = nil
    var sizeCohort: String? = nil
    var pnlCohort: String? = nil
    var accountValue: Double? = nil
    var totalNotional: Double? = nil
    var unrealizedPnl: Double? = nil
    var currentLeverage: Double? = nil
    var marginUtilization: Double? = nil
    var netPnl: Double? = nil
    var winRate: Double? = nil
    var sharpe: Double? = nil
    var maxDrawdownPercent: Double? = nil
    var profitFactor: Double? = nil
    var fillCount: Int? = nil
    var activeDays: Int? = nil
    var longBias: Double? = nil
    var tradeDuration: SmartMoneyTradeDuration? = nil
    var periodMetrics: [String: SmartMoneyPeriodMetric]? = nil
    var currentPositions: [SmartMoneyPosition]? = nil
    var assetPerformance: [SmartMoneyAssetPerformance]? = nil
    var recentTrades: [SmartMoneyTrade]? = nil
    var capitalActivity: [SmartMoneyCapitalActivity]? = nil
    var components: SmartMoneyScoreComponents? = nil

    var resolvedAddress: String { address ?? id }
    var resolvedTier: String { tier ?? "Qualified" }
    var resolvedStyle: String { style ?? "Unclassified" }
    var resolvedPositions: [SmartMoneyPosition] { currentPositions ?? [] }
    var resolvedPeriodMetrics: [String: SmartMoneyPeriodMetric] { periodMetrics ?? [:] }
    var resolvedSource: String { source ?? "unverified" }
    var resolvedScoreSource: String { scoreSource ?? "unverified" }
}

struct SmartMoneyMetricPoint: Codable, Hashable {
    let timestamp: Double
    let value: Double
}

struct SmartMoneyTradeDuration: Codable, Hashable {
    let completedTrades: Int
    let averageHoldHours: Double
    let medianHoldHours: Double
    let style: String
}

struct SmartMoneyPeriodMetric: Codable, Hashable {
    let equity: Double
    let pnl: Double
    let volume: Double
    let sharpe: Double
    let maxDrawdown: Double
    let maxDrawdownPercent: Double
    let accountValueHistory: [SmartMoneyMetricPoint]
    let pnlHistory: [SmartMoneyMetricPoint]
}

struct SmartMoneyPosition: Identifiable, Codable, Hashable {
    var id: String { coin }
    let coin: String
    let symbol: String
    let category: String
    let dex: String
    let direction: String
    let size: Double
    let notional: Double
    let entryPrice: Double?
    let markPrice: Double?
    let unrealizedPnl: Double
    let returnOnEquity: Double
    let liquidationPrice: Double?
    let liquidationDistance: Double?
    let leverage: Double
    let marginUsed: Double
    let fundingSinceOpen: Double
}

struct SmartMoneyAssetPerformance: Identifiable, Codable, Hashable {
    var id: String { symbol }
    let symbol: String
    let netPnl: Double
    let fees: Double
    let volume: Double
    let trades: Int
    let winRate: Double
}

struct SmartMoneyTrade: Identifiable, Codable, Hashable {
    let id: String
    let symbol: String
    let coin: String
    let direction: String
    let side: String
    let price: Double
    let size: Double
    let notional: Double
    let closedPnl: Double
    let time: Date
    let hash: String
}

struct SmartMoneyCapitalActivity: Identifiable, Codable, Hashable {
    let id: String
    let type: String
    let direction: String
    let amount: Double
    let token: String
    let time: Date
    let hash: String
}

struct SmartMoneyScoreComponents: Codable, Hashable {
    let performance: Double
    let consistency: Double
    let payoff: Double
    let risk: Double
    let execution: Double
}

// Legacy research type retained for /v1/research compatibility.
struct TickerResearch: Identifiable, Codable, Hashable {
    var id: String { ticker }
    let ticker: String
    let companyName: String
    let currentPrice: Double
    let dayChangePercent: Double
    let conclusion: String
    let smartAccountShift: String
    let smartMoneyCoverage: SmartMoneyCoverage
    let smartMoneyShift: String
    let opinions: [CuratedOpinion]
}
