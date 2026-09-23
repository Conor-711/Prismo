import SwiftUI

struct OnboardingTradePage: View {
    let story: TodayRepresentativeStory?
    let sample: OnboardingTradeDraft
    let onPreview: () -> Void

    var body: some View {
        OnboardingPageFrame(
            step: 3,
            title: "From view to trade"
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                if let story {
                    sampleOrder(story)
                        .padding(.bottom, BSmartSpacing.small)
                }
            }
        }
    }

    private func sampleOrder(_ story: TodayRepresentativeStory) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.large) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartAvatar(
                    url: story.account.avatarURL,
                    name: story.account.name,
                    size: 36,
                    fallbackColor: BSmartColor.brand
                )
                Text("%@ · %@ bullish".bSmartLocalized(story.account.name, story.ticker))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
            }

            Divider().overlay(BSmartColor.line)

            HStack(spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: story.ticker, size: 42)
                Text(story.ticker)
                    .font(.title3.weight(.bold))
                Spacer()
                Text("Long".bSmartLocalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.bull)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Sample margin".bSmartLocalized)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Text(OnboardingMoney.string(sample.margin))
                    .font(.title2.weight(.bold).monospacedDigit())
            }

            Button(action: onPreview) {
                HStack {
                    Text("Review sample order".bSmartLocalized)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, BSmartSpacing.medium)
                .frame(maxWidth: .infinity, minHeight: 46)
                .bSmartActionSurface(cornerRadius: BSmartRadius.control)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.trade-preview")

            Text("Preview only. Leveraged trading can be liquidated.".bSmartLocalized)
                .font(.caption)
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
    }
}

struct OnboardingOrderPreview: View {
    let story: TodayRepresentativeStory
    let margin: Double
    let leverage: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                HStack(spacing: BSmartSpacing.medium) {
                    BSmartAssetMark(ticker: story.ticker, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("%@ · Long".bSmartLocalized(story.ticker))
                            .font(.title2.weight(.black))
                        Text("Perpetual contract".bSmartLocalized)
                            .font(.caption)
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                }

                previewRow("Margin", OnboardingMoney.string(margin))
                previewRow("Leverage", "\(leverage)×")
                previewRow("Position size", OnboardingMoney.string(margin * Double(leverage)))

                Text("This preview does not create or send an order.".bSmartLocalized)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
                Button("Back to the opinion".bSmartLocalized) { dismiss() }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .bSmartActionSurface(cornerRadius: BSmartRadius.control)
            }
            .padding(BSmartSpacing.xLarge)
            .background(BSmartColor.ink.ignoresSafeArea())
            .navigationTitle("Order preview".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("onboarding.order-preview")
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.bSmartLocalized)
                .foregroundStyle(BSmartColor.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
        }
    }
}

struct OnboardingCallPreview: View {
    let story: TodayRepresentativeStory
    let call: TodayRepresentativeStory.Call

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                HStack(spacing: BSmartSpacing.medium) {
                    BSmartAvatar(
                        url: story.account.avatarURL,
                        name: story.account.name,
                        size: 48,
                        fallbackColor: BSmartColor.brand
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(story.account.name)
                            .font(.headline.weight(.black))
                        Text("%@ · %@".bSmartLocalized(
                            TodayRepresentativeStoryCopy.day(call.day),
                            TodayRepresentativeStoryCopy.chartPrice(call.price)
                        ))
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                    }
                }

                Text("%@ · Bullish".bSmartLocalized(story.ticker))
                    .font(.title2.weight(.black))
                Text(call.summary ?? "This public view is recorded on the price timeline.".bSmartLocalized)
                    .font(.body)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: call.sourceURL) {
                    Label("View original source".bSmartLocalized, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }

                Spacer()
                Button("Done".bSmartLocalized) { dismiss() }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .bSmartActionSurface(cornerRadius: BSmartRadius.control)
            }
            .padding(BSmartSpacing.xLarge)
            .background(BSmartColor.ink.ignoresSafeArea())
            .navigationTitle("Public view".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("onboarding.call-preview")
    }
}
