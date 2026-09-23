import SwiftUI

struct TodayRepresentativeStoryCard: View {
    let story: TodayRepresentativeStory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BSmartDetailNavigationLink(id: "story-\(story.account.id)-\(story.ticker)") {
                TodayRepresentativeOpinionDestination(story: story, call: story.anchor)
            } label: {
                HStack(spacing: 10) {
                    BSmartAssetMark(ticker: story.ticker, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Market highlight".bSmartLocalized)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BSmartColor.brand)
                        Text(story.ticker)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text((story.peakChange > 0 ? "+" : "") + TodayRepresentativeStoryCopy.percent(story.peakChange))
                            .font(.title2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(story.peakChange > 0 ? BSmartColor.bull : BSmartColor.secondaryText)
                        Text("Peak rise".bSmartLocalized)
                            .font(.caption2).foregroundStyle(BSmartColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("discovery.story.peak-gain")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 60)
                .background(BSmartColor.brand.opacity(0.08))
                .overlay(alignment: .leading) {
                    Rectangle().fill(BSmartColor.brand).frame(width: 3)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("discovery.story.open")
            VStack(spacing: 0) {
                TodayRepresentativeStoryChart(story: story) { call, index in
                    BSmartDetailNavigationLink(id: "story-node-\(call.id)") {
                        TodayRepresentativeOpinionDestination(story: story, call: call)
                    } label: { TodayRepresentativeStoryNode(index: index) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bullish view %d · %@ · %@".bSmartLocalized(index,
                        TodayRepresentativeStoryCopy.day(call.day), TodayRepresentativeStoryCopy.chartPrice(call.price)))
                    .accessibilityIdentifier("discovery.story.node.\(index)")
                }
            }
            .padding(.top, 8)
            .background(BSmartColor.chartPlot)
        }
        .padding(.top, 2).padding(.bottom, 4)
        .foregroundStyle(BSmartColor.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discovery.highlight")
    }
}
