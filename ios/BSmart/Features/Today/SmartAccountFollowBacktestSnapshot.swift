import Foundation

enum SmartAccountFollowBacktestSnapshot {
    static func stats(for profile: SmartAccountProfile) -> SmartAccountFollowBacktest? {
        if let current = profile.followBacktest, isUsable(current) { return current }
        return records[key(source: profile.platform, id: profile.id)]
    }

    private static let records: [String: SmartAccountFollowBacktest] = {
        guard let url = Bundle.main.url(forResource: "smart-account-backtest-full-history", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let rows = try? PropertyListDecoder().decode([SmartAccountFollowBacktest].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: rows.filter(isUsable).map {
            (key(source: $0.source, id: $0.investorID), $0)
        })
    }()

    private static func isUsable(_ stats: SmartAccountFollowBacktest) -> Bool {
        stats.tradeCount > 0 && stats.tradeHitRate.isFinite && (0...1).contains(stats.tradeHitRate)
            && stats.totalReturn.isFinite && !stats.endDay.isEmpty
    }

    private static func key(source: String, id: String) -> String {
        let platform = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalized = platform == "twitter" || platform == "x.com" ? "x" : platform
        return "\(normalized):\(id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}
