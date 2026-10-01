import Foundation

extension NativeTradeFeedClient {
    // Already verified trades must not depend on a second exchange sync succeeding.
    func activityForWriting(cloid: String, accountID: UUID) async throws -> TradeFeedItem {
        try await TradeThesisVerificationWait.load(
            read: { try await activity(cloid: cloid, accountID: accountID) },
            synchronize: { _ = try await synchronize(accountID: accountID, cloid: cloid) })
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

@MainActor
enum TradeThesisVerificationWait {
    static func load<Value>(read: () async throws -> Value, synchronize: () async throws -> Void,
                           pause: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> Value {
        // Another verifier may hold the lease. Re-read only this order; never resubmit it.
        let delays: [Duration] = [.seconds(1), .seconds(3), .seconds(6)]
        for attempt in 0...delays.count {
            try Task.checkCancellation()
            do { return try await read() }
            catch TradeThesisError.pending {
                do { try await synchronize() }
                catch AccountAccessError.unavailable { /* A transient read-side failure can recover. */ }
                catch TradeThesisError.unavailable { }
                do { return try await read() }
                catch TradeThesisError.pending {
                    guard attempt < delays.count else { throw TradeThesisError.pending }
                    try await pause(delays[attempt])
                }
            }
        }
        throw TradeThesisError.pending
    }
}

struct TradeThesisChange {
    let accountID: UUID
    let thesis: TradeThesis
}

extension Notification.Name {
    static let bSmartTradeThesisUpdated = Notification.Name("bSmartTradeThesisUpdated")
    static let bSmartNativeInvestorChanged = Notification.Name("bSmartNativeInvestorChanged")
}
