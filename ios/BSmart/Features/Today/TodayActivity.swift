import Foundation

enum TodayActivityScope: String, CaseIterable, Identifiable {
    case holdings
    case watchlist

    var id: Self { self }

    var label: String {
        switch self {
        case .holdings: "My holdings".bSmartLocalized
        case .watchlist: "Watchlist".bSmartLocalized
        }
    }
}

enum TodayActivityPlatform: String, CaseIterable, Identifiable {
    case all
    case x
    case youtube
    case reddit

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All platforms".bSmartLocalized
        case .x: "X"
        case .youtube: "YouTube"
        case .reddit: "Reddit"
        }
    }
}

enum TodayActivityFilter: String, CaseIterable, Identifiable {
    case all
    case accounts
    case money

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All updates".bSmartLocalized
        case .accounts: "Smart Account"
        case .money: "Smart Money"
        }
    }
}

enum TodayActivitySort: String, CaseIterable, Identifiable {
    case latest
    case smartScore

    var id: Self { self }

    var label: String {
        switch self {
        case .latest: "Latest".bSmartLocalized
        case .smartScore: "Smart score".bSmartLocalized
        }
    }

    var symbol: String {
        switch self {
        case .latest: "clock"
        case .smartScore: "sparkles"
        }
    }
}

struct TodayAccountActivity: Identifiable, Hashable {
    let updates: [SmartAccountUpdate]

    init(updates: [SmartAccountUpdate]) {
        precondition(!updates.isEmpty)
        self.updates = updates.sorted { $0.publishedAt > $1.publishedAt }
    }

    var id: UUID { latest.id }
    var latest: SmartAccountUpdate { updates[0] }
    var ticker: String { latest.ticker }
    var occurredAt: Date { latest.publishedAt }
    var mentionCount: Int { updates.count }

    func informativeTitle(for update: SmartAccountUpdate) -> String {
        accountActivityTitle(update)
    }
}

struct TodayMoneyActivity: Identifiable, Hashable {
    let movements: [SmartMoneyMovement]

    init(movements: [SmartMoneyMovement]) {
        precondition(!movements.isEmpty)
        self.movements = movements.sorted { $0.observedAt > $1.observedAt }
    }

    var id: UUID { latest.id }
    var latest: SmartMoneyMovement { movements[0] }
    var ticker: String { latest.ticker }
    var accountId: String { latest.accountId }
    var accountScore: Double { latest.accountScore }
    var market: String { latest.market }
    var action: SmartMoneyAction { latest.action }
    var direction: SignalDirection { latest.direction }
    var observedAt: Date { latest.observedAt }
    var evidenceURL: URL? { latest.evidenceURL }
    var publicIdentity: SmartMoneyPublicIdentity { latest.publicIdentity }
    var transactionCount: Int { movements.count }
    var notionalBefore: Double { movements.reduce(0) { $0 + $1.notionalBefore } }
    var notionalAfter: Double { movements.reduce(0) { $0 + $1.notionalAfter } }
    var notionalChange: Double { movements.reduce(0) { $0 + $1.notionalChange } }

    var leverage: Double? {
        let values = movements.compactMap(\.leverage)
        guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.01 }) else {
            return latest.leverage
        }
        return first
    }
}

enum TodayActivity: Identifiable, Hashable {
    case account(TodayAccountActivity)
    case money(TodayMoneyActivity)

    var id: UUID {
        switch self {
        case let .account(activity): activity.id
        case let .money(activity): activity.id
        }
    }

    var ticker: String {
        switch self {
        case let .account(activity): activity.ticker
        case let .money(activity): activity.ticker
        }
    }

    var occurredAt: Date {
        switch self {
        case let .account(activity): activity.occurredAt
        case let .money(activity): activity.observedAt
        }
    }

    var isSmartAccount: Bool {
        if case .account = self { return true }
        return false
    }

    var platform: TodayActivityPlatform {
        switch self {
        case let .account(activity):
            switch activity.latest.platform.lowercased() {
            case "youtube", "youtu.be": .youtube
            case "reddit", "reddit.com": .reddit
            default: .x
            }
        case .money:
            .all
        }
    }

    var smartRankPercentile: Double {
        max(0, min(100, 100 - rawSmartScore))
    }

    var direction: SignalDirection {
        switch self {
        case let .account(activity): activity.latest.direction
        case let .money(activity): activity.direction
        }
    }

    fileprivate var rawSmartScore: Double {
        switch self {
        case let .account(activity):
            return max(0, min(100, (1 - activity.latest.platformPercentile) * 100))
        case let .money(activity):
            return activity.accountScore
        }
    }

    var actorKey: String {
        switch self {
        case let .account(activity): "account:\(activity.latest.authorId.lowercased())"
        case let .money(activity): "money:\(activity.accountId.lowercased())"
        }
    }

    var informativeTitle: String {
        switch self {
        case let .account(activity): accountActivityTitle(activity.latest)
        case let .money(activity): moneyActivityTitle(activity)
        }
    }
}

extension TodayActivity {
    static func latestTrackedActivities(
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement],
        smartAccounts: [SmartAccountProfile] = [],
        followedAccountIDs: Set<String>,
        followedMoneyIDs: Set<String>
    ) -> [TodayActivity] {
        let accountIDs = Set(followedAccountIDs.map { $0.lowercased() })
        let moneyIDs = Set(followedMoneyIDs.map { $0.lowercased() })
        let followedProfiles = smartAccounts.filter { accountIDs.contains($0.id.lowercased()) }

        var latestAccountByID: [String: SmartAccountUpdate] = [:]
        for update in accountUpdates {
            let directKey = update.authorId.lowercased()
            let profileKey = followedProfiles.first(where: { profile in
                profile.id.caseInsensitiveCompare(update.authorId) == .orderedSame
                    || profile.name.caseInsensitiveCompare(update.authorName) == .orderedSame
                    || profile.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                        .caseInsensitiveCompare(update.authorName.trimmingCharacters(in: CharacterSet(charactersIn: "@"))) == .orderedSame
            })?.id.lowercased()
            guard let key = accountIDs.contains(directKey) ? directKey : profileKey else { continue }
            if update.publishedAt > (latestAccountByID[key]?.publishedAt ?? .distantPast) {
                latestAccountByID[key] = update
            }
        }

        var latestMoneyByID: [String: SmartMoneyMovement] = [:]
        for movement in moneyMovements where moneyIDs.contains(movement.accountId.lowercased()) {
            let key = movement.accountId.lowercased()
            if movement.observedAt > (latestMoneyByID[key]?.observedAt ?? .distantPast) {
                latestMoneyByID[key] = movement
            }
        }

        let accounts = latestAccountByID.values.map {
            TodayActivity.account(TodayAccountActivity(updates: [$0]))
        }
        let money = latestMoneyByID.values.map {
            TodayActivity.money(TodayMoneyActivity(movements: [$0]))
        }

        return (accounts + money).sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.actorKey < rhs.actorKey
        }
    }

    static func limitingRepeatedActors(
        _ activities: [TodayActivity],
        maximumPerActor: Int = 2
    ) -> [TodayActivity] {
        guard maximumPerActor > 0 else { return [] }
        var counts: [String: Int] = [:]
        return activities.filter { activity in
            let count = counts[activity.actorKey, default: 0]
            guard count < maximumPerActor else { return false }
            counts[activity.actorKey] = count + 1
            return true
        }
    }

    static func activities(
        scope: TodayActivityScope,
        positions: [PortfolioPosition],
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement],
        sort: TodayActivitySort = .latest
    ) -> [TodayActivity] {
        let scopedPositions = positions.filter { position in
            switch scope {
            case .holdings: position.isPosition
            case .watchlist: !position.isPosition
            }
        }
        let tickers = Set(scopedPositions.map { $0.ticker.uppercased() })

        let accountActivities = groupedAccountActivities(
            accountUpdates
                .filter { tickers.contains($0.ticker.uppercased()) }
                .sorted { $0.publishedAt > $1.publishedAt }
        )
            .map(TodayActivity.account)
        let moneyActivities = groupedMoneyActivities(
            moneyMovements
            .filter { tickers.contains($0.ticker.uppercased()) }
            .sorted { $0.observedAt > $1.observedAt }
        )
            .map(TodayActivity.money)

        let combined = accountActivities + moneyActivities
        switch sort {
        case .latest:
            return combined.sorted { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
                return lhs.rawSmartScore > rhs.rawSmartScore
            }
        case .smartScore:
            let percentiles = normalizedSmartPercentiles(for: combined)
            return combined.sorted { lhs, rhs in
                let lhsScore = percentiles[lhs.id] ?? 0
                let rhsScore = percentiles[rhs.id] ?? 0
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.occurredAt > rhs.occurredAt
            }
        }
    }

    private struct AccountThreadKey: Hashable {
        let authorId: String
        let ticker: String
        let direction: SignalDirection
        let horizon: String
        let targetPrice: Int?
    }

    private static func groupedAccountActivities(
        _ updates: [SmartAccountUpdate]
    ) -> [TodayAccountActivity] {
        let groupingWindow: TimeInterval = 14 * 24 * 60 * 60
        var groups: [[SmartAccountUpdate]] = []

        for update in updates {
            guard update.lifecycle == .new else {
                groups.append([update])
                continue
            }

            let key = accountThreadKey(update)
            if let index = groups.firstIndex(where: { group in
                guard let newest = group.first, newest.lifecycle == .new else { return false }
                return accountThreadKey(newest) == key
                    && newest.publishedAt.timeIntervalSince(update.publishedAt) <= groupingWindow
            }) {
                groups[index].append(update)
            } else {
                groups.append([update])
            }
        }

        return groups.map(TodayAccountActivity.init)
    }

    private static func accountThreadKey(_ update: SmartAccountUpdate) -> AccountThreadKey {
        AccountThreadKey(
            authorId: update.authorId.lowercased(),
            ticker: update.ticker.uppercased(),
            direction: update.direction,
            horizon: update.horizon.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            targetPrice: update.targetPrice.map { Int(($0 * 100).rounded()) }
        )
    }

    private static func normalizedSmartPercentiles(
        for activities: [TodayActivity]
    ) -> [UUID: Double] {
        var values: [UUID: Double] = [:]
        let sources = [
            activities.filter(\.isSmartAccount),
            activities.filter { !$0.isSmartAccount },
        ]

        for source in sources {
            let scores = Array(Set(source.map(\.rawSmartScore))).sorted()
            guard !scores.isEmpty else { continue }
            if scores.count == 1 {
                for activity in source { values[activity.id] = 100 }
                continue
            }
            let denominator = Double(scores.count - 1)
            var percentileByScore: [Double: Double] = [:]
            for (index, score) in scores.enumerated() where percentileByScore[score] == nil {
                percentileByScore[score] = 100 * Double(index) / denominator
            }
            for activity in source {
                values[activity.id] = percentileByScore[activity.rawSmartScore] ?? 0
            }
        }
        return values
    }


    private static func groupedMoneyActivities(
        _ movements: [SmartMoneyMovement]
    ) -> [TodayMoneyActivity] {
        let groupingWindow: TimeInterval = 10 * 60
        var groups: [[SmartMoneyMovement]] = []

        for movement in movements {
            guard movement.action == .opened || movement.action == .closed else {
                groups.append([movement])
                continue
            }

            if let index = groups.firstIndex(where: { group in
                guard let newest = group.first else { return false }
                return newest.accountId == movement.accountId
                    && newest.ticker.caseInsensitiveCompare(movement.ticker) == .orderedSame
                    && newest.market == movement.market
                    && newest.action == movement.action
                    && newest.direction == movement.direction
                    && abs(newest.observedAt.timeIntervalSince(movement.observedAt)) <= groupingWindow
            }) {
                groups[index].append(movement)
            } else {
                groups.append([movement])
            }
        }

        return groups.map(TodayMoneyActivity.init)
    }
}

private func accountActivityTitle(_ update: SmartAccountUpdate) -> String {
    if BSmartLocalization.isSimplifiedChinese,
       let localized = update.activityTitleZH?.todayNonBlank ?? update.activityTitle?.todayNonBlank {
        return localized
    }
    if !BSmartLocalization.isSimplifiedChinese,
       let localized = update.activityTitleEN?.todayNonBlank ?? update.activityTitle?.todayNonBlank {
        return localized
    }

    let insight = conciseActivityInsight(update.thesis)
    let direction = update.direction.label.bSmartLocalized
    if let targetPrice = update.targetPrice {
        return "%@ %@ toward %@: %@".bSmartLocalized(
            direction,
            update.ticker,
            targetPrice.formatted(.currency(code: "USD").precision(.fractionLength(0))),
            insight
        )
    }

    switch update.lifecycle {
    case .strengthened:
        return "Strengthened %@ view on %@: %@".bSmartLocalized(direction, update.ticker, insight)
    case .weakened:
        return "Reduced conviction on %@: %@".bSmartLocalized(update.ticker, insight)
    case .reversed:
        return "Reversed %@ to %@: %@".bSmartLocalized(update.ticker, direction, insight)
    case .closed:
        return "Closed %@ view: %@".bSmartLocalized(update.ticker, insight)
    case .invalidated:
        return "%@ view invalidated: %@".bSmartLocalized(update.ticker, insight)
    case .new:
        return "%@ %@: %@".bSmartLocalized(direction, update.ticker, insight)
    }
}

private func moneyActivityTitle(_ activity: TodayMoneyActivity) -> String {
    let side = switch activity.direction {
    case .bullish: "long position".bSmartLocalized
    case .bearish: "short position".bSmartLocalized
    case .neutral, .mixed: "position".bSmartLocalized
    }
    let amount = compactActivityUSD(abs(activity.notionalChange))

    switch activity.action {
    case .opened:
        return "Opened %@ %@, about %@ total".bSmartLocalized(activity.ticker, side, amount)
    case .increased:
        return "Added to %@ %@, about %@".bSmartLocalized(activity.ticker, side, amount)
    case .reduced:
        return "Reduced %@ %@, about %@".bSmartLocalized(activity.ticker, side, amount)
    case .closed:
        return "Closed %@ %@, reduced about %@ exposure".bSmartLocalized(activity.ticker, side, amount)
    case .flipped:
        return "Flipped %@ to %@, about %@".bSmartLocalized(activity.ticker, side, amount)
    }
}

private func conciseActivityInsight(_ text: String, limit: Int = 64) -> String {
    let normalized = text
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")

    let separators = ["。", "！", "？", ". ", "; ", "；"]
    let end = separators.compactMap { normalized.range(of: $0)?.lowerBound }.min()
    let sentence = end.map { String(normalized[..<$0]) } ?? normalized
    guard sentence.count > limit else { return sentence }
    return String(sentence.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

private func compactActivityUSD(_ value: Double) -> String {
    switch abs(value) {
    case 1_000_000...:
        return String(format: "$%.1fM", value / 1_000_000)
    case 1_000...:
        return String(format: "$%.1fK", value / 1_000)
    default:
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

private extension String {
    var todayNonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
