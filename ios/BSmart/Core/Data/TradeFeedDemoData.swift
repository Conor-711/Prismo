import Foundation

/// Explicit local preview. These identities and trades never enter the live API.
struct TradeFeedDemoData {
    let items: [TradeFeedItem]

    static func load(bundle: Bundle = .main, now: Date = Date()) throws -> Self {
        guard let url = bundle.url(forResource: "trade-feed-demo", withExtension: "json") else {
            throw BSmartAPIError.invalidResponse
        }
        let page = try BSmartJSONCoding.makeDecoder().decode(TradeFeedPage.self, from: Data(contentsOf: url))
        let ages: [TimeInterval] = [120, 480, 1_500, 3_600, 10_800, 86_400]
        let items = page.items.enumerated().map { index, item in
            TradeFeedItem(id: item.id, trader: item.trader, opinion: item.opinion,
                          side: item.side, notionalUSD: item.notionalUSD, marketCoin: item.marketCoin,
                          executedAt: now.addingTimeInterval(-ages[min(index, ages.count - 1)]))
        }
        try TradeFeedPage(items: items, nextOffset: nil).validate(offset: 0)
        return Self(items: items)
    }

    func page(offset: Int, profileID: UUID? = nil) throws -> TradeFeedPage {
        guard offset >= 0 else { throw BSmartAPIError.invalidResponse }
        let filtered = items.filter { profileID == nil || $0.trader.id == profileID }
        let rows = Array(filtered.dropFirst(offset).prefix(3))
        return .init(items: rows, nextOffset: offset + rows.count < filtered.count ? offset + rows.count : nil)
    }

    func popular(offset: Int, now: Date = Date()) throws -> PopularOpinionsPage {
        guard offset >= 0 else { throw BSmartAPIError.invalidResponse }
        let recent = items.filter { $0.executedAt >= now.addingTimeInterval(-7 * 86400) && $0.executedAt <= now }
        let groups = Dictionary(grouping: recent, by: { $0.opinion.id })
        let rows = groups.values.compactMap { group -> (PopularOpinion, Date)? in
            let sorted = group.sorted { $0.executedAt != $1.executedAt ? $0.executedAt > $1.executedAt
                : $0.id.uuidString < $1.id.uuidString }
            guard let latest = sorted.first else { return nil }
            var seen = Set<UUID>()
            let people = sorted.filter { seen.insert($0.trader.id).inserted }
            let longs = people.filter { $0.side == .long }.count
            return (.init(opinion: latest.opinion, totalTraders: people.count,
                          longTraders: longs, shortTraders: people.count - longs), latest.executedAt)
        }.sorted {
            if $0.0.totalTraders != $1.0.totalTraders { return $0.0.totalTraders > $1.0.totalTraders }
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id.uuidString < $1.0.id.uuidString
        }.map { $0.0 }
        let page = Array(rows.dropFirst(offset).prefix(10))
        return .init(items: page, nextOffset: offset + page.count < rows.count ? offset + page.count : nil, windowDays: 7)
    }

    func profile(id: UUID) throws -> FeedPublicProfile {
        guard let profile = items.first(where: { $0.trader.id == id })?.trader else {
            throw BSmartAPIError.httpStatus(404)
        }
        return profile
    }
}
