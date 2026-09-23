import Foundation

/// A presentation grouping, not a new investor pool or a cross-source score.
struct TodayInvestorActivity: Identifiable, Hashable {
    let id: String
    let activities: [TodayActivity]

    var latest: TodayActivity { activities[0] }
    var preview: [TodayActivity] { Array(activities.prefix(2)) }
    var name: String {
        switch latest {
        case let .account(account): account.latest.authorName
        case let .money(money): money.publicIdentity.displayName
        }
    }
    var source: TodayActivityFilter { latest.isSmartAccount ? .accounts : .money }

    static func groups(accountUpdates: [SmartAccountUpdate], moneyMovements: [SmartMoneyMovement],
                       now: Date = Date()) -> [Self] {
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let entries = accountUpdates.map { TodayActivity.account(.init(updates: [$0])) }
            + moneyMovements.map { TodayActivity.money(.init(movements: [$0])) }
        var seen = Set<String>()
        let recent = entries.filter { $0.occurredAt >= cutoff && $0.occurredAt <= now }
            .sorted(by: newestFirst)
            .filter { activity in
                seen.insert("\(identity(activity)):\(activity.id)").inserted
            }
        return Dictionary(grouping: recent, by: identity).map { key, entries in
            Self(id: key, activities: entries.sorted(by: newestFirst))
        }.sorted {
            if $0.latest.occurredAt != $1.latest.occurredAt {
                return $0.latest.occurredAt > $1.latest.occurredAt
            }
            return $0.id < $1.id
        }
    }

    static func previewAccounts(from groups: [Self], limit: Int = 3) -> [Self] {
        guard limit > 0 else { return [] }
        let accounts = groups.filter { $0.source == .accounts }
        var selectedIDs = Set<String>()
        var platforms = Set<String>()
        for group in accounts {
            guard case let .account(account) = group.latest else { continue }
            if platforms.insert(accountPlatform(account.latest.platform)).inserted {
                selectedIDs.insert(group.id)
                if selectedIDs.count == limit { break }
            }
        }
        for group in accounts where selectedIDs.count < limit {
            selectedIDs.insert(group.id)
        }
        return accounts.filter { selectedIDs.contains($0.id) }
    }

    func matches(source: TodayActivityFilter, query: String) -> Bool {
        guard source == .all || self.source == source else { return false }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedCaseInsensitiveContains(query)
            || activities.contains { $0.ticker.localizedCaseInsensitiveContains(query) }
    }

    private static func identity(_ activity: TodayActivity) -> String {
        switch activity {
        case let .account(account):
            let update = account.latest
            return "account:\(accountPlatform(update.platform)):\(normalized(update.authorId))"
        case let .money(money): return "money:\(normalized(money.accountId))"
        }
    }

    private static func accountPlatform(_ value: String) -> String {
        let platform = normalized(value)
        switch platform {
        case "twitter", "twitter.com", "x.com": return "x"
        case "youtu.be", "youtube.com": return "youtube"
        default: return platform
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func newestFirst(_ lhs: TodayActivity, _ rhs: TodayActivity) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
        if identity(lhs) != identity(rhs) { return identity(lhs) < identity(rhs) }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
