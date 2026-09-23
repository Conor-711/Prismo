import Foundation

extension NativeTradeFeedClient {
    // Already verified trades must not depend on a second exchange sync succeeding.
    func activityForWriting(cloid: String, accountID: UUID) async throws -> TradeFeedItem {
        do {
            return try await activity(cloid: cloid, accountID: accountID)
        } catch TradeThesisError.pending {
            _ = try await synchronize(accountID: accountID, cloid: cloid)
            return try await activity(cloid: cloid, accountID: accountID)
        }
    }

    func activity(cloid: String, accountID: UUID) async throws -> TradeFeedItem {
        let item: TradeFeedItem = try await request("/orders/\(cloid)/activity", expectedAccountID: accountID)
        try item.validate()
        return item
    }

    func publishThesis(tradeID: UUID, body: String, accountID: UUID) async throws -> TradeThesis {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TradeThesis.validBody(text) else { throw TradeThesisError.invalid }
        let result: TradeThesis = try await request("/trades/\(tradeID.uuidString)/thesis", method: "PUT",
            body: JSONEncoder().encode(["body": text]), expectedAccountID: accountID)
        try result.validate(tradeID: tradeID)
        return result
    }

    func likeThesis(tradeID: UUID, liked: Bool, accountID: UUID) async throws -> TradeThesis {
        let result: TradeThesis = try await request("/theses/\(tradeID.uuidString)/like", method: "PUT",
            body: JSONEncoder().encode(["liked": liked]), expectedAccountID: accountID)
        try result.validate(tradeID: tradeID)
        guard result.likedByMe == liked else { throw BSmartAPIError.invalidResponse }
        return result
    }
}

struct TradeThesisChange {
    let accountID: UUID
    let thesis: TradeThesis
}

extension Notification.Name {
    static let bSmartTradeThesisUpdated = Notification.Name("bSmartTradeThesisUpdated")
}
