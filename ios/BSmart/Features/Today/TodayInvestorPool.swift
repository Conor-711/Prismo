import Foundation

/// Editorial placement only: preserve eligibility, identity, and every published rank.
enum TodayInvestorPool {
    // The existing X account behind @aleabitoreddit; names never merge identities.
    static let preferredID = "x:1940360837547565056"

    static func arranged(
        _ candidates: [TodayInvestorDiscovery.Investor],
        hasBullishWork: (TodayInvestorDiscovery.Investor) -> Bool = {
            TodayRepresentativeStoryBundle.bundled?.story(for: $0.account) != nil
        }
    ) -> [TodayInvestorDiscovery.Investor] {
        let ordered = candidates.filter(hasAvatar) + candidates.filter { !hasAvatar($0) }
        guard let first = ordered.first(where: { $0.id == preferredID }) ?? ordered.first else { return [] }
        let youtube = Array(ordered.filter {
            $0.id.hasPrefix("youtube:") && hasAvatar($0) && $0.id != first.id
        }.prefix(3))
        let reddit = Array(ordered.filter {
            $0.id.hasPrefix("reddit:") && hasAvatar($0) && $0.id != first.id
        }.prefix(1))
        // Preserve the fifth-slot Reddit account and move the second YouTube account to fourth.
        let replacement = ordered.first {
            $0.id.hasPrefix("reddit:") && hasAvatar($0) && $0.id != first.id
                && $0.id != reddit.first?.id && hasBullishWork($0)
        }
        let result: [TodayInvestorDiscovery.Investor]
        if youtube.count >= 2, let replacement {
            result = [youtube[0], replacement, first, youtube[1]] + reddit
        } else {
            result = Array(youtube.prefix(2)) + [first] + Array(youtube.dropFirst(2)) + reddit
        }
        let displayed = Set(result.map(\.id))
        return result + ordered.filter { !displayed.contains($0.id) }
    }

    private static func hasAvatar(_ investor: TodayInvestorDiscovery.Investor) -> Bool {
        investor.account.avatarURL != nil
            || RedditAuthorAvatars.url(forDisplayName: investor.account.name) != nil
    }

    static func topPercent(_ investor: TodayInvestorDiscovery.Investor) -> Int {
        max(1, Int(ceil(investor.account.resolvedPlatformPercentile * 100)))
    }
}
