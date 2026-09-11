import Foundation

struct SmartAccountFirstOpinion: Codable, Hashable {
    let publishedAt: Date
    let direction: SignalDirection
    let priceBasis: String
    var price: Double? = nil
    var priceDay: String? = nil
    var priceSource: String? = nil
    var sourcePostId: String? = nil
    var evidenceURL: URL? = nil

    var referencePrice: Double? {
        guard priceBasis == "last_completed_daily_close", let price, price.isFinite, price > 0,
              let priceDay, !priceDay.isEmpty else { return nil }
        return price
    }
}

struct SmartAccountRepresentativeIntro: Codable, Hashable {
    let evidenceId: UUID
    let authorId: String
    let platform: String
    let ticker: String
    let direction: SignalDirection
    let publishedAt: Date
    let horizon: String
    var stockReturnPercent: Double? = nil
    var firstOpinion: SmartAccountFirstOpinion? = nil
    var entryDay: String? = nil
    var entryPrice: Double? = nil
    var exitDay: String? = nil
}
