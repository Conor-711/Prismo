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

    func profile(id: UUID) throws -> FeedPublicProfile {
        guard let profile = items.first(where: { $0.trader.id == id })?.trader else {
            throw BSmartAPIError.httpStatus(404)
        }
        return profile
    }
}
