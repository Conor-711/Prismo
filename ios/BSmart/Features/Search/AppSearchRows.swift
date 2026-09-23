import SwiftUI

struct AppSearchResultRow: View {
    let item: AppSearchItem
    var body: some View {
        Group {
            switch item {
            case .ticker(let entry): ticker(entry)
            case .opinion(let value):
                opinion(ticker: value.ticker, text: TodaySourceHeadline.account(value).text,
                        direction: value.direction, date: value.publishedAt) {
                    BSmartAvatar(url: value.authorAvatarURL, name: value.authorName, size: 22)
                    SmartPlatformMark(platform: value.platform, size: 12)
                    Text(value.authorName)
                }
            case .movement(let value):
                opinion(ticker: value.ticker, text: "\(value.action.label) · \(value.notionalAfter.bSmartCompactUSD)",
                        direction: value.direction, date: value.observedAt) {
                    BSmartSmartMoneyAvatar(identity: value.publicIdentity, size: 22)
                    Text(value.publicIdentity.displayName)
                    Text("Smart Money").foregroundStyle(BSmartColor.sky)
                }
            case .author(let value):
                identity(name: value.name, detail: value.handle, percentile: value.platformPercentile) {
                    BSmartAvatar(url: value.avatarURL, name: value.name, size: 44)
                } platform: { SmartPlatformMark(platform: value.platform, size: 14) }
            case .money(let value):
                identity(name: value.publicIdentity.displayName, detail: "Smart Money", percentile: nil) {
                    BSmartSmartMoneyAvatar(identity: value.publicIdentity, size: 44)
                } platform: { Image(systemName: "waveform.path").foregroundStyle(BSmartColor.brand) }
            case .user(let value):
                identity(name: value.nickname, detail: value.handle.map { "@" + $0 } ?? "", percentile: nil) {
                    BSmartAvatar(url: value.avatarURL, name: value.nickname, size: 44)
                } platform: { EmptyView() }
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func ticker(_ entry: AppTickerCatalogEntry) -> some View {
        HStack(spacing: 12) {
            BSmartAssetMark(ticker: entry.symbol, size: 42, isCrypto: entry.isCrypto)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.symbol).font(.headline).lineLimit(1)
                if entry.companyName != entry.symbol {
                    Text(entry.companyName).font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(entry.price?.bSmartMarketPrice ?? "—").font(.subheadline.weight(.semibold))
                if let change = entry.dayChange {
                    Text(change.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(change >= 0 ? BSmartColor.bull : BSmartColor.bear)
                }
            }.monospacedDigit().fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, 14)
    }

    private func identity<Avatar: View, Platform: View>(name: String, detail: String, percentile: Double?,
        @ViewBuilder avatar: () -> Avatar, @ViewBuilder platform: () -> Platform) -> some View {
        HStack(spacing: 12) {
            avatar()
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 5) { platform(); Text(detail).lineLimit(1) }
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
            }
            Spacer(minLength: 4)
            if let percentile, percentile.isFinite, (0...1).contains(percentile) {
                Text("Top %d%%".bSmartLocalized(max(1, Int(ceil(percentile * 100)))))
                    .font(.caption.weight(.semibold)).foregroundStyle(BSmartColor.brand)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }.padding(.vertical, 14)
    }

    private func opinion<Source: View>(ticker: String, text: String, direction: SignalDirection, date: Date,
        @ViewBuilder source: () -> Source) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BSmartAssetMark(ticker: ticker, size: 24)
                Text(ticker).font(.subheadline.weight(.bold))
                Spacer()
                Text(direction.label).font(.caption.weight(.semibold)).foregroundStyle(direction.color)
            }
            Text(text).font(.subheadline).lineSpacing(3).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                source()
                Spacer(minLength: 4)
                Text(date.bSmartRelativeTimestamp).foregroundStyle(BSmartColor.tertiaryText)
            }
            .font(.caption).foregroundStyle(BSmartColor.secondaryText).lineLimit(1)
        }
        .padding(14)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line.opacity(0.7), lineWidth: 0.5) }
        .padding(.vertical, 6)
    }
}

struct AppSearchDestination: View {
    let item: AppSearchItem
    var preview: TradeFeedDemoData? = nil
    var body: some View {
        Group {
            switch item {
            case .ticker(let value): TickerDestinationView(symbol: value.symbol)
            case .opinion(let value): SmartAccountEvidenceDetailView(update: value)
            case .movement(let value): SmartMoneyMovementDetailView(movement: value)
            case .author(let value): SmartAccountDetailView(account: value)
            case .money(let value): SmartMoneyDetailView(signal: value)
            case .user(let value): FeedPublicProfileView(profileID: value.id, demo: preview)
            }
        }
        .toolbar(.visible, for: .navigationBar)
    }
}
