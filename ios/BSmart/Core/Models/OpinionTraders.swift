import Foundation

struct OpinionTrader: Codable, Identifiable, Equatable {
    enum Side: String, Codable { case long, short }
    let id: UUID
    let nickname: String
    let avatarURL: URL?
    let side: Side
    let tradedAt: Date
    var handle: String? = nil
}

struct OpinionTradersPage: Codable {
    let totalTraders: Int
    let publicTraders: Int
    let traders: [OpinionTrader]
    let nextOffset: Int?
    var longTraders: Int? = nil
    var shortTraders: Int? = nil
    var totalNotionalUSD: String? = nil

    var totalNotional: Decimal? {
        guard let totalNotionalUSD else { return nil }
        return Decimal(string: totalNotionalUSD, locale: Locale(identifier: "en_US_POSIX"))
    }

    var totalNotionalLabel: String? {
        guard let totalNotional else { return nil }
        return totalNotional.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))
            .precision(.fractionLength(0...2)))
    }

    func validate(offset: Int) throws {
        if let totalNotionalUSD {
            guard totalNotionalUSD.count <= 64,
                  totalNotionalUSD.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let totalNotional, totalNotional >= 0 else { throw BSmartAPIError.invalidResponse }
        }
        if let longTraders, let shortTraders {
            guard longTraders >= 0, shortTraders >= 0, longTraders <= totalTraders,
                  shortTraders == totalTraders - longTraders else { throw BSmartAPIError.invalidResponse }
        } else if longTraders != nil || shortTraders != nil { throw BSmartAPIError.invalidResponse }
        guard totalTraders >= publicTraders, publicTraders >= 0, offset >= 0,
              traders.count <= 50, Set(traders.map(\.id)).count == traders.count,
              publicTraders >= traders.count,
              nextOffset == nil || (!traders.isEmpty && nextOffset == offset + traders.count),
              traders.allSatisfy({ !$0.nickname.isEmpty && $0.nickname.count <= 28
                  && ($0.handle == nil || AccountProfile.validHandle($0.handle!))
                  && ($0.avatarURL == nil || $0.avatarURL?.scheme == "https") }) else {
            throw BSmartAPIError.invalidResponse
        }
    }
}

struct OpinionTradeSource: Equatable {
    let opinionID: UUID
    let ticker: String
    var feedEventID: UUID? = nil
    var authorID: String? = nil
    var supportsThesis = true

    func matches(symbol: String) -> Bool {
        ticker.caseInsensitiveCompare(symbol) == .orderedSame
    }
}
