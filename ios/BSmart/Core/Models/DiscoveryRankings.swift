import Foundation

enum DiscoveryRankingKind: String, Codable, CaseIterable {
    case opinions, investors
    var title: String { self == .opinions ? "Trending opinions" : "Trending investors" }
}

enum DiscoveryRankingSort: String, Codable, CaseIterable {
    case traders, volume
    var title: String { self == .traders ? "Trading people" : "Trading volume" }
}

enum DiscoveryRankingWindow: String, Codable, CaseIterable {
    case day = "1d", week = "7d", month = "30d", all
    var title: String {
        switch self {
        case .day: "24 hours"
        case .week: "Past 7 days"
        case .month: "Past 30 days"
        case .all: "All time"
        }
    }
    var days: Int? {
        switch self { case .day: 1; case .week: 7; case .month: 30; case .all: nil }
    }
}

struct DiscoveryRankingQuery: Equatable, Hashable {
    let kind: DiscoveryRankingKind
    var sort: DiscoveryRankingSort = .traders
    var window: DiscoveryRankingWindow = .week
}

struct DiscoveryRankingItem: Codable, Identifiable {
    let id: String
    let opinion: SmartAccountUpdate
    let totalTraders: Int
    let totalNotionalUSD: String?
    let opinionCount: Int
    let longTraders: Int
    let shortTraders: Int
    let lastTradedAt: Date

    var volume: Decimal? {
        guard let value = totalNotionalUSD, value.count <= 100,
              value.range(of: "^[0-9]+([.][0-9]+)?$", options: .regularExpression) != nil,
              let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), number > 0 else { return nil }
        return number
    }
    var volumeLabel: String {
        volume?.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(0...2))) ?? "—"
    }
    func precedes(_ other: Self, sort: DiscoveryRankingSort) -> Bool {
        let a = sort == .traders ? Decimal(totalTraders) : volume ?? 0
        let b = sort == .traders ? Decimal(other.totalTraders) : other.volume ?? 0
        if a != b { return a > b }
        if lastTradedAt != other.lastTradedAt { return lastTradedAt > other.lastTradedAt }
        return id < other.id
    }
}

struct DiscoveryRankingsPage: Codable {
    let kind: DiscoveryRankingKind
    let sort: DiscoveryRankingSort
    let window: DiscoveryRankingWindow
    let asOf: Date
    let items: [DiscoveryRankingItem]
    let nextOffset: Int?

    func validate(query: DiscoveryRankingQuery, offset: Int, limit: Int, anchor: Date? = nil) throws {
        guard kind == query.kind, sort == query.sort, window == query.window,
              anchor == nil || abs(asOf.timeIntervalSince(anchor!)) < 0.001,
              offset >= 0, (1...30).contains(limit), items.count <= limit,
              Set(items.map(\.id)).count == items.count,
              nextOffset == nil || (!items.isEmpty && nextOffset == offset + items.count) else {
            throw BSmartAPIError.invalidResponse
        }
        for item in items {
            let expectedID = kind == .opinions ? item.opinion.id.uuidString.lowercased()
                : item.opinion.platform.lowercased() + ":" + item.opinion.authorId
            guard item.id == expectedID, item.totalTraders > 0, item.opinionCount > 0,
                  kind != .opinions || item.opinionCount == 1,
                  item.longTraders >= 0, item.longTraders <= item.totalTraders,
                  item.shortTraders == item.totalTraders - item.longTraders,
                  !item.opinion.authorId.isEmpty, !item.opinion.authorName.isEmpty,
                  !item.opinion.platform.isEmpty, item.opinion.platform.lowercased() != "hyperliquid",
                  (0...0.25).contains(item.opinion.platformPercentile),
                  item.lastTradedAt <= asOf,
                  window.days == nil || item.lastTradedAt >= asOf.addingTimeInterval(-Double(window.days!) * 86400),
                  item.totalNotionalUSD == nil || item.volume != nil,
                  sort != .volume || item.volume != nil else { throw BSmartAPIError.invalidResponse }
        }
        for (a, b) in zip(items, items.dropFirst()) where b.precedes(a, sort: sort) {
            throw BSmartAPIError.invalidResponse
        }
    }
}
