import Foundation

struct PopularOpinion: Codable, Identifiable {
    let opinion: SmartAccountUpdate
    let totalTraders: Int
    let longTraders: Int
    let shortTraders: Int
    var id: UUID { opinion.id }

    func validate() throws {
        guard totalTraders > 0, longTraders >= 0, shortTraders >= 0, longTraders <= totalTraders,
              shortTraders == totalTraders - longTraders, !opinion.ticker.isEmpty,
              !opinion.authorId.isEmpty, !opinion.authorName.isEmpty,
              (0...0.25).contains(opinion.platformPercentile) else { throw BSmartAPIError.invalidResponse }
    }
}

struct PopularOpinionsPage: Codable {
    let items: [PopularOpinion]
    let nextOffset: Int?
    let windowDays: Int

    func validate(offset: Int) throws {
        guard offset >= 0, windowDays == 7, items.count <= 30,
              Set(items.map(\.id)).count == items.count,
              nextOffset == nil || (!items.isEmpty && nextOffset == offset + items.count) else {
            throw BSmartAPIError.invalidResponse
        }
        for item in items { try item.validate() }
        for pair in zip(items, items.dropFirst()) where pair.0.totalTraders < pair.1.totalTraders {
            throw BSmartAPIError.invalidResponse
        }
    }
}
