import SwiftUI

struct TradeFeedRow: View {
    @EnvironmentObject private var model: AppModel
    let item: TradeFeedItem
    let onTradeDismiss: () -> Void
    var demo: TradeFeedDemoData? = nil

    private var accent: Color { item.side == .long ? BSmartColor.bull : BSmartColor.bear }
    private var excerpt: String {
        let original = item.opinion.originalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return original.isEmpty ? item.opinion.thesis : original
    }
    private var hasOriginal: Bool {
        !(item.opinion.originalText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                BSmartDetailNavigationLink(id: "feed.user.\(item.id)") {
                    FeedPublicProfileView(profileID: item.trader.id, demo: demo)
                } label: {
                    HStack(spacing: 10) {
                        BSmartAvatar(url: item.trader.avatarURL, name: item.trader.nickname, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.trader.nickname).font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(BSmartColor.primaryText).lineLimit(2)
                            if let handle = item.trader.handle {
                                Text("@" + handle).font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
                            }
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feed.user.\(item.id.uuidString)")
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.executedAt.bSmartRelativeTimestamp)
                        .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
                        .accessibilityLabel(item.executedAt.formatted(date: .complete, time: .standard))
                    if demo != nil {
                        Text("Demo").font(.caption2.weight(.medium)).foregroundStyle(BSmartColor.brand)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    executionInstrument
                    Spacer(minLength: 0)
                    executionAmount
                }
                VStack(alignment: .leading, spacing: 8) {
                    executionInstrument
                    executionAmount
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.execution.\(item.id.uuidString)")

            if let thesis = item.thesis {
                Text(thesis.body).font(.system(size: 17)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("thesis.body.\(item.id.uuidString)")
            }
            VStack(alignment: .leading, spacing: 12) {
                BSmartDetailNavigationLink(id: "feed.author.\(item.id)", usesZoomTransition: false) {
                    SmartAccountDetailView(account: model.smartAccountProfile(for: item.opinion))
                } label: {
                    HStack(spacing: 9) {
                        BSmartAvatar(url: item.opinion.authorAvatarURL, name: item.opinion.authorName, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.opinion.authorName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                SmartPlatformMark(platform: item.opinion.platform, size: 14)
                            }
                            Text("Through this opinion".bSmartLocalized).font(.caption2)
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        Text(item.opinion.publishedAt, format: .dateTime.month().day())
                            .font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                    }
                    .foregroundStyle(BSmartColor.primaryText).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("feed.author.\(item.id.uuidString)")
                BSmartDetailNavigationLink(id: "feed.opinion.\(item.id)") {
                    SmartAccountEvidenceDetailView(update: item.opinion)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !hasOriginal {
                                Text("Summary".bSmartLocalized).font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                            }
                            Text(excerpt).font(.system(size: 15)).lineSpacing(4).lineLimit(4)
                                .foregroundStyle(BSmartColor.secondaryText).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("feed.opinion.\(item.id.uuidString)")
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(BSmartColor.line).frame(width: 2) }
            HStack(spacing: 12) {
                if demo == nil {
                    TradeThesisActions(item: item, onPublished: onTradeDismiss)
                }
                Spacer(minLength: 0)
                FeedQuickTradeBar(item: item, onDismiss: onTradeDismiss, isDemo: demo != nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.row.\(item.id.uuidString)")
    }

    private var executionInstrument: some View {
        HStack(alignment: .center, spacing: 10) {
            Label((item.side == .long ? "Long" : "Short").bSmartLocalized,
                  systemImage: item.side == .long ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
            BSmartDetailNavigationLink(id: "feed.instrument.\(item.id)") {
                TickerDestinationView(symbol: item.opinion.ticker)
            } label: {
                HStack(spacing: 8) {
                    BSmartAssetMark(ticker: item.opinion.ticker, size: 28)
                    Text(item.opinion.ticker).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                }
            }
            .buttonStyle(.plain).accessibilityIdentifier("feed.ticker.\(item.id.uuidString)")
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var executionAmount: some View {
        Text(item.amountLabel).font(.system(size: 22, weight: .semibold)).monospacedDigit()
            .foregroundStyle(BSmartColor.primaryText).fixedSize()
    }
}
