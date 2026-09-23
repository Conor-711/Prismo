import SwiftUI

struct OpinionDetailLayout<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var trading: HyperliquidTradingStore
    let update: SmartAccountUpdate
    @ViewBuilder let content: () -> Content
    @State private var collapsed = false
    @State private var quote: HyperliquidPerpMarket?
    @State private var showsChatShare = false

    private var sharedContent: SocialSharedContent {
        let profile = model.smartAccountProfile(for: update)
        let rank = profile.resolvedRank > 0 ? "#\(profile.resolvedRank) · " : ""
        let percentile = max(1, Int(ceil(update.platformPercentile * 100)))
        let summary = OpinionReadingContent(update: update, chinese: BSmartLocalization.isSimplifiedChinese).summary
            ?? update.thesis
        return .init(kind: .opinion, id: update.id.uuidString.lowercased(),
                     title: SocialSharedContent.clipped(update.authorName, utf16Limit: 100),
                     detail: SocialSharedContent.clipped("\(rank)Top \(percentile)% · \(update.platform)", utf16Limit: 120),
                     summary: SocialSharedContent.clipped(summary, utf16Limit: 300), ticker: update.ticker.uppercased(),
                     publishedAt: ISO8601DateFormatter().string(from: update.publishedAt),
                     avatarURL: SocialSharedContent.shareableAvatarURL(update.authorAvatarURL ?? profile.avatarURL))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    OpinionPortraitHeader(update: update,
                        avatarURL: update.authorAvatarURL ?? model.smartAccountProfile(for: update).avatarURL,
                        width: geometry.size.width) { next in
                            if collapsed != next { collapsed = next }
                        }
                    VStack(alignment: .leading, spacing: 20) {
                        attribution
                        content()
                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .top)
            .coordinateSpace(name: "opinion.detail.scroll")
            .accessibilityIdentifier("opinion.detail.scroll")
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(BSmartColor.ink)
        .navigationTitle(collapsed ? update.ticker : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(collapsed ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BSmartIconButton(symbol: "paperplane.fill", accessibilityLabel: "Share",
                                 color: BSmartColor.brand) { showsChatShare = true }
                    .accessibilityIdentifier("opinion.share")
            }
        }
        .sheet(isPresented: $showsChatShare) { ShareToChatSheet(content: sharedContent) }
        .task(id: update.ticker) {
            quote = nil
            while !Task.isCancelled {
                let latest = await trading.opinionQuote(for: update.ticker)
                guard !Task.isCancelled else { return }
                quote = latest
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 10) {
            source
            HStack(alignment: .center, spacing: 12) {
                assetIdentity
                Spacer(minLength: 8)
                price
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("opinion.identity")
    }

    private var source: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SmartPlatformMark(platform: update.platform, size: 18)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(update.authorName).font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
                .accessibilityIdentifier("opinion.author-name")
            Spacer(minLength: 4)
            time
        }
        .foregroundStyle(BSmartColor.primaryText)
    }

    private var assetIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(update.ticker)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("opinion.ticker")
                BSmartTag(text: update.direction.label, color: update.direction.color)
                    .accessibilityIdentifier("opinion.direction")
            }
            if !update.companyName.isEmpty, update.companyName.caseInsensitiveCompare(update.ticker) != .orderedSame {
                Text(update.companyName).font(.caption2)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var price: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(quote?.markPrice.bSmartMarketPrice ?? "—")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(BSmartColor.primaryText)
                .accessibilityIdentifier("opinion.market.price")
            if let quote, quote.previousDayPrice > 0 {
                Text(quote.dayChangePercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())) + " · 24h")
                    .font(.caption2.weight(.medium)).monospacedDigit()
                    .foregroundStyle(quote.dayChangePercent >= 0 ? BSmartColor.bull : BSmartColor.bear)
                    .accessibilityIdentifier("opinion.market.change")
            } else {
                Text("24h —").font(.caption2).foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var time: some View {
        Text(update.publishedAt.bSmartDataTimestamp)
            .font(.caption2).foregroundStyle(BSmartColor.secondaryText)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("opinion.published-at")
    }

}
