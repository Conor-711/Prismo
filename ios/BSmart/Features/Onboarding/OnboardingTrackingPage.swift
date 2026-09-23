import SwiftUI

struct OnboardingTrackingPage: View {
    let story: TodayRepresentativeStory?
    let isFollowing: Bool
    let onToggleFollow: () -> Void

    var body: some View {
        OnboardingPageFrame(
            step: 2,
            title: "See how they think"
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: BSmartSpacing.large) {
                    if let story {
                        authorRow(story)
                        latestView(story)
                    } else {
                        ContentUnavailableView(
                            "Unable to load".bSmartLocalized,
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                    }
                }
                .padding(.bottom, BSmartSpacing.small)
            }
        }
    }

    private func authorRow(_ story: TodayRepresentativeStory) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAvatar(
                url: story.account.avatarURL,
                name: story.account.name,
                size: 52,
                fallbackColor: BSmartColor.brand
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(story.account.name)
                    .font(.headline.weight(.black))
                Text("X · \(story.account.handle)")
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer(minLength: 6)
            Button(action: onToggleFollow) {
                Label(
                    (isFollowing ? "Tracking" : "Track").bSmartLocalized,
                    systemImage: isFollowing ? "checkmark" : "plus"
                )
                .font(.caption.weight(.bold))
                .padding(.horizontal, 11)
                .frame(minHeight: 38)
                .foregroundStyle(isFollowing ? BSmartColor.onAccent : BSmartColor.brand)
                .background(isFollowing ? BSmartColor.brand : BSmartColor.brand.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.follow-featured")
        }
    }

    private func latestView(_ story: TodayRepresentativeStory) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: 6) {
                Text("\(story.ticker) · " + "Bullish".bSmartLocalized)
                    .foregroundStyle(BSmartColor.bull)
                Text("·")
                    .foregroundStyle(BSmartColor.tertiaryText)
                Text(OnboardingFeaturedStory.latestViewDay)
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                BSmartAssetMark(ticker: story.ticker, size: 28)
            }
            .font(.caption.weight(.bold))

            Text(OnboardingFeaturedStory.latestViewTitle.bSmartLocalized)
                .font(.title3.weight(.black))
                .foregroundStyle(BSmartColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("“\(OnboardingFeaturedStory.latestViewQuote.bSmartLocalized)”")
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BSmartSpacing.large)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
        .accessibilityIdentifier("onboarding.latest-view")
    }
}
