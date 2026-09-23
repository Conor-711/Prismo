import Foundation

extension TradeFeedDemoData {
    func rankings(query: DiscoveryRankingQuery, offset: Int, limit: Int, asOf: Date = Date()) throws -> DiscoveryRankingsPage {
        guard offset >= 0, (1...30).contains(limit) else { throw BSmartAPIError.invalidResponse }
        let recent = items.filter {
            $0.executedAt <= asOf && (query.window.days == nil ||
                $0.executedAt >= asOf.addingTimeInterval(-Double(query.window.days!) * 86400)) &&
                (0...0.25).contains($0.opinion.platformPercentile)
        }
        let groups = Dictionary(grouping: recent) {
            query.kind == .opinions ? $0.opinion.id.uuidString.lowercased()
                : $0.opinion.platform.lowercased() + ":" + $0.opinion.authorId
        }
        let ranked = groups.compactMap { id, group -> DiscoveryRankingItem? in
            let sorted = group.sorted { $0.executedAt != $1.executedAt ? $0.executedAt > $1.executedAt
                : $0.id.uuidString < $1.id.uuidString }
            guard let latest = sorted.first else { return nil }
            var seen = Set<UUID>()
            let people = sorted.filter { seen.insert($0.trader.id).inserted }
            let longs = people.filter { $0.side == .long }.count
            let amounts = group.compactMap(\.notional)
            let volume = amounts.count == group.count ? NSDecimalNumber(decimal: amounts.reduce(0, +)).stringValue : nil
            guard query.sort != .volume || volume != nil else { return nil }
            return .init(id: id, opinion: latest.opinion, totalTraders: people.count, totalNotionalUSD: volume,
                         opinionCount: Set(group.map { $0.opinion.id }).count, longTraders: longs,
                         shortTraders: people.count - longs, lastTradedAt: latest.executedAt)
        }.sorted { $0.precedes($1, sort: query.sort) }
        let page = Array(ranked.dropFirst(offset).prefix(limit))
        return .init(kind: query.kind, sort: query.sort, window: query.window, asOf: asOf, items: page,
                     nextOffset: offset + page.count < ranked.count ? offset + page.count : nil)
    }
}
