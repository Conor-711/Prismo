import SwiftUI

/// Uses the standard opinion screen; a marker summary is never promoted to original text.
struct TodayRepresentativeOpinionDestination: View {
    let story: TodayRepresentativeStory
    let call: TodayRepresentativeStory.Call
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SmartAccountEvidenceDetailView(
            update: Self.resolve(story: story, call: call,
                evidence: model.accountEvidence(for: story.account) + model.accountUpdates(for: story.account)),
            priceContextNote: [
                "Prices use the last completed daily close before each post, not a verified purchase. The later high excludes the first post's trading day. This is the stock's historical rise, not the author's realized return.".bSmartLocalized,
                "These are available records, not every post by this author. The chart marks at most the earliest three bullish views in these records.".bSmartLocalized,
                "%@ · Through %@".bSmartLocalized(story.source, TodayRepresentativeStoryCopy.day(story.cutoff))
            ].joined(separator: "\n\n")
        )
        .task { await model.loadSmartAccountEvidence(for: story.account) }
    }

    static func resolve(story: TodayRepresentativeStory, call: TodayRepresentativeStory.Call,
                        evidence: [SmartAccountUpdate]) -> SmartAccountUpdate {
        let identity = TodayInvestorDiscovery.identity(story.account.id, platform: story.account.platform)
        if let full = evidence.first(where: {
            TodayInvestorDiscovery.identity($0.authorId, platform: $0.platform) == identity
                && $0.ticker.caseInsensitiveCompare(story.ticker) == .orderedSame
                && TodayRepresentativeStory.sourceKey($0.sourceURL ?? $0.evidenceURL)
                    == TodayRepresentativeStory.sourceKey(call.sourceURL)
        }) { return full }
        if let original = call.original { return original }
        return SmartAccountUpdate(id: call.id, ticker: story.ticker,
            companyName: story.ticker,
            authorId: story.account.id, authorName: story.account.name, platform: story.account.platform,
            score: story.account.score, platformPercentile: story.account.resolvedPlatformPercentile,
            direction: call.direction, lifecycle: .new, horizon: call.horizon ?? "unknown", targetPrice: nil,
            thesis: call.summary ?? "", invalidation: nil, publishedAt: call.publishedAt,
            evidenceURL: call.sourceURL, authorAvatarURL: story.account.avatarURL,
            authorFollowersCount: story.account.followersCount, sourceURL: call.sourceURL)
    }
}
