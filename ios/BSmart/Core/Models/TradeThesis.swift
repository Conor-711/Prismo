import Foundation

struct TradeThesis: Codable, Identifiable, Hashable {
    let id: UUID
    let body: String
    let publishedAt: Date
    let likeCount: Int
    let likedByMe: Bool

    static func validBody(_ body: String) -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.unicodeScalars.count <= 1000
            && !text.unicodeScalars.contains { scalar in
                (scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13)
                    || (127...159).contains(scalar.value)
            }
    }

    func validate(tradeID: UUID, executedAt: Date? = nil, now: Date = Date()) throws {
        guard id == tradeID, Self.validBody(body), likeCount >= 0,
              !likedByMe || likeCount > 0,
              publishedAt <= now.addingTimeInterval(60),
              executedAt == nil || publishedAt >= executedAt! else { throw BSmartAPIError.invalidResponse }
    }
}

enum TradeThesisError: String, Error {
    case notReady = "thesis_not_ready"
    case pending = "trade_pending"
    case exists = "thesis_exists"
    case invalid = "invalid_input"
    case own = "own_thesis"
    case missing = "not_found"
    case unavailable = "feed_unavailable"

    var message: String {
        switch self {
        case .notReady: "Thesis publishing is not available yet. Please try again later.".bSmartLocalized
        case .pending: "Trade verification is pending. Try again shortly.".bSmartLocalized
        case .exists: "A thesis is already published for this trade. Refresh to view it.".bSmartLocalized
        case .invalid: "Write a thesis of 1–1000 characters.".bSmartLocalized
        case .own: "You cannot like your own thesis.".bSmartLocalized
        case .missing: "This trade thesis is unavailable.".bSmartLocalized
        case .unavailable: "Could not update the thesis. Please try again.".bSmartLocalized
        }
    }
}
