import SwiftUI

struct OnboardingDiscoveryPage: View {
    let story: TodayRepresentativeStory?
    let onSelectCall: (TodayRepresentativeStory.Call) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: InvestorEducationSnapshot?
    @State private var artwork: InvestorEducationArtwork?
    @State private var hasFocusedPool = false

    var body: some View {
        OnboardingPageFrame(
            step: 1,
            title: "Find investors worth following"
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: BSmartSpacing.large) {
                    selectionPool
                    if let story {
                        representativeWork(story)
                    } else {
                        unavailable
                    }
                }
                .padding(.bottom, BSmartSpacing.small)
            }
        }
        .task {
            guard snapshot == nil else { return }
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    try InvestorEducationSnapshot.load()
                }.value
                guard !Task.isCancelled else { return }
                snapshot = value
                artwork = InvestorEducationArtwork(snapshot: value)
                withAnimation(reduceMotion ? nil : .smooth(duration: 1.0)) {
                    hasFocusedPool = true
                }
            } catch {
                hasFocusedPool = true
            }
        }
    }

    @ViewBuilder
    private var selectionPool: some View {
        if let snapshot,
           let artwork,
           let platform = snapshot.platforms.first(where: { $0.id == "x" }),
           let author = platform.authors.first(where: { $0.id == OnboardingFeaturedStory.authorID }) {
            OnboardingInvestorSelectionPool(
                platform: platform,
                artwork: artwork,
                author: author,
                story: story,
                focused: hasFocusedPool
            )
        } else {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .fill(BSmartColor.surface)
                .frame(height: 208)
                .overlay { ProgressView().tint(BSmartColor.brand) }
        }
    }

    private func representativeWork(_ story: TodayRepresentativeStory) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartAssetMark(ticker: story.ticker, size: 30)
                Text(story.ticker)
                    .font(.headline.weight(.black))
                Text("Representative work".bSmartLocalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Text("+" + TodayRepresentativeStoryCopy.percent(story.peakChange))
                    .font(.title3.weight(.black))
                    .foregroundStyle(BSmartColor.bull)
                    .monospacedDigit()
            }

            TodayRepresentativeStoryChart(story: story) { call, index in
                Button { onSelectCall(call) } label: {
                    BSmartAvatar(
                        url: story.account.avatarURL,
                        name: story.account.name,
                        size: 32,
                        fallbackColor: BSmartColor.brand
                    )
                    .overlay { Circle().stroke(BSmartColor.brand, lineWidth: 2) }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bullish view %d · %@ · %@".bSmartLocalized(
                    index,
                    TodayRepresentativeStoryCopy.day(call.day),
                    TodayRepresentativeStoryCopy.chartPrice(call.price)
                ))
                .accessibilityIdentifier("onboarding.story.node.\(index)")
            }

            Text("Peak stock move after first view".bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
        }
        .padding(BSmartSpacing.medium)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
        .accessibilityIdentifier("onboarding.representative-work")
    }

    private var unavailable: some View {
        Label(
            "Representative work is unavailable".bSmartLocalized,
            systemImage: "chart.line.uptrend.xyaxis"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(BSmartColor.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
    }
}

private struct OnboardingInvestorSelectionPool: View {
    let platform: InvestorEducationSnapshot.Platform
    let artwork: InvestorEducationArtwork
    let author: InvestorEducationSnapshot.Author
    let story: TodayRepresentativeStory?
    let focused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            InvestorEducationPool(
                platform: platform,
                tiles: artwork.tiles,
                progress: focused ? 1 : 0
            )
            .frame(height: 208)
            .scaleEffect(focused ? 1.03 : 1)
            .opacity(focused ? 0.44 : 0.72)
            .mask {
                LinearGradient(
                    colors: [.black, .black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            HStack(spacing: BSmartSpacing.medium) {
                Group {
                    if let image = artwork.tiles[author.tile] {
                        image.resizable().scaledToFill()
                    } else {
                        BSmartAvatar(
                            url: story?.account.avatarURL,
                            name: author.name,
                            size: 52,
                            fallbackColor: BSmartColor.brand
                        )
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay { Circle().stroke(BSmartColor.brand, lineWidth: 2) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(author.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)
                    Text(story?.account.handle ?? "@aleabitoreddit")
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                Spacer(minLength: 4)
                Text("X · Top \(max(1, Int(ceil((story?.account.resolvedPlatformPercentile ?? 0.15) * 100))))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.brand)
            }
            .padding(BSmartSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSmartColor.surface.opacity(0.96))
        }
        .frame(height: 208)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.investor-pool")
    }
}
