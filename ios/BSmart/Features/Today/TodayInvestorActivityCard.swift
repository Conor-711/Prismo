import SwiftUI

struct TodayInvestorActivityCard: View {
    let investor: TodayInvestorActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(investor.latest.occurredAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(BSmartColor.tertiaryText)
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            }
            .padding(.bottom, 16)
            TodayInvestorActivityHeader(investor: investor)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(investor.preview) { activity in
                    TodayInvestorActivityEntry(activity: activity)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(BSmartColor.line).frame(width: 1)
            }
            .padding(.leading, 21)
            BSmartDetailNavigationLink(id: "investor-activity-\(investor.id)") {
                TodayInvestorActivityTimelineView(investorID: investor.id)
            } label: {
                HStack(spacing: 6) {
                    Text("All activity".bSmartLocalized)
                    Text("\(investor.activities.count)").monospacedDigit()
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 35)
            .accessibilityIdentifier("smart-updates.open.\(investor.id)")
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-updates.investor.\(investor.id)")
    }
}

struct TodayInvestorActivityHeader: View {
    @EnvironmentObject private var model: AppModel
    let investor: TodayInvestorActivity

    private var activity: TodayActivity { investor.latest }
    private var accent: Color { activity.isSmartAccount ? BSmartColor.brand : BSmartColor.sky }
    private var subject: TickerSmartActivityItem {
        switch activity {
        case let .account(account): .init(payload: .account(account.latest))
        case let .money(money): .init(payload: .money(money.latest))
        }
    }
    private var followID: String {
        switch activity {
        case let .account(account): model.smartAccountProfile(for: account.latest).id
        case let .money(money):
            model.smartMoney.first {
                $0.id.caseInsensitiveCompare(money.accountId) == .orderedSame
                    || $0.resolvedAddress.caseInsensitiveCompare(money.accountId) == .orderedSame
            }?.id ?? money.accountId
        }
    }
    private var isTracked: Bool {
        activity.isSmartAccount ? model.isFollowingSmartAccount(followID) : model.isFollowingSmartMoney(followID)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 6) {
                    Text(investor.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        platform
                        Text(activity.isSmartAccount ? "Smart Account" : "Smart Money")
                            .foregroundStyle(BSmartColor.secondaryText)
                        ranking
                    }
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .bSmartSubjectDestination(subject)
            Button {
                if activity.isSmartAccount { model.toggleSmartAccountFollow(followID) }
                else { model.toggleSmartMoneyFollow(followID) }
            } label: {
                Image(systemName: isTracked ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isTracked ? accent : BSmartColor.tertiaryText)
                    .frame(width: 30, height: 30)
                    .background(isTracked ? accent.opacity(0.08) : .clear, in: Circle())
                    .overlay(Circle().strokeBorder(BSmartColor.line, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((isTracked ? "Tracking" : "Track").bSmartLocalized)
            .accessibilityValue(isTracked ? "Tracking".bSmartLocalized : "Not tracked".bSmartLocalized)
            .accessibilityIdentifier("smart-updates.track.\(investor.id)")
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private var avatar: some View {
        switch activity {
        case let .account(account):
            BSmartAvatar(url: account.latest.authorAvatarURL, name: investor.name, size: 44)
        case let .money(money): BSmartSmartMoneyAvatar(identity: money.publicIdentity, size: 44)
        }
    }

    @ViewBuilder private var platform: some View {
        switch activity {
        case let .account(account): SmartPlatformMark(platform: account.latest.platform, size: 14)
        case .money: SmartPlatformMark(platform: "Hyperliquid", size: 14)
        }
    }

    @ViewBuilder private var ranking: some View {
        switch activity {
        case let .account(account):
            if account.latest.platformPercentile.isFinite,
               (0...1).contains(account.latest.platformPercentile) {
                Text("Top \(max(1, Int(ceil(account.latest.platformPercentile * 100))))%")
                    .foregroundStyle(accent)
            }
        case let .money(money):
            if money.accountScore.isFinite {
                Text("Score \(Int(money.accountScore.rounded()))")
                    .foregroundStyle(accent)
            }
        }
    }
}

struct TodayInvestorActivityEntry: View {
    @EnvironmentObject private var model: AppModel
    let activity: TodayActivity
    var isTimeline = false

    private var headline: String {
        if case let .account(account) = activity { return TodaySourceHeadline.account(account.latest).text }
        return activity.informativeTitle
    }

    var body: some View {
        BSmartDetailNavigationLink(id: "investor-evidence-\(activity.actorKey)-\(activity.id)") {
            Group {
                switch activity {
                case let .account(account): SmartAccountEvidenceDetailView(update: account.latest)
                case let .money(money): SmartMoneyMovementDetailView(movement: money.latest)
                }
            }
            .onAppear { model.markTodayActivityRead(activity.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    BSmartAssetMark(ticker: activity.ticker, size: 22)
                    Text(activity.ticker.uppercased()).font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(isTimeline ? activity.occurredAt.bSmartDataTimestamp : activity.occurredAt.bSmartRelativeTimestamp)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                }
                Text(headline)
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(3)
                    .lineLimit(isTimeline ? 5 : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("smart-updates.evidence.\(activity.isSmartAccount ? "account" : "money").\(activity.id)")
    }
}
