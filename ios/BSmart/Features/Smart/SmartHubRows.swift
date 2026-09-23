import SwiftUI

struct SmartAccountRow: View {
    let rank: Int
    let account: SmartAccountProfile
    let recentTickers: [String]
    let isFollowing: Bool

    private var highlight: TodayInvestorDiscoveryHighlight {
        TodayInvestorDiscoveryHighlight(account: account, representatives: [])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SmartHubRank(rank: rank)
            BSmartAvatar(url: account.avatarURL, name: account.name, size: 52)
                .overlay(alignment: .bottomTrailing) {
                    SmartPlatformMark(platform: account.platform, size: 16)
                        .padding(3).background(BSmartColor.ink, in: Circle()).offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 9) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        name
                        Spacer(minLength: 0)
                        rankLabel.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) { name; rankLabel }
                }
                Text([account.specialty, account.horizon].map { $0.bSmartLocalized }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let intro = highlight.intro {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            BSmartAssetMark(ticker: intro.ticker, size: 18)
                            Text(intro.ticker).fontWeight(.semibold)
                            Text("Representative work".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                        }.font(.caption)
                        if let value = highlight.stockReturn, let days = highlight.tradingSessions {
                            Text("%dD stock %@".bSmartLocalized(days,
                                value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + "%"))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(value >= 0 ? BSmartColor.bull : BSmartColor.bear)
                        }
                    }
                    .accessibilityIdentifier("smart.account.row.work")
                } else {
                    SmartHubAssets(tickers: recentTickers)
                }
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var name: some View {
        HStack(spacing: 5) {
            Text(account.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            if isFollowing { Image(systemName: "star.fill").font(.caption2).foregroundStyle(BSmartColor.gold) }
        }
        .accessibilityLabel("\(account.name), \(account.platform), \(account.handle)")
        .accessibilityIdentifier("smart.account.row.identity")
    }

    @ViewBuilder private var rankLabel: some View {
        if let label = SmartAccountRankPresentation.label(account) {
            Text(label).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(BSmartColor.brand)
        }
    }
}

struct SmartMoneyRow: View {
    let signal: SmartMoneySignal
    let isFollowing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SmartHubRank(rank: signal.rank ?? 0)
            BSmartSmartMoneyAvatar(identity: signal.publicIdentity, size: 52)
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        identity
                        Spacer(minLength: 0)
                        performance(alignment: .trailing).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        identity
                        performance(alignment: .leading)
                    }
                }
                SmartHubAssets(tickers: positionTickers)
            }
        }
        .foregroundStyle(BSmartColor.primaryText)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(signal.publicIdentity.displayName).font(.headline)
                if isFollowing { Image(systemName: "star.fill").font(.caption2).foregroundStyle(BSmartColor.gold) }
            }
            Text(signal.resolvedStyle.bSmartLocalized)
                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func performance(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(signal.netPnl.map { ($0 >= 0 ? "+" : "-") + abs($0).bSmartCompactUSD } ?? "—")
                .font(.subheadline.weight(.bold)).monospacedDigit()
                .foregroundStyle(signal.netPnl.map { $0 >= 0 ? BSmartColor.bull : BSmartColor.bear } ?? BSmartColor.secondaryText)
            Text("30D P&L".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
        }
    }

    private var positionTickers: [String] {
        var seen = Set<String>()
        return signal.resolvedPositions.sorted { abs($0.notional) > abs($1.notional) }
            .map { $0.symbol.uppercased() }.filter { seen.insert($0).inserted }
    }
}

private struct SmartHubRank: View {
    let rank: Int
    @ScaledMetric(relativeTo: .caption) private var width = 25.0

    var body: some View {
        Text(rank > 0 ? "\(rank)" : "—")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(rank > 0 && rank <= 3 ? BSmartColor.brand : BSmartColor.tertiaryText)
            .frame(width: width, height: 52)
            .accessibilityLabel("Rank %d".bSmartLocalized(rank))
    }
}

private struct SmartHubAssets: View {
    let tickers: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            assets(limit: 3)
            assets(limit: 1)
        }
    }

    private func assets(limit: Int) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(tickers.prefix(limit)), id: \.self) { ticker in
                HStack(spacing: 4) {
                    BSmartAssetMark(ticker: ticker, size: 18)
                    Text(ticker).font(.caption.weight(.medium))
                }.fixedSize()
            }
        }.foregroundStyle(BSmartColor.secondaryText)
    }
}
