import SwiftUI

struct TodayHoldingsActivityRow: View {
    let activity: TodayActivity
    let weight: Double?
    var showsTicker = true

    private var accent: Color { activity.isSmartAccount ? BSmartColor.brand : BSmartColor.sky }
    private var headline: String {
        if case let .account(account) = activity { return TodaySourceHeadline.account(account.latest).text }
        return activity.informativeTitle
    }

    var body: some View {
        BSmartDetailNavigationLink(id: "holdings-activity-\(activity.id)") {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if showsTicker {
                    TodayHoldingGroupHeader(ticker: activity.ticker, weight: weight)
                }
                Text(headline)
                    .font(.subheadline.weight(.medium))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sourceFooter
            }
            .foregroundStyle(BSmartColor.primaryText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(BSmartColor.line, lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("holdings.activity.\(activity.isSmartAccount ? "account" : "money").\(activity.id)")
    }

    private var sourceFooter: some View {
        HStack(spacing: 6) {
            avatar
                .bSmartSubjectDestination(subjectActivity)
            platform
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if case let .account(account) = activity,
               account.latest.platformPercentile.isFinite,
               (0...1).contains(account.latest.platformPercentile) {
                Text("Top \(max(1, Int(ceil(account.latest.platformPercentile * 100))))%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            Text(activity.occurredAt.bSmartRelativeTimestamp)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    private var subjectActivity: TickerSmartActivityItem {
        switch activity {
        case let .account(account): TickerSmartActivityItem(payload: .account(account.latest))
        case let .money(money): TickerSmartActivityItem(payload: .money(money.latest))
        }
    }

    private var name: String {
        switch activity {
        case let .account(account): account.latest.authorName
        case let .money(money): money.publicIdentity.displayName
        }
    }

    @ViewBuilder private var avatar: some View {
        switch activity {
        case let .account(account):
            BSmartAvatar(url: account.latest.authorAvatarURL, name: name, size: 24)
        case let .money(money):
            BSmartSmartMoneyAvatar(identity: money.publicIdentity, size: 24)
        }
    }

    @ViewBuilder private var platform: some View {
        switch activity {
        case let .account(account): SmartPlatformMark(platform: account.latest.platform, size: 12)
        case .money: SmartPlatformMark(platform: "Hyperliquid", size: 12)
        }
    }

    @ViewBuilder private var destination: some View {
        switch activity {
        case let .account(account): SmartAccountEvidenceDetailView(update: account.latest)
        case let .money(money): SmartMoneyMovementDetailView(movement: money.latest)
        }
    }
}

struct TodayHoldingGroupHeader: View {
    let ticker: String
    let weight: Double?
    var inAppSide: TodayInAppPositionSide? = nil

    var body: some View {
        HStack(spacing: 8) {
            BSmartAssetMark(ticker: ticker, size: 26)
            Text(TodayHoldingsActivity.symbol(ticker))
                .font(.headline.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
            if let inAppSide {
                Text(inAppSide.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(inAppSide == .both ? BSmartColor.secondaryText :
                                     inAppSide == .short ? BSmartColor.bear : BSmartColor.bull)
            }
            Spacer(minLength: 8)
            if let weight {
                Text("Portfolio weight %@".bSmartLocalized(
                    weight.formatted(.percent.precision(.fractionLength(0...1)))
                ))
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(1)
            }
        }
        .frame(minHeight: 32)
    }
}
