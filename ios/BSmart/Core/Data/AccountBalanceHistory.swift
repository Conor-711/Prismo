import Foundation

enum AccountBalancePeriod: String, CaseIterable, Identifiable {
    case day = "1D", week = "1W", month = "1M", all = "All"
    var id: Self { self }

    var portfolioKey: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .all: "allTime"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .all: nil
        }
    }

    func localPoints(in history: [PortfolioValuePoint], now: Date) -> [PortfolioValuePoint] {
        guard let duration else { return history }
        return history.filter { $0.timestamp >= now.addingTimeInterval(-duration) }
    }
}

enum AccountBalanceHistory {
    static func remote(wallet: DeviceWalletSummary, reader: HyperCoreBalanceReading = HyperCoreBalanceClient(),
                       now: Date = Date()) async throws -> [AccountBalancePeriod: [PortfolioValuePoint]] {
        guard TradingWalletChallenge.validAddress(wallet.address) else { throw HyperCoreBalanceError.invalidResponse }
        return try parsePortfolio(await reader.read(.portfolio, owner: wallet.address), now: now)
    }

    static func parsePortfolio(_ response: FundingRPCValue, now: Date) throws -> [AccountBalancePeriod: [PortfolioValuePoint]] {
        guard case .array(let periods) = response, periods.count <= 32 else {
            throw HyperCoreBalanceError.invalidResponse
        }
        var result: [AccountBalancePeriod: [PortfolioValuePoint]] = [:]
        for period in periods {
            guard case .array(let pair) = period, pair.count == 2,
                  case .string(let name) = pair[0],
                  let selection = AccountBalancePeriod.allCases.first(where: { $0.portfolioKey == name }),
                  case .object(let details) = pair[1],
                  case .array(let rows) = details["accountValueHistory"], rows.count <= 5_000 else { continue }
            let points = try rows.map { row -> PortfolioValuePoint in
                guard case .array(let values) = row, values.count == 2,
                      case .integer(let milliseconds) = values[0], milliseconds > 0,
                      case .string(let amount) = values[1],
                      let balance = Double(amount), balance.isFinite, balance >= 0 else {
                    throw HyperCoreBalanceError.invalidResponse
                }
                return .init(timestamp: Date(timeIntervalSince1970: Double(milliseconds) / 1_000), value: balance)
            }
            let sorted = points.filter { $0.timestamp <= now }
                .sorted { $0.timestamp < $1.timestamp }
            if let duration = selection.duration {
                let cutoff = now.addingTimeInterval(-duration - 86_400)
                result[selection] = sorted.filter { $0.timestamp >= cutoff }
            } else {
                result[selection] = sorted
            }
        }
        return result
    }

    private static func key(for wallet: DeviceWalletSummary) -> String {
        "bsmart.account-balance.\(wallet.accountID.uuidString).\(wallet.address.lowercased())"
    }

    static func load(wallet: DeviceWalletSummary, now: Date = Date(), defaults: UserDefaults = .standard) -> [PortfolioValuePoint] {
        guard let data = defaults.data(forKey: key(for: wallet)),
              let saved = try? JSONDecoder().decode([PortfolioValuePoint].self, from: data) else { return [] }
        return Array(PortfolioValuationHistory.normalized(saved, now: now)
            .filter { $0.timestamp >= now.addingTimeInterval(-30 * 86_400) }.suffix(5_000))
    }

    @discardableResult
    static func record(_ snapshot: HyperCoreBalanceSnapshot, wallet: DeviceWalletSummary,
                       defaults: UserDefaults = .standard) -> [PortfolioValuePoint] {
        guard snapshot.accountID == wallet.accountID, snapshot.owner == wallet.address,
              let value = snapshot.accountBalanceValue, value >= 0 else {
            return load(wallet: wallet, now: snapshot.checkedAt, defaults: defaults)
        }
        let recent = load(wallet: wallet, now: snapshot.checkedAt, defaults: defaults)
        let updated = Array(PortfolioValuationHistory.recording(value, at: snapshot.checkedAt, in: recent).suffix(5_000))
        if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: key(for: wallet)) }
        return updated
    }
}
