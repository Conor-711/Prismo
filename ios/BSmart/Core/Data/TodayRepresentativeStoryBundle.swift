import Foundation

/// Offline snapshot IO is owned by the data layer, not the card views.
struct TodayRepresentativeStoryBundle: Codable {
    static let version = 2
    let formatVersion: Int
    let generatedAt: Date
    let introductions: [SmartAccountRepresentativeIntro]
    let stories: [TodayRepresentativeStory]

    static let bundled: TodayRepresentativeStoryBundle? = {
        guard let url = Bundle.main.url(forResource: "representative-stories", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let value = try? PropertyListDecoder().decode(Self.self, from: data),
              value.formatVersion == version else { return nil }
        return value
    }()

    func story(for account: SmartAccountProfile) -> TodayRepresentativeStory? {
        guard let intro = account.representativeWork,
              let story = stories.first(where: {
                  $0.anchor.id == intro.evidenceId && $0.ticker == intro.ticker
                      && TodayInvestorDiscovery.identity($0.account.id, platform: $0.account.platform)
                        == TodayInvestorDiscovery.identity(account.id, platform: account.platform)
              }), intro.firstOpinion?.referencePrice == story.anchor.price,
              intro.firstOpinion?.publishedAt == story.anchor.publishedAt else { return nil }
        return story
    }
}
