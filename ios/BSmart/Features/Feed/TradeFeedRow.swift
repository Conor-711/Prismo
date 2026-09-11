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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                BSmartDetailNavigationLink(id: "feed.user.\(item.id)") {
                    FeedPublicProfileView(profileID: item.trader.id, demo: demo)
                } label: {
                    HStack(spacing: 10) {
                        BSmartAvatar(url: item.trader.avatarURL, name: item.trader.nickname, size: 42)
                        Text(item.trader.nickname).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BSmartColor.primaryText).lineLimit(2)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feed.user.\(item.id.uuidString)")
                Spacer(minLength: 4)
                if demo != nil {
                    Text("Demo").font(.caption2.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(BSmartColor.recessed, in: Capsule())
                }
                Text(item.executedAt.bSmartRelativeTimestamp)
                    .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
                    .accessibilityLabel(item.executedAt.formatted(date: .complete, time: .standard))
            }
            HStack(spacing: 8) {
                Image(systemName: item.side == .long ? "arrow.up.right" : "arrow.down.right")
                Text((item.side == .long ? "Long" : "Short").bSmartLocalized)
                Text(item.amountLabel).monospacedDigit()
                BSmartDetailNavigationLink(id: "feed.instrument.\(item.id)") {
                    TickerDestinationView(symbol: item.opinion.ticker)
                } label: {
                    Text(item.opinion.ticker).underline().lineLimit(1)
                }
                .buttonStyle(.plain).accessibilityIdentifier("feed.ticker.\(item.id.uuidString)")
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(accent)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.execution.\(item.id.uuidString)")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "link").font(.caption)
                    Text("Through this opinion".bSmartLocalized).font(.caption)
                }.foregroundStyle(BSmartColor.tertiaryText)
                BSmartDetailNavigationLink(id: "feed.author.\(item.id)") {
                    SmartAccountDetailView(account: model.smartAccountProfile(for: item.opinion))
                } label: {
                    HStack(spacing: 9) {
                        BSmartAvatar(url: item.opinion.authorAvatarURL, name: item.opinion.authorName, size: 28)
                        Text(item.opinion.authorName).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(item.opinion.platform).font(.caption2)
                            .foregroundStyle(BSmartColor.secondaryText)
                        Spacer(minLength: 0)
                        Text("Top 25%").font(.caption2.weight(.semibold))
                            .foregroundStyle(BSmartColor.brand)
                    }
                    .foregroundStyle(BSmartColor.primaryText).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("feed.author.\(item.id.uuidString)")
                BSmartDetailNavigationLink(id: "feed.opinion.\(item.id)") {
                    SmartAccountEvidenceDetailView(update: item.opinion)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(BSmartColor.brand.opacity(0.65)).frame(width: 2)
                        VStack(alignment: .leading, spacing: 6) {
                            if !hasOriginal {
                                Text("Summary".bSmartLocalized).font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                            }
                            Text(excerpt).font(.system(size: 15)).lineSpacing(4).lineLimit(4)
                                .foregroundStyle(BSmartColor.primaryText).multilineTextAlignment(.leading)
                            Text(item.opinion.publishedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("feed.opinion.\(item.id.uuidString)")
            }
            .padding(14).background(BSmartColor.recessed, in: RoundedRectangle(cornerRadius: 14))
            FeedQuickTradeBar(item: item, onDismiss: onTradeDismiss, isDemo: demo != nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.row.\(item.id.uuidString)")
    }
}
