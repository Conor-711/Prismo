import Foundation

struct FeedPublicPortfolio: Decodable {
    enum Status: String, Decodable { case ready, notConnected = "not_connected" }
    struct Point: Decodable, Identifiable {
        let at: TimeInterval
        let valueUSD: String
        var id: TimeInterval { at }
        var date: Date { Date(timeIntervalSince1970: at / 1000) }
        var value: Double { Double(valueUSD) ?? 0 }
    }
    struct History: Decodable {
        let day: [Point]
        let week: [Point]
        let month: [Point]
    }
    struct Position: Decodable, Identifiable {
        enum Side: String, Decodable { case long, short }
        let coin: String
        let side: Side
        let size: String
        let valueUSD: String
        let entryPriceUSD: String?
        let unrealizedPnLUSD: String
        let returnOnEquity: String
        let leverage: Int
        var id: String { coin }
        var symbol: String { String(coin.split(separator: ":").last ?? Substring(coin)) }
    }

    let status: Status
    let perpsEquityUSD: String?
    let equityAsOf: TimeInterval?
    let spotUSDC: String?
    let positions: [Position]
    let history: History

    func validate() throws {
        guard positions.count <= 1000, Set(positions.map(\.coin)).count == positions.count,
              positions.allSatisfy({ $0.leverage > 0 && $0.leverage <= 1000 && Self.valid($0.valueUSD)
                  && Self.valid($0.size) && Self.valid($0.unrealizedPnLUSD) && Self.valid($0.returnOnEquity)
                  && ($0.entryPriceUSD == nil || Self.valid($0.entryPriceUSD!)) }),
              Self.valid(perpsEquityUSD), Self.valid(spotUSDC),
              [history.day, history.week, history.month].allSatisfy({ points in
                  points.count <= 121 && points.allSatisfy({ Self.valid($0.valueUSD) && $0.at > 0 })
                      && zip(points, points.dropFirst()).allSatisfy({ $0.at < $1.at })
              }) else { throw BSmartAPIError.invalidResponse }
        if status == .notConnected && (!positions.isEmpty || perpsEquityUSD != nil || spotUSDC != nil) {
            throw BSmartAPIError.invalidResponse
        }
    }

    private static func valid(_ value: String?) -> Bool {
        guard let value, value.count <= 48, let number = Double(value), number.isFinite else { return value == nil }
        return true
    }
}
