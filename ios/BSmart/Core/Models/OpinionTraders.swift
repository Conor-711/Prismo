import Foundation

struct OpinionTrader: Codable, Identifiable, Equatable {
    enum Side: String, Codable { case long, short }
    let id: UUID
    let nickname: String
    let avatarURL: URL?
    let side: Side
    let tradedAt: Date
}

struct OpinionTradersPage: Codable {
    let totalTraders: Int
    let publicTraders: Int
    let traders: [OpinionTrader]
    let nextOffset: Int?

    func validate(offset: Int) throws {
        guard totalTraders >= publicTraders, publicTraders >= 0, offset >= 0,
              traders.count <= 50, Set(traders.map(\.id)).count == traders.count,
              publicTraders >= traders.count,
              nextOffset == nil || (!traders.isEmpty && nextOffset == offset + traders.count),
              traders.allSatisfy({ !$0.nickname.isEmpty && $0.nickname.count <= 28 }) else {
            throw BSmartAPIError.invalidResponse
        }
    }
}

struct OpinionTradeSource: Equatable {
    let opinionID: UUID
    let ticker: String
    var feedEventID: UUID? = nil

    func matches(symbol: String) -> Bool {
        ticker.caseInsensitiveCompare(symbol) == .orderedSame
    }
}
