#if DEBUG
import Foundation

enum DebugDataScenario: String {
    case loaded
    case marketHistory = "market-history"
    case firstUse = "first-use"
    case weightOnly = "weight-only"
    case noSignals = "no-signals"
    case loading
    case error

    static var launched: DebugDataScenario? {
        let prefix = "--ui-scenario="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return DebugDataScenario(rawValue: String(argument.dropFirst(prefix.count)))
    }
}

struct DebugBSmartAPIClient: BSmartAPIClient {
    let scenario: DebugDataScenario
    private let bundleClient: BundleBSmartAPIClient
    private let bundle: Bundle

    init(scenario: DebugDataScenario, bundle: Bundle = .main) {
        self.scenario = scenario
        self.bundle = bundle
        self.bundleClient = BundleBSmartAPIClient(bundle: bundle)
    }

    func fetchPortfolio() async throws -> [PortfolioPosition] {
        if scenario == .marketHistory {
            return ["NVDA", "SPCX", "SNDK"].enumerated().map { index, ticker in
                PortfolioPosition(id: UUID(), ticker: ticker, companyName: ticker,
                                  shares: Double(index + 1), averageCost: 1, currentPrice: 1,
                                  entryKind: .position)
            }
        }
        if scenario == .firstUse { return [] }
        if scenario == .weightOnly {
            return [PortfolioPosition(
                id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
                ticker: "NVDA",
                companyName: "NVIDIA",
                shares: 0,
                averageCost: 0,
                currentPrice: 0,
                entryKind: .position,
                portfolioWeight: 0.35
            )]
        }
        return try await value { try await bundleClient.fetchPortfolio() }
    }

    func fetchOpinionTraders(opinionID: UUID, offset: Int) async throws -> OpinionTradersPage {
        guard ProcessInfo.processInfo.arguments.contains("--ui-opinion-traders-fixture"),
              let url = bundle.url(forResource: "opinion-traders", withExtension: "json") else {
            throw BSmartAPIError.tradeStatisticsUnavailable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(OpinionTradersPage.self, from: Data(contentsOf: url))
        let rows = Array(fixture.traders.dropFirst(offset).prefix(1))
        return OpinionTradersPage(totalTraders: fixture.totalTraders, publicTraders: fixture.publicTraders,
                                  traders: rows, nextOffset: offset + rows.count < fixture.publicTraders ? offset + rows.count : nil,
                                  longTraders: fixture.longTraders, shortTraders: fixture.shortTraders,
                                  totalNotionalUSD: fixture.totalNotionalUSD)
    }

    func fetchTradeFeed(offset: Int, profileID: UUID?) async throws -> TradeFeedPage {
        if ProcessInfo.processInfo.arguments.contains("--ui-trade-feed-empty") {
            return .init(items: [], nextOffset: nil)
        }
        let fixture = try feedFixture()
        let items = fixture.items.filter { profileID == nil || $0.trader.id == profileID }
        let page = Array(items.dropFirst(offset).prefix(2))
        return .init(items: page, nextOffset: offset + page.count < items.count ? offset + page.count : nil)
    }

    func fetchPublicTrader(profileID: UUID) async throws -> FeedPublicProfile {
        guard let profile = try feedFixture().items.first(where: { $0.trader.id == profileID })?.trader else {
            throw BSmartAPIError.httpStatus(404)
        }
        return profile
    }

    private func feedFixture() throws -> TradeFeedPage {
        guard ProcessInfo.processInfo.arguments.contains("--ui-trade-feed-fixture"),
              let url = bundle.url(forResource: "trade-feed", withExtension: "json") else {
            throw BSmartAPIError.tradeStatisticsUnavailable
        }
        return try BSmartJSONCoding.makeDecoder().decode(TradeFeedPage.self, from: Data(contentsOf: url))
    }

    func fetchPortfolioHistory() async throws -> [PortfolioValuePoint] {
        if scenario == .firstUse || scenario == .weightOnly { return [] }
        return try await value { try await bundleClient.fetchPortfolioHistory() }
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        if scenario == .noSignals || scenario == .marketHistory { return [] }
        return try await value { try await bundleClient.fetchSignals() }
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] {
        if scenario == .noSignals || scenario == .marketHistory { return [] }
        return try await value { try await bundleClient.fetchSmartAccountUpdates() }
    }

    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] {
        if scenario == .noSignals || scenario == .marketHistory { return [] }
        return try await value { try await bundleClient.fetchSmartMoneyMovements() }
    }

    func fetchTickerIntelligence() async throws -> [TickerIntelligence] {
        try await value { try await bundleClient.fetchTickerIntelligence() }
    }

    func fetchSmartAccounts() async throws -> [SmartAccountProfile] {
        try await value { try await bundleClient.fetchSmartAccounts() }
    }

    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] {
        try await value { try await bundleClient.fetchSmartAccountEvidence(accountID: accountID) }
    }

    func fetchSmartMoney() async throws -> [SmartMoneySignal] {
        try await value { try await bundleClient.fetchSmartMoney() }
    }

    func fetchSmartMoneyEvidence(accountID: String) async throws -> [SmartMoneyRepresentativeEvidence] {
        if ProcessInfo.processInfo.arguments.contains("--ui-evidence-chart-fixture") {
            return DebugChartEvidence.money(accountID: accountID)
        }
        return try await value { try await bundleClient.fetchSmartMoneyEvidence(accountID: accountID) }
    }

    private func value<T>(_ loader: () async throws -> T) async throws -> T {
        switch scenario {
        case .loading:
            try await Task.sleep(for: .seconds(30))
        case .error:
            throw BSmartAPIError.invalidResponse
        case .loaded, .marketHistory, .firstUse, .weightOnly, .noSignals:
            break
        }
        return try await loader()
    }
}
#endif
