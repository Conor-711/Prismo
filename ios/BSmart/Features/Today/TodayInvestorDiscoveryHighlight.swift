import Foundation

/// Use the existing representative-work order, not the largest return as a new ranking.
struct TodayInvestorDiscoveryHighlight {
    let work: SmartAccountUpdate?
    let intro: SmartAccountRepresentativeIntro?

    init(account: SmartAccountProfile, representatives: [SmartAccountUpdate], now: Date = Date()) {
        let identity = TodayInvestorDiscovery.identity(account.id, platform: account.platform)
        work = representatives.first {
            TodayInvestorDiscovery.identity($0.authorId, platform: $0.platform) == identity
                && $0.publishedAt <= now
                && $0.evidenceRole?.lowercased() != "latest"
                && $0.settlement?.status.lowercased() == "settled"
                && !$0.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let supplied = account.representativeWork
        if let supplied,
           TodayInvestorDiscovery.identity(supplied.authorId, platform: supplied.platform) == identity,
           supplied.direction == .bullish || supplied.direction == .bearish,
           supplied.publishedAt <= now, !supplied.ticker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intro = supplied
        } else if let work {
            intro = SmartAccountRepresentativeIntro(evidenceId: work.id, authorId: work.authorId,
                platform: work.platform, ticker: work.ticker, direction: work.direction,
                publishedAt: work.publishedAt, horizon: work.settlement?.horizon ?? "unknown",
                stockReturnPercent: work.settlement?.tickerReturnPercent, firstOpinion: work.firstOpinion)
        } else {
            intro = nil
        }
    }

    var stockReturn: Double? {
        guard let value = intro?.stockReturnPercent, value.isFinite else { return nil }
        return value
    }

    var tradingSessions: Int? {
        guard let horizon = intro?.horizon.uppercased(), horizon.hasSuffix("D"),
              let days = Int(horizon.dropLast()), days > 0 else { return nil }
        return days
    }

    var firstOpinion: SmartAccountFirstOpinion? {
        guard let intro, let first = intro.firstOpinion, first.publishedAt <= intro.publishedAt,
              first.direction == intro.direction else { return nil }
        return first
    }
}
