import Foundation

/// A presentation of the published platform ranks, never a new score or author pool.
struct TodayInvestorDiscovery {
    struct Investor: Identifiable, Hashable {
        let account: SmartAccountProfile
        var id: String { TodayInvestorDiscovery.identity(account.id, platform: account.platform) }
        var sector: String { account.specialty.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    let investors: [Investor]

    init(accounts: [SmartAccountProfile]) {
        var seen = Set<String>()
        investors = accounts.filter {
            guard let percentile = $0.platformPercentile,
                  percentile.isFinite, (0...0.25).contains(percentile) else { return false }
            return $0.resolvedPlatformRank > 0 && $0.score.isFinite
        }.map { Investor(account: $0) }.sorted {
            if $0.account.resolvedPlatformPercentile != $1.account.resolvedPlatformPercentile {
                return $0.account.resolvedPlatformPercentile < $1.account.resolvedPlatformPercentile
            }
            if $0.account.resolvedPlatformRank != $1.account.resolvedPlatformRank {
                return $0.account.resolvedPlatformRank < $1.account.resolvedPlatformRank
            }
            return $0.id < $1.id
        }.filter { seen.insert($0.id).inserted }

    }

    var sectors: [String] {
        Set(investors.map(\.sector).filter { !$0.isEmpty }).sorted()
    }

    func candidates(sector: String?, query: String = "",
                    localize: (String) -> String = { $0 }) -> [Investor] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return investors.filter { investor in
            guard sector == nil || investor.sector == sector else { return false }
            let account = investor.account
            return query.isEmpty || [account.name, account.handle, account.specialty, account.resolvedStyle,
                                    localize(account.specialty), localize(account.resolvedStyle), localize(account.horizon)]
                .contains { $0.localizedCaseInsensitiveContains(query) }
                || account.resolvedTopTickers.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    static func selected(_ id: String?, in candidates: [Investor]) -> Investor? {
        candidates.first { $0.id == id } ?? candidates.first
    }

    static func identity(_ id: String, platform: String) -> String {
        let platform = platform.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonical: String
        switch platform {
        case "twitter", "twitter.com", "x.com": canonical = "x"
        case "youtu.be", "youtube.com": canonical = "youtube"
        case "雪球": canonical = "xueqiu"
        default: canonical = platform
        }
        return "\(canonical):\(id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

/// Snapshot the current sector/search cohort so browsing cannot drift on refresh.
struct TodayInvestorDiscoverySession: Identifiable {
    let id = UUID()
    let investors: [TodayInvestorDiscovery.Investor]
    private(set) var index: Int

    init(investors: [TodayInvestorDiscovery.Investor], selectedID: String) {
        self.investors = investors
        index = investors.firstIndex { $0.id == selectedID } ?? 0
    }

    var current: TodayInvestorDiscovery.Investor? {
        investors.indices.contains(index) ? investors[index] : nil
    }
    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index + 1 < investors.count }

    mutating func move(by offset: Int) {
        guard investors.indices.contains(index + offset) else { return }
        index += offset
    }
}
