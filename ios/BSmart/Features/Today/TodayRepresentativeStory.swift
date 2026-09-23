import Foundation

/// A retrospective price story, not a new Score or the author's trading return.
struct TodayRepresentativeStory: Codable {
    struct Call: Identifiable, Codable {
        let id: UUID
        let publishedAt: Date
        let day: String
        let price: Double
        let priceDay: String
        let direction: SignalDirection
        let sourceURL: URL
        var original: SmartAccountUpdate? = nil
        let summary: String?
        var horizon: String? = nil
        // Full source documents already ship in the evidence fixture; do not duplicate them per story.
        enum CodingKeys: String, CodingKey {
            case id, publishedAt, day, price, priceDay, direction, sourceURL, summary, horizon
        }
    }

    struct Price: Identifiable, Codable {
        var id: String { day }
        let day: String
        let time: Date
        let value: Double
    }

    let account: SmartAccountProfile
    let ticker: String
    let calls: [Call]
    let prices: [Price]
    let peak: Price
    let source: String
    let cutoff: String
    var bundledChineseCopy: String? = nil
    var bundledEnglishCopy: String? = nil

    var earliestCalls: [Call] { Array(calls.filter { $0.direction == .bullish }.prefix(3)) }
    var anchor: Call { earliestCalls[0] }
    var bullishCount: Int { calls.filter { $0.direction == .bullish }.count }
    var bearishCount: Int { calls.filter { $0.direction == .bearish }.count }
    var peakChange: Double { (peak.value / anchor.price - 1) * 100 }

    init?(account: SmartAccountProfile, intro: SmartAccountRepresentativeIntro?,
          evidence: [SmartAccountUpdate], now: Date = Date()) {
        guard let intro, intro.direction == .bullish,
              TodayInvestorDiscovery.identity(intro.authorId, platform: intro.platform)
                == TodayInvestorDiscovery.identity(account.id, platform: account.platform),
              let first = intro.firstOpinion, first.direction == .bullish,
              first.publishedAt <= intro.publishedAt, intro.publishedAt <= now,
              let firstPrice = first.referencePrice, let firstPriceDay = first.priceDay,
              let firstURL = first.evidenceURL, Self.isPublicSource(firstURL), Self.belongs(firstURL, to: account),
              account.platform.lowercased() != "x" || first.sourcePostId == nil || Self.postID(firstURL) == first.sourcePostId
        else { return nil }
        let clock = TodayRepresentativeStoryClock()
        guard clock.isRecentClose(firstPriceDay, before: first.publishedAt) else { return nil }
        let identity = TodayInvestorDiscovery.identity(account.id, platform: account.platform)
        let matching = evidence.filter {
            TodayInvestorDiscovery.identity($0.authorId, platform: $0.platform) == identity
                && $0.ticker.caseInsensitiveCompare(intro.ticker) == .orderedSame
                && $0.publishedAt <= now
        }
        let priceRecords = matching.filter {
            $0.priceEvidence?.ticker.caseInsensitiveCompare(intro.ticker) == .orderedSame
        }.sorted { lhs, rhs in
            if (lhs.id == intro.evidenceId) != (rhs.id == intro.evidenceId) { return lhs.id == intro.evidenceId }
            return (lhs.priceEvidence?.candles.count ?? 0) > (rhs.priceEvidence?.candles.count ?? 0)
        }
        guard let history = priceRecords.first?.priceEvidence else { return nil }
        var uniqueCandles: [String: PriceCandle] = [:]
        for candle in history.candles where clock.valid(candle) && clock.isCompleted(candle.day, before: now) {
            uniqueCandles[candle.day] = candle
        }
        let candles = uniqueCandles.values.sorted { $0.day < $1.day }
        let firstDay = clock.day(first.publishedAt)
        let subsequent = candles.filter { $0.day > firstDay }
        guard let last = subsequent.last,
              let highest = subsequent.max(by: { $0.high < $1.high }),
              let peakTime = clock.date(highest.day), let startTime = clock.date(firstPriceDay)
        else { return nil }

        let firstOriginal = matching.first { Self.sourceKey($0.sourceURL ?? $0.evidenceURL) == Self.sourceKey(firstURL) }
        let firstMarker = matching.flatMap { $0.priceEvidence?.opinionMarkers ?? [] }
            .first { Self.sourceKey($0.evidenceURL) == Self.sourceKey(firstURL) }
        let initial = Call(id: intro.evidenceId, publishedAt: first.publishedAt, day: firstDay,
            price: firstPrice, priceDay: firstPriceDay, direction: .bullish, sourceURL: firstURL,
            original: firstOriginal, summary: firstOriginal?.thesis ?? firstMarker?.thesis,
            horizon: firstOriginal?.horizon ?? firstMarker?.horizon)
        var uniqueCalls = [Self.sourceKey(firstURL): initial]
        func append(id: UUID, date: Date, direction: SignalDirection, url: URL?, original: SmartAccountUpdate?, summary: String, horizon: String) {
            guard direction == .bullish || direction == .bearish,
                  date >= first.publishedAt, date <= now, clock.day(date) <= last.day,
                  let url, Self.isPublicSource(url), Self.belongs(url, to: account),
                  let candle = candles.last(where: { clock.isCompleted($0.day, before: date) }),
                  clock.isRecentClose(candle.day, before: date)
            else { return }
            let key = Self.sourceKey(url)
            guard key != Self.sourceKey(firstURL) else { return }
            if uniqueCalls[key]?.original != nil && original == nil { return }
            uniqueCalls[key] = Call(id: id, publishedAt: date, day: clock.day(date), price: candle.close,
                priceDay: candle.day, direction: direction, sourceURL: url, original: original, summary: summary, horizon: horizon)
        }
        for update in matching {
            for marker in update.priceEvidence?.opinionMarkers ?? [] {
                append(id: marker.id, date: marker.publishedAt, direction: marker.direction,
                       url: marker.evidenceURL, original: nil, summary: marker.thesis, horizon: marker.horizon)
            }
            append(id: update.id, date: update.publishedAt, direction: update.direction,
                   url: update.sourceURL ?? update.evidenceURL, original: update, summary: update.thesis, horizon: update.horizon)
        }
        self.account = account
        ticker = intro.ticker
        calls = uniqueCalls.values.sorted {
            $0.publishedAt != $1.publishedAt ? $0.publishedAt < $1.publishedAt : $0.id.uuidString < $1.id.uuidString
        }
        prices = [Price(day: firstPriceDay, time: startTime, value: firstPrice)] + candles.filter { $0.day > firstPriceDay }.compactMap {
            guard let time = clock.date($0.day) else { return nil }
            return Price(day: $0.day, time: time, value: $0.close)
        }
        peak = Price(day: highest.day, time: peakTime, value: highest.high)
        source = history.source
        cutoff = last.day
        guard peakChange.isFinite else { return nil }
    }

    private static func isPublicSource(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil
    }

    private static func postID(_ url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "status"), parts.indices.contains(index + 1) else { return nil }
        return parts[index + 1]
    }

    static func sourceKey(_ url: URL?) -> String {
        guard let url else { return "" }
        if let id = postID(url), ["x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased()) {
            return "x:\(id)"
        }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.url?.absoluteString ?? url.absoluteString
    }

    private static func belongs(_ url: URL, to account: SmartAccountProfile) -> Bool {
        guard account.platform.lowercased() == "x" else { return true }
        guard ["x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased()),
              url.pathComponents.count >= 4, url.pathComponents[2] == "status" else { return false }
        let owner = url.pathComponents[1].lowercased()
        return owner == account.id.lowercased() || owner == account.handle.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }
}

private struct TodayRepresentativeStoryClock {
    private let dayFormatter: DateFormatter
    private let utcFormatter: DateFormatter
    private let calendar: Calendar

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        self.calendar = calendar
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = calendar.timeZone
        day.dateFormat = "yyyy-MM-dd"
        dayFormatter = day
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.dateFormat = "yyyy-MM-dd"
        utc.isLenient = false
        utcFormatter = utc
    }

    func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    func date(_ day: String) -> Date? {
        guard let value = utcFormatter.date(from: day), utcFormatter.string(from: value) == day else { return nil }
        return value
    }
    func isCompleted(_ day: String, before publishedAt: Date) -> Bool {
        guard let priceDate = date(day), let publishedDay = date(self.day(publishedAt)),
              publishedDay.timeIntervalSince(priceDate) >= 0 else { return false }
        return day < self.day(publishedAt) || calendar.component(.hour, from: publishedAt) >= 16
    }
    func isRecentClose(_ day: String, before publishedAt: Date) -> Bool {
        guard isCompleted(day, before: publishedAt), let value = date(day),
              let publication = date(self.day(publishedAt)) else { return false }
        return publication.timeIntervalSince(value) <= 7 * 86_400
    }
    func valid(_ candle: PriceCandle) -> Bool {
        date(candle.day) != nil && [candle.open, candle.high, candle.low, candle.close].allSatisfy { $0.isFinite && $0 > 0 }
            && candle.low <= min(candle.open, candle.close) && candle.high >= max(candle.open, candle.close)
    }
}
