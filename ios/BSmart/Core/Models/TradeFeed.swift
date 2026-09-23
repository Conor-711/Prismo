import Foundation

struct FeedPublicProfile: Codable, Identifiable, Hashable {
    let id: UUID
    let nickname: String
    let avatarURL: URL?
    var handle: String? = nil
    var bio: String? = nil

    var isValid: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nickname.count <= 28
            && (avatarURL == nil || avatarURL?.scheme == "https")
            && (handle == nil || AccountProfile.validHandle(handle!))
            && (bio == nil || bio!.unicodeScalars.count <= 120)
    }
}

struct TradeFeedItem: Codable, Identifiable, Hashable {
    let id: UUID
    let trader: FeedPublicProfile
    let opinion: SmartAccountUpdate
    let side: PaperTradeSide
    let notionalUSD: String
    let marketCoin: String
    let executedAt: Date
    var thesis: TradeThesis? = nil
    var canPublishThesis: Bool? = nil
    var canLikeThesis: Bool? = nil

    var notional: Decimal? { Decimal(string: notionalUSD, locale: Locale(identifier: "en_US_POSIX")) }
    var amountLabel: String {
        guard let notional else { return "—" }
        return notional.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))
            .precision(.fractionLength(0...2)))
    }
    var source: OpinionTradeSource {
        .init(opinionID: opinion.id, ticker: opinion.ticker, feedEventID: id, authorID: opinion.authorId)
    }

    func validate(now: Date = Date()) throws {
        guard trader.isValid, let notional, notional > 0, notionalUSD.count <= 64,
              notionalUSD.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              !marketCoin.isEmpty, marketCoin.count <= 64,
              !opinion.ticker.isEmpty, !opinion.authorId.isEmpty, !opinion.authorName.isEmpty,
              (0...1).contains(opinion.platformPercentile)
                && (opinion.platformPercentile <= 0.25 || thesis != nil || canPublishThesis == true),
              opinion.publishedAt <= executedAt, executedAt <= now.addingTimeInterval(60) else {
            throw BSmartAPIError.invalidResponse
        }
        if let thesis {
            try thesis.validate(tradeID: id, executedAt: executedAt, now: now)
            guard canPublishThesis != true else { throw BSmartAPIError.invalidResponse }
        }
    }
}

struct TradeFeedPage: Codable {
    let items: [TradeFeedItem]
    let nextOffset: Int?

    func validate(offset: Int) throws {
        guard offset >= 0, items.count <= 50, Set(items.map(\.id)).count == items.count,
              nextOffset == nil || (!items.isEmpty && nextOffset == offset + items.count) else {
            throw BSmartAPIError.invalidResponse
        }
        for item in items { try item.validate() }
        for pair in zip(items, items.dropFirst()) where pair.0.executedAt < pair.1.executedAt {
            throw BSmartAPIError.invalidResponse
        }
    }
}
