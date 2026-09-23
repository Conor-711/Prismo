import SwiftUI

struct OpinionPortraitLayout {
    let portrait: SmartAccountPortraitLayout
    let contentWidth: CGFloat
    let avatarFrame: CGRect
    let assetFrame: CGRect

    init(width: CGFloat, offset: CGFloat) {
        portrait = SmartAccountPortraitLayout(height: 205, offset: offset)
        contentWidth = min(390, max(0, width))
        let inset = (width - contentWidth) / 2
        let centerY = portrait.imageHeight / 2
        avatarFrame = CGRect(x: inset + contentWidth * 0.20, y: centerY - 41.5,
            width: contentWidth * 0.28, height: contentWidth * 0.28)
        assetFrame = CGRect(x: inset + contentWidth * 0.45, y: centerY - 10.5,
            width: contentWidth * 0.24, height: contentWidth * 0.24)
    }

    var compositionScale: CGFloat { min(1.18, 1 + portrait.pull / portrait.baseHeight) }
}

struct OpinionPortraitHeader: View {
    let update: SmartAccountUpdate
    let avatarURL: URL?
    let width: CGFloat
    var onCollapseChanged: (Bool) -> Void
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        let layout = OpinionPortraitLayout(width: width, offset: scrollOffset)
        ZStack {
            BSmartColor.ink
            ZStack {
                ZStack(alignment: .bottom) {
                    BSmartAvatar(url: avatarURL, name: update.authorName,
                        size: layout.avatarFrame.width, fallbackSymbol: "person.fill")
                        .bSmartSubjectDestination(update)
                    if update.platformPercentile.isFinite, (0...1).contains(update.platformPercentile) {
                        Text("Top %d%%".bSmartLocalized(max(1, Int(ceil(update.platformPercentile * 100)))))
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(BSmartColor.brand)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(BSmartColor.ink, in: Capsule())
                            .overlay { Capsule().strokeBorder(BSmartColor.brand.opacity(0.35), lineWidth: 0.75) }
                            .padding(.horizontal, 8)
                            .offset(y: 8)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("opinion.author-rank")
                    }
                }
                .frame(width: layout.avatarFrame.width, height: layout.avatarFrame.height)
                .accessibilityElement(children: .contain)
                .position(x: layout.avatarFrame.midX, y: layout.avatarFrame.midY)
                OpinionAssetPortrait(ticker: update.ticker, size: layout.assetFrame.width)
                    .contentShape(Circle())
                    .bSmartTickerDestination(update.ticker)
                    .position(x: layout.assetFrame.midX, y: layout.assetFrame.midY)
            }
            .frame(width: width, height: layout.portrait.imageHeight)
            .scaleEffect(layout.compositionScale, anchor: UnitPoint(x: 0.49, y: 0.60))
        }
        .frame(width: width, height: layout.portrait.imageHeight)
        .clipped()
        .offset(y: -layout.portrait.pull)
        .frame(height: layout.portrait.baseHeight, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.frame(in: .named("opinion.detail.scroll")).minY
        } action: { offset in
            scrollOffset = offset
            onCollapseChanged(OpinionPortraitLayout(width: width, offset: offset).portrait.isCollapsed)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("opinion.portrait")
    }
}

struct OpinionAssetPortrait: View {
    let ticker: String
    let size: CGFloat

    var body: some View {
        BSmartAssetMark(ticker: ticker, size: size, contentInset: 0)
            .background(BSmartColor.surface)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(BSmartColor.ink, lineWidth: 5) }
    }
}
