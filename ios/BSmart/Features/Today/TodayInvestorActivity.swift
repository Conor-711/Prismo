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

enum TodaySubjectKind: String, Codable {
    case politician, celebrity, institution

    var title: String {
        switch self {
        case .politician: "Politician"
        case .celebrity: "Public figure"
        case .institution: "Institution"
        }
    }

    var platform: String {
        switch self {
        case .politician: "congress"
        case .celebrity: "celebrity"
        case .institution: "institution"
        }
    }
}

struct TodaySubjectProfile: Decodable, Hashable, Identifiable {
    let id: String
    let kind: TodaySubjectKind
    let name: String
    let avatarURL: URL?
    let metrics: TodaySubjectMetrics?
    var research: TodaySubjectResearch? = nil

    var bundledAvatarAssetName: String { Self.avatarAssetName(for: id) }

    static func avatarAssetName(for id: String) -> String {
        "SubjectAvatar_" + id.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}

struct TodaySubjectResearch: Decodable, Hashable {
    let method: String
    let asOf: String
    let sourceSince: String
    let latestMarketDate: String
    let candidatePositions: Int
    let pricedPositions: Int
    let directionalWins: Int
    let directionalLosses: Int
    let directionalObservations: Int
    let directionalWinRate: Double?
    let openPositionPositiveRate: Double?
    let meanOpenReturn: Double?

    var winRateFromDecidedOutcomes: Double? {
        let decided = directionalWins + directionalLosses
        return decided > 0 ? Double(directionalWins) / Double(decided) : nil
    }

    var isValid: Bool {
        method == "three_year_open_positions_v1"
            && candidatePositions >= pricedPositions && pricedPositions >= 0
            && directionalWins >= 0 && directionalLosses >= 0
            && directionalWins + directionalLosses <= directionalObservations
            && directionalWinRate.map { $0.isFinite && (0...1).contains($0) } ?? true
            && meanOpenReturn.map { $0.isFinite && $0 >= -1 } ?? true
            && openPositionPositiveRate.map { $0.isFinite && (0...1).contains($0) } ?? true
            && SubjectFeedDay.parse(asOf) != .distantPast
            && SubjectFeedDay.parse(sourceSince) != .distantPast
            && SubjectFeedDay.parse(latestMarketDate) != .distantPast
            && sourceSince <= latestMarketDate && latestMarketDate <= asOf
    }
}

enum TodaySubjectEventType: String, Codable {
    case trade, opinion, holding
}

struct TodaySubjectEvent: Codable, Identifiable, Hashable {
    let id: String
    let subjectID: String
    let ticker: String?
    let underlyingTicker: String?
    let cusip: String?
    let assetName: String?
    let type: TodaySubjectEventType
    let action: String?
    let direction: String?
    let summary: String?
    let occurredDay: String
    let displayDay: String
    let amountRange: String?
    let assetDescription: String?
    let sourceURL: URL?
    let sourceNote: String?
    let isSample: Bool
    let eventDayAdjustedClose: Double?
    let latestAdjustedClose: Double?
    let latestPriceDay: String?
    let priceBasis: String?

    var displayedAt: Date { SubjectFeedDay.parse(displayDay) }
    var occurredAt: Date { SubjectFeedDay.parse(occurredDay) }
    var isBuy: Bool { action == "buy" }
    var displayAsset: String { ticker ?? underlyingTicker ?? assetName ?? "" }
    var syncTicker: String? { ticker ?? (type == .holding ? underlyingTicker : nil) }
    var syncSource: OpinionTradeSource? {
        guard let syncTicker else { return nil }
        return .init(opinionID: nil, ticker: syncTicker, subjectID: subjectID, subjectEventID: id)
    }
    var holdingTitle: String {
        switch action {
        case "new": "New holding"
        case "increased": "Increased"
        case "reduced": "Reduced"
        case "no_longer_reported": "No longer reported"
        default: "Holding"
        }
    }
    var directionTitle: String {
        switch direction {
        case "bullish": "Bullish"
        case "bearish": "Bearish"
        default: "Neutral"
        }
    }
}

struct TodaySubjectMetrics: Decodable, Hashable {
    let wins: Int
    let losses: Int
    let trackedReturn: Double
}

struct TodaySubjectActivity: Identifiable, Hashable {
    let subject: TodaySubjectProfile
    let events: [TodaySubjectEvent]

    var id: String { subject.id }
    var name: String { subject.name }
    var latest: TodaySubjectEvent { events[0] }
    var preview: [TodaySubjectEvent] { Array(events.prefix(2)) }
    var metrics: TodaySubjectMetrics { subject.metrics ?? Self.sampleMetrics(for: id) }
    var hasSampleMetrics: Bool { subject.metrics == nil }
    var researchMetric: TodaySubjectResearch? { subject.research }
    var previewRank: Int {
        let seed = id.utf8.reduce(UInt64(2_166_136_261)) { ($0 ^ UInt64($1)) &* 16_777_619 }
        return 1 + Int(seed % 20)
    }

    private static func sampleMetrics(for id: String) -> TodaySubjectMetrics {
        let seed = id.utf8.reduce(UInt64(2_166_136_261)) { ($0 ^ UInt64($1)) &* 16_777_619 }
        return TodaySubjectMetrics(wins: 18 + Int(seed % 47),
                                   losses: 7 + Int((seed / 47) % 27),
                                   trackedReturn: Double(Int((seed / 1_269) % 651) - 180) / 1_000)
    }

    static func history(for id: String, in snapshot: TodaySubjectFeedSnapshot) -> Self? {
        guard let subject = snapshot.subjects.first(where: { $0.id == id }) else { return nil }
        let events = snapshot.events.filter { $0.subjectID == id }.sorted {
            $0.displayDay == $1.displayDay ? $0.id > $1.id : $0.displayDay > $1.displayDay
        }
        guard !events.isEmpty else { return nil }
        return Self(subject: subject, events: events)
    }

    static func groups(from snapshot: TodaySubjectFeedSnapshot, now: Date = Date()) -> [Self] {
        let cutoff = SubjectFeedDay.format(now.addingTimeInterval(-30 * 86_400))
        let holdingsCutoff = SubjectFeedDay.format(now.addingTimeInterval(-400 * 86_400))
        let today = SubjectFeedDay.format(now)
        let profiles = Dictionary(uniqueKeysWithValues: snapshot.subjects.map { ($0.id, $0) })
        let eligible = snapshot.events.filter {
            $0.displayDay >= holdingsCutoff
                && $0.displayDay <= today && profiles[$0.subjectID] != nil
        }
        return Dictionary(grouping: eligible, by: \.subjectID).compactMap { id, events in
            guard let subject = profiles[id] else { return nil }
            let sorted = events.sorted {
                $0.displayDay == $1.displayDay ? $0.id > $1.id : $0.displayDay > $1.displayDay
            }
            guard let latest = sorted.first,
                  latest.type == .holding || latest.displayDay >= cutoff else { return nil }
            return Self(subject: subject, events: sorted)
        }.sorted { $0.latest.displayDay == $1.latest.displayDay
            ? $0.id < $1.id : $0.latest.displayDay > $1.latest.displayDay }
    }

    func matches(query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || name.localizedCaseInsensitiveContains(value)
            || events.contains { ($0.ticker?.localizedCaseInsensitiveContains(value) ?? false)
                || ($0.assetName?.localizedCaseInsensitiveContains(value) ?? false) }
    }
}

struct TodaySubjectFeedSnapshot: Decodable {
    let schemaVersion: Int
    let snapshotAt: String?
    let subjects: [TodaySubjectProfile]
    let events: [TodaySubjectEvent]

    var isValid: Bool {
        guard schemaVersion == 1, subjects.count <= 10_000, events.count <= 100_000 else { return false }
        let ids = Set(subjects.map(\.id))
        return ids.count == subjects.count && Set(events.map(\.id)).count == events.count
            && subjects.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty }
            && subjects.allSatisfy { $0.research?.isValid ?? true }
            && subjects.allSatisfy { $0.avatarURL.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? true }
            && events.allSatisfy { event in
                guard ids.contains(event.subjectID),
                      SubjectFeedDay.parse(event.displayDay) != .distantPast,
                      SubjectFeedDay.parse(event.occurredDay) != .distantPast,
                      event.sourceURL.map({ ["http", "https"].contains($0.scheme?.lowercased() ?? "") }) ?? true
                else { return false }
                let priceFields = [event.eventDayAdjustedClose, event.latestAdjustedClose]
                if priceFields.contains(where: { $0 != nil }) || event.latestPriceDay != nil {
                    guard priceFields.allSatisfy({ $0.map { $0.isFinite && $0 > 0 } ?? false }),
                          let latestDay = event.latestPriceDay,
                          SubjectFeedDay.parse(latestDay) >= SubjectFeedDay.parse(event.occurredDay)
                    else { return false }
                }
                switch event.type {
                case .trade:
                    return !(event.ticker ?? "").isEmpty && ["buy", "sell"].contains(event.action ?? "")
                case .opinion:
                    return !(event.ticker ?? "").isEmpty
                        && ["bullish", "bearish", "neutral"].contains(event.direction ?? "")
                        && !(event.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                case .holding:
                    return !(event.assetName ?? "").isEmpty && event.sourceURL != nil
                        && ["new", "increased", "reduced", "no_longer_reported", "held"].contains(event.action ?? "")
                }
            }
    }

    static let bundled: Self = {
        guard let url = Bundle.main.url(forResource: "subject-activity", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(schemaVersion: 1, snapshotAt: nil, subjects: [], events: [])
        }
        return snapshot
    }()
}

enum SubjectFeedDay {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String) -> Date { formatter.date(from: value) ?? .distantPast }
    static func format(_ value: Date) -> String { formatter.string(from: value) }
}
