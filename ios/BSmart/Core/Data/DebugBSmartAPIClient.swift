#if DEBUG
import Foundation

enum DebugDataScenario: String {
    case loaded
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

    init(scenario: DebugDataScenario, bundle: Bundle = .main) {
        self.scenario = scenario
        self.bundleClient = BundleBSmartAPIClient(bundle: bundle)
    }

    func fetchPortfolio() async throws -> [PortfolioPosition] {
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

    func fetchSignals() async throws -> [PortfolioSignal] {
        if scenario == .noSignals { return [] }
        return try await value { try await bundleClient.fetchSignals() }
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] {
        try await value { try await bundleClient.fetchSmartAccountUpdates() }
    }

    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] {
        try await value { try await bundleClient.fetchSmartMoneyMovements() }
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

    private func value<T>(_ loader: () async throws -> T) async throws -> T {
        switch scenario {
        case .loading:
            try await Task.sleep(for: .seconds(30))
        case .error:
            throw BSmartAPIError.invalidResponse
        case .loaded, .firstUse, .weightOnly, .noSignals:
            break
        }
        return try await loader()
    }
}
#endif
