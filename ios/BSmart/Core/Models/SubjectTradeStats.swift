import Foundation

struct TradeSubject: Equatable {
    enum Kind: String, Codable { case account, money }
    let kind: Kind
    let id: String
    let platform: String

    init(account: SmartAccountProfile) {
        kind = .account; id = account.id; platform = account.platform
    }

    init(money: SmartMoneySignal) {
        kind = .money; id = money.id; platform = "hyperliquid"
    }

    init(kind: Kind, id: String, platform: String) {
        self.kind = kind; self.id = id; self.platform = platform
    }
}

struct SubjectTradeStats: Decodable, Equatable {
    let kind: TradeSubject.Kind
    let subjectId, platform: String
    let totalTrades, longTrades, shortTrades, sourceCount: Int

    func validate(subject: TradeSubject) throws {
        guard kind == subject.kind, subjectId == subject.id, platform == subject.platform,
              totalTrades >= 0, longTrades >= 0, longTrades <= totalTrades,
              shortTrades == totalTrades - longTrades,
              sourceCount >= 0, sourceCount <= totalTrades,
              (sourceCount == 0) == (totalTrades == 0) else { throw BSmartAPIError.invalidResponse }
    }
}
