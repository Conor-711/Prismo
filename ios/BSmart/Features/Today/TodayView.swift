import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @State private var holdingsRefreshID = UUID()

    private var portfolioPositions: [PortfolioPosition] {
        let heldTickers = Set(model.heldPositions.map { $0.ticker.uppercased() })
        return model.heldPositions + model.watchlist.filter {
            !heldTickers.contains($0.ticker.uppercased())
        }
    }

    private var trackedActivities: [TodayActivity] {
        var updatesByID = Dictionary(uniqueKeysWithValues: model.smartAccountUpdates.map { ($0.id, $0) })
        for (accountID, updates) in model.smartAccountEvidenceByAuthor where
            model.followedSmartAccountIDs.contains(where: {
                $0.caseInsensitiveCompare(accountID) == .orderedSame
            }) {
            for update in updates {
                updatesByID[update.id] = update
            }
        }

        return TodayActivity.latestTrackedActivities(
            accountUpdates: Array(updatesByID.values),
            moneyMovements: model.smartMoneyMovements,
            smartAccounts: model.smartAccounts,
            followedAccountIDs: model.followedSmartAccountIDs,
            followedMoneyIDs: model.followedSmartMoneyIDs
        )
        .filter(\.isSmartAccount)
    }

    private var trackedAccountRecommendations: [SmartAccountProfile] {
        model.smartAccounts
            .filter { account in
                !model.followedSmartAccountIDs.contains(where: {
                    $0.caseInsensitiveCompare(account.id) == .orderedSame
                })
            }
            .sorted { lhs, rhs in
                let lhsRank = lhs.resolvedRank > 0 ? lhs.resolvedRank : .max
                let rhsRank = rhs.resolvedRank > 0 ? rhs.resolvedRank : .max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.score > rhs.score
            }
            .prefix(4)
            .map { $0 }
    }

    private var followedAccountSyncKey: String {
        model.followedSmartAccountIDs.map { $0.lowercased() }.sorted().joined(separator: "|")
    }

    private var viewpointPackages: [TodayViewpointPackage] {
        return TodayViewpointPackage.packages(
            from: model.smartAccountUpdates,
            maximumPackages: 10
        )
    }

    private var alphaOpportunities: [TodayAlphaOpportunity] {
        TodayAlphaOpportunity.opportunities(
            accountUpdates: model.smartAccountUpdates,
            moneyMovements: model.smartMoneyMovements,
            excluding: Set(portfolioPositions.map { $0.ticker.uppercased() })
        )
    }


    var body: some View {
        NavigationStack(path: $router.todayPath) {
            TodayHomeContent(
                header: { viewport in
                    VStack(alignment: .leading, spacing: viewport.height < 700 ? BSmartSpacing.small : BSmartSpacing.medium) {
                        pageHeader
                        TodayInvestorDiscoveryModule(compact: viewport.height < 700)
                    }
                    .padding(.horizontal, BSmartSpacing.large)
                    .padding(.vertical, viewport.height < 700 ? BSmartSpacing.small : BSmartSpacing.large)
                },
                content: { section in
                    switch section {
                    case .portfolio:
                        VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                            TodayHoldingsActivityModule(refreshID: holdingsRefreshID)
                            TodayTrackedActivityModule(
                                activities: trackedActivities,
                                recommendations: trackedAccountRecommendations
                            )
                        }
                    case .market:
                        TodayMarketActivityView(packages: viewpointPackages, opportunities: alphaOpportunities)
                    case .investors:
                        TodayInvestorActivityModule()
                    }
                },
                refresh: {
                    await model.refreshLiveIntelligence()
                    holdingsRefreshID = UUID()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.screen")
            .background(BSmartColor.ink)
            .task(id: followedAccountSyncKey) {
                for account in model.smartAccounts where model.followedSmartAccountIDs.contains(where: {
                    $0.caseInsensitiveCompare(account.id) == .orderedSame
                }) {
                    await model.loadSmartAccountEvidence(for: account)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .dailyDigest:
                    DailyDigestView()
                }
            }
            .task(id: router.pendingSignalID) {
                router.resolvePendingSignal(from: model.signals)
            }
            .onChange(of: model.signals) { _, signals in
                router.resolvePendingSignal(from: signals)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .bSmartPage()
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: BSmartSpacing.medium) {
            BSmartPageTitle(
                eyebrow: "",
                title: "Today",
                subtitle: "Recent Smart Account views for stocks you track"
            )

            Spacer()

            NotificationEntryView()
        }
        .frame(minHeight: 44)
    }

}

private struct TodayTrackedActivityModule: View {
    @EnvironmentObject private var model: AppModel

    let activities: [TodayActivity]
    let recommendations: [SmartAccountProfile]

    private var followedCount: Int {
        model.followedSmartAccountIDs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                TodayEditorialSectionTitle(title: "Tracked activity")
                if followedCount > 0 {
                    Text("%d tracked".bSmartLocalized(followedCount))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                        .monospacedDigit()
                }
            }

            if followedCount == 0 {
                recommendationList(title: "Track top Smart Accounts")
            } else if activities.isEmpty && !model.loadingSmartAccountEvidenceIDs.isEmpty {
                BSmartSkeletonRows(style: .feed, count: 2)
            } else if activities.isEmpty {
                Text("No tracked activity yet".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(activities) { activity in
                        destination(for: activity) {
                            trackedCard(activity)
                        }
                        Divider().overlay(BSmartColor.line)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.tracked-activity")
    }

    @ViewBuilder
    private func recommendationList(title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.secondaryText)
                .padding(.horizontal, BSmartSpacing.medium)
                .padding(.vertical, BSmartSpacing.small)

            ForEach(Array(recommendations.prefix(3).enumerated()), id: \.element.id) { index, account in
                if index > 0 { Divider().overlay(BSmartColor.line) }
                HStack(spacing: BSmartSpacing.small) {
                    Text(account.resolvedRank > 0 ? "#\(account.resolvedRank)" : "–")
                        .font(.caption.weight(.black))
                        .foregroundStyle(index == 0 ? BSmartColor.gold : BSmartColor.tertiaryText)
                        .frame(width: 28, alignment: .leading)

                    BSmartAvatar(url: account.avatarURL, name: account.name, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            SmartPlatformMark(platform: account.platform, size: 15)
                            if let ticker = account.recentTicker {
                                BSmartAssetMark(ticker: ticker, size: 15)
                                Text(ticker)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(BSmartColor.secondaryText)
                            }
                        }
                    }

                    Spacer(minLength: BSmartSpacing.small)

                    Button {
                        model.toggleSmartAccountFollow(account.id)
                        Task { await model.loadSmartAccountEvidence(for: account) }
                    } label: {
                        Label("Track".bSmartLocalized, systemImage: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.ink)
                            .padding(.horizontal, BSmartSpacing.small)
                            .frame(minHeight: 32)
                            .background(BSmartColor.brand)
                            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.tracked-activity.recommendation.\(account.id)")
                }
                .padding(.horizontal, BSmartSpacing.medium)
                .frame(minHeight: 58)
            }
        }
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    @ViewBuilder
    private func destination<Label: View>(
        for activity: TodayActivity,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        switch activity {
        case let .account(accountActivity):
            BSmartDetailNavigationLink(id: "tracked-account-\(activity.id)") {
                SmartAccountEvidenceDetailView(update: accountActivity.latest)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        case let .money(moneyActivity):
            BSmartDetailNavigationLink(id: "tracked-money-\(activity.id)") {
                SmartMoneyMovementDetailView(movement: moneyActivity.latest)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        }
    }

    private func trackedCard(_ activity: TodayActivity) -> some View {
        HStack(alignment: .top, spacing: 10) {
            trackedAvatar(activity)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(actorName(activity))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                    sourceMark(activity)
                    Spacer(minLength: 4)
                    Text(compactRelativeTime(activity.occurredAt))
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                HStack(spacing: 6) {
                    BSmartAssetMark(ticker: activity.ticker, size: 18)
                    Text(activity.ticker)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                Text(activity.informativeTitle)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.tracked-activity.\(activity.actorKey)")
    }

    @ViewBuilder
    private func trackedAvatar(_ activity: TodayActivity) -> some View {
        switch activity {
        case let .account(accountActivity):
            BSmartAvatar(
                url: accountActivity.latest.authorAvatarURL,
                name: accountActivity.latest.authorName,
                size: 36
            )
        case let .money(moneyActivity):
            BSmartSmartMoneyAvatar(identity: moneyActivity.publicIdentity, size: 36)
        }
    }

    @ViewBuilder
    private func sourceMark(_ activity: TodayActivity) -> some View {
        switch activity {
        case let .account(accountActivity):
            SmartPlatformMark(platform: accountActivity.latest.platform, size: 14)
        case .money:
            SmartPlatformMark(platform: "Hyperliquid", size: 14)
        }
    }

    private func actorName(_ activity: TodayActivity) -> String {
        switch activity {
        case let .account(accountActivity): accountActivity.latest.authorName
        case let .money(moneyActivity): moneyActivity.publicIdentity.displayName
        }
    }

}

private struct TodayLeadActivityCard: View {
    let activity: TodayActivity
    let position: PortfolioPosition?
    let isRead: Bool
    let isExpanded: Bool
    let onOpen: () -> Void
    let onOpenAccount: (SmartAccountUpdate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            actorHeader

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                    Text(activity.informativeTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(BSmartColor.primaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if case let .account(accountActivity) = activity {
                        let update = accountActivity.latest
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Why they hold this view".bSmartLocalized.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(BSmartColor.brand)
                            Text(accountDisplayText(update))
                                .font(.subheadline)
                                .foregroundStyle(BSmartColor.secondaryText)
                                .multilineTextAlignment(.leading)
                                .lineLimit(4)
                        }
                        .padding(BSmartSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BSmartColor.recessed)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(BSmartColor.brand)
                                .frame(width: 2)
                        }

                        TodayAccountFacts(update: update)

                        if accountActivity.mentionCount > 1 {
                            Label(
                                "%d similar views grouped".bSmartLocalized(accountActivity.mentionCount),
                                systemImage: "rectangle.stack"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                        }
                    } else if case let .money(movement) = activity {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Observed action".bSmartLocalized.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(BSmartColor.sky)
                            Text(moneyObservation(movement))
                                .font(.subheadline)
                                .foregroundStyle(BSmartColor.secondaryText)
                                .multilineTextAlignment(.leading)
                                .lineLimit(4)
                        }
                        .padding(BSmartSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BSmartColor.recessed)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(BSmartColor.sky)
                                .frame(width: 2)
                        }

                        TodayMoneyFacts(movement: movement)
                    }

                    HStack(spacing: BSmartSpacing.small) {
                        BSmartAssetMark(ticker: activity.ticker, size: 28)
                            .bSmartTickerDestination(activity.ticker)
                        Text(positionContext(position, ticker: activity.ticker))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BSmartColor.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text(isExpanded ? "Hide evidence".bSmartLocalized : "View evidence".bSmartLocalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.pulse)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BSmartColor.pulse)
                    }
                    .padding(.top, BSmartSpacing.small)
                    .overlay(alignment: .top) {
                        Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.lead-activity")

            if isExpanded {
                TodayActivityEvidence(activity: activity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .bSmartPanel(
            padding: BSmartSpacing.large,
            fill: BSmartColor.surface,
            border: BSmartColor.pulse.opacity(0.48)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BSmartColor.pulse)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
        .overlay(alignment: .topLeading) {
            if !isRead {
                Circle()
                    .fill(BSmartColor.pulse)
                    .frame(width: 6, height: 6)
                    .offset(x: 10, y: 10)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var actorHeader: some View {
        switch activity {
        case let .account(activity):
            let update = activity.latest
            Button {
                onOpenAccount(update)
            } label: {
                HStack(spacing: BSmartSpacing.medium) {
                    BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(update.authorName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                        Text(accountMetadata(update))
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    BSmartTag(text: accountRank(update), color: BSmartColor.brand)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Smart Account preview".bSmartLocalized)
            .accessibilityIdentifier("today.smart-account-preview")

        case let .money(movement):
            HStack(spacing: BSmartSpacing.medium) {
                BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(movement.publicIdentity.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)
                    Text("Public capital account · %@".bSmartLocalized(movement.market))
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                BSmartTag(
                    text: "Score %@".bSmartLocalized(
                        movement.accountScore.formatted(.number.precision(.fractionLength(0)))
                    ),
                    color: BSmartColor.sky
                )
            }
        }
    }

}

private struct TodayActivityRow: View {
    @EnvironmentObject private var model: AppModel
    let activity: TodayActivity
    let position: PortfolioPosition?
    let isRead: Bool
    let isExpanded: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                actorAvatar

                VStack(alignment: .leading, spacing: 5) {
                    sourceHeader

                    Button(action: onOpen) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(activity.informativeTitle)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(BSmartColor.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(preview)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(BSmartColor.secondaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 6) {
                                BSmartTag(text: actionTag, color: activity.direction.color)
                                Text(positionContext(position, ticker: activity.ticker))
                                    .font(.caption2)
                                    .foregroundStyle(BSmartColor.tertiaryText)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOpen) {
                    VStack(spacing: 3) {
                        Text(compactRelativeTime(activity.occurredAt))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .frame(width: 25, height: 34)
                }
                .buttonStyle(.plain)
            }
            .padding(BSmartSpacing.large)

            if isExpanded {
                Divider().overlay(BSmartColor.line)
                    .padding(.horizontal, BSmartSpacing.large)
                TodayActivityEvidence(activity: activity)
                    .padding(.horizontal, BSmartSpacing.large)
                    .padding(.top, BSmartSpacing.small)
                    .padding(.bottom, BSmartSpacing.medium)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(activity.direction.color.opacity(0.26), lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private var actorAvatar: some View {
        switch activity {
        case let .account(activity):
            let update = activity.latest
            accountPreviewLink(update: update, source: "avatar") {
                ZStack(alignment: .bottomTrailing) {
                    BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 40)
                        .overlay {
                            Circle()
                                .stroke(BSmartColor.brand.opacity(0.9), lineWidth: 1.5)
                        }

                    Image(systemName: "person.crop.circle.badge.chevron.forward")
                        .font(.system(size: 13, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(BSmartColor.onAccent, BSmartColor.brand)
                        .background(BSmartColor.surface, in: Circle())
                        .offset(x: 3, y: 3)
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
        case let .money(movement):
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 38)
                .bSmartSubjectDestination(movement.latest)
        }
    }

    @ViewBuilder
    private var sourceHeader: some View {
        HStack(spacing: 5) {
            if !isRead {
                Circle()
                    .fill(BSmartColor.pulse)
                    .frame(width: 5, height: 5)
            }

            switch activity {
            case let .account(accountActivity):
                let update = accountActivity.latest
                accountPreviewLink(update: update, source: "header") {
                    HStack(spacing: 4) {
                        Text(update.authorName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        platformLogo(for: update.platform)
                    }
                    .foregroundStyle(BSmartColor.brand)
                }
                BSmartTag(text: accountRank(update), color: BSmartColor.brand)
            case let .money(movement):
                HStack(spacing: 4) {
                    Text(movement.publicIdentity.displayName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .bSmartSubjectDestination(movement.latest)
                    Image(systemName: "wallet.pass.fill")
                        .font(.caption2)
                }
                .foregroundStyle(BSmartColor.sky)
                BSmartTag(
                    text: "Score %@".bSmartLocalized(
                        movement.accountScore.formatted(.number.precision(.fractionLength(0)))
                    ),
                    color: BSmartColor.sky
                )
            }

            Spacer(minLength: 2)
            BSmartAssetMark(ticker: activity.ticker, size: 18)
                .accessibilityLabel(activity.ticker)
        }
    }

    @ViewBuilder
    private func accountPreviewLink<Label: View>(
        update: SmartAccountUpdate,
        source: String,
        @ViewBuilder label: @escaping () -> Label
    ) -> some View {
        let account = model.smartAccountProfile(for: update)
        BSmartDetailNavigationLink(id: "activity-account-\(update.id)-\(source)", usesZoomTransition: false) {
            SmartAccountDetailView(account: account)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Smart Account preview".bSmartLocalized)
        .accessibilityIdentifier("today.smart-account-preview")
    }

    @ViewBuilder
    private func platformLogo(for platform: String) -> some View {
        if platform.lowercased().contains("youtube") {
            Image(systemName: "play.rectangle.fill")
                .foregroundStyle(Color.red)
        } else {
            Text("X")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(BSmartColor.primaryText)
        }
    }

    private var preview: String {
        switch activity {
        case let .account(activity): accountDisplayText(activity.latest)
        case let .money(movement): moneyObservation(movement)
        }
    }

    private var actionTag: String {
        switch activity {
        case let .account(activity):
            let update = activity.latest
            return isSpecifiedHorizon(update.horizon)
                ? "\(update.direction.label) · \(update.horizon)"
                : update.direction.label
        case let .money(movement): return movement.action.label
        }
    }
}

private struct TodayAccountFacts: View {
    let update: SmartAccountUpdate

    var body: some View {
        HStack(spacing: 0) {
            if isSpecifiedHorizon(update.horizon) {
                fact("Horizon", update.horizon.bSmartLocalized)
                Divider().overlay(BSmartColor.line)
            }
            fact(
                "Target",
                update.targetPrice?.formatted(.bSmartDollars.precision(.fractionLength(0)))
                    ?? "Not stated".bSmartLocalized
            )
            Divider().overlay(BSmartColor.line)
            fact("Invalidation", update.invalidation?.nilIfBlank ?? "Not stated".bSmartLocalized)
        }
        .frame(minHeight: 58)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, BSmartSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayMoneyFacts: View {
    let movement: TodayMoneyActivity

    var body: some View {
        HStack(spacing: 0) {
            fact("Action", movement.action.label.bSmartLocalized)
            Divider().overlay(BSmartColor.line)
            fact("Change", compactSignedUSD(movement.notionalChange))
            Divider().overlay(BSmartColor.line)
            fact(
                "Leverage",
                movement.leverage.map { "\($0.formatted(.number.precision(.fractionLength(1))))x" }
                    ?? "Not available".bSmartLocalized
            )
        }
        .frame(minHeight: 58)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, BSmartSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayActivityEvidence: View {
    let activity: TodayActivity
    @State private var showsOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.small) {
                Label(evidenceTitle, systemImage: "quote.opening")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                Spacer()
                if hasTranslation {
                    Button(showsOriginal ? "View translation".bSmartLocalized : "View original".bSmartLocalized) {
                        withAnimation(BSmartMotion.quick) {
                            showsOriginal.toggle()
                        }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: BSmartSpacing.small) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(BSmartColor.brand.opacity(0.75))
                    .frame(width: 3)

                Text(renderedEvidenceText)
                    .font(.body)
                    .foregroundStyle(BSmartColor.primaryText.opacity(0.9))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if case let .account(accountActivity) = activity,
               accountActivity.mentionCount > 1 {
                Divider().overlay(BSmartColor.line)
                VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                    Text("Grouped view history".bSmartLocalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)

                    ForEach(accountActivity.updates, id: \.id) { update in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(update.publishedAt.bSmartRelativeTimestamp)
                                if isSpecifiedHorizon(update.horizon) {
                                    Text("·")
                                    Text(update.horizon.bSmartLocalized)
                                }
                                Spacer()
                                if let url = update.sourceURL ?? update.evidenceURL {
                                    Link(destination: url) {
                                        Image(systemName: "arrow.up.right")
                                            .foregroundStyle(BSmartColor.brand)
                                    }
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BSmartColor.tertiaryText)

                            Text(accountActivity.informativeTitle(for: update))
                                .font(.caption)
                                .foregroundStyle(BSmartColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            HStack(spacing: BSmartSpacing.small) {
                Image(systemName: "checkmark.shield")
                    .font(.caption2.weight(.bold))
                Text(auditLabel)
                    .font(.caption2)
                Spacer()
                if let sourceURL {
                    Link(destination: sourceURL) {
                        Label("Open source".bSmartLocalized, systemImage: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                    }
                }
            }
            .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(BSmartSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private var evidenceTitle: String {
        activity.isSmartAccount ? "Original text".bSmartLocalized : "Public account evidence".bSmartLocalized
    }

    private var renderedEvidenceText: String {
        guard case let .account(accountActivity) = activity else {
            if case let .money(movement) = activity { return moneyAuditText(movement) }
            return ""
        }
        let update = accountActivity.latest
        if showsOriginal { return originalEvidence(for: update) }
        return localizedEvidence(for: update)
    }

    private var hasTranslation: Bool {
        guard case let .account(accountActivity) = activity else { return false }
        return translation(for: accountActivity.latest) != nil
    }

    private func localizedEvidence(for update: SmartAccountUpdate) -> String {
        translation(for: update) ?? localizedFullTextFallback(for: update)
    }

    private func translation(for update: SmartAccountUpdate) -> String? {
        if BSmartLocalization.isSimplifiedChinese {
            return update.translatedTextZH?.nilIfBlank ?? update.translatedText?.nilIfBlank
        }
        return update.translatedTextEN?.nilIfBlank
    }

    private func localizedFullTextFallback(for update: SmartAccountUpdate) -> String {
        originalEvidence(for: update)
    }

    private func originalEvidence(for update: SmartAccountUpdate) -> String {
        update.originalText?.nilIfBlank ?? "Full original text unavailable".bSmartLocalized
    }

    private var auditLabel: String {
        switch activity {
        case let .account(activity):
            let update = activity.latest
            return "%@ · published %@".bSmartLocalized(update.platform, update.publishedAt.bSmartDataTimestamp)
        case let .money(movement):
            return "%@ · observed %@".bSmartLocalized(movement.market, movement.observedAt.bSmartDataTimestamp)
        }
    }

    private var sourceURL: URL? {
        switch activity {
        case let .account(activity): activity.latest.sourceURL ?? activity.latest.evidenceURL
        case let .money(movement): movement.evidenceURL
        }
    }
}

private func isSpecifiedHorizon(_ horizon: String) -> Bool {
    let normalized = horizon.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !normalized.isEmpty && !["unknown", "unspecified", "n/a", "na", "none", "null", "未明确", "未知"].contains(normalized)
}

private func compactRelativeTime(_ date: Date) -> String {
    let seconds = max(0, Date().timeIntervalSince(date))
    if seconds < 60 { return "now".bSmartLocalized }
    if seconds < 3_600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
    if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }
    return "\(Int(seconds / 604_800))w"
}

private func accountMetadata(_ update: SmartAccountUpdate) -> String {
    var parts = [update.platform]
    if let followers = update.authorFollowersCount {
        parts.append("%@ followers".bSmartLocalized(compactCountForToday(followers)))
    }
    parts.append(update.publishedAt.bSmartRelativeTimestamp)
    return parts.joined(separator: " · ")
}

private func accountDisplayText(_ update: SmartAccountUpdate) -> String {
    if BSmartLocalization.isSimplifiedChinese,
       let translated = update.translatedTextZH?.nilIfBlank ?? update.translatedText?.nilIfBlank {
        return translated
    }
    if !BSmartLocalization.isSimplifiedChinese,
       let translated = update.translatedTextEN?.nilIfBlank {
        return translated
    }
    return update.thesis
}

private func accountRank(_ update: SmartAccountUpdate) -> String {
    let raw = update.platformPercentile
    let percentage = max(1, Int(ceil(raw > 1 ? raw : raw * 100)))
    return "Top %d%%".bSmartLocalized(percentage)
}

private func positionContext(_ position: PortfolioPosition?, ticker: String) -> String {
    guard let position else { return ticker }
    if position.isPosition {
        var parts: [String] = []
        if let weight = position.portfolioWeight {
            parts.append("%@ of portfolio".bSmartLocalized(
                weight.formatted(.percent.precision(.fractionLength(0)))
            ))
        } else {
            parts.append("Held position".bSmartLocalized)
        }
        if position.averageCost > 0 {
            parts.append("avg %@".bSmartLocalized(
                position.averageCost.formatted(.bSmartDollars.precision(.fractionLength(2)))
            ))
        }
        return "\(ticker) · \(parts.joined(separator: " · "))"
    }
    return "%@ · Watchlist".bSmartLocalized(ticker)
}

private func moneyObservation(_ movement: TodayMoneyActivity) -> String {
    if movement.transactionCount > 1 {
        var text = "Observed %d transactions averaging %@ each, totaling %@ on %@"
            .bSmartLocalized(
                movement.transactionCount,
                compactUSD(abs(movement.notionalChange) / Double(movement.transactionCount)),
                compactUSD(abs(movement.notionalChange)),
                movement.market
            )
        if let leverage = movement.leverage {
            text += " · %@x leverage".bSmartLocalized(
                leverage.formatted(.number.precision(.fractionLength(1)))
            )
        }
        return text + ". " + "This describes observable capital activity, not motive.".bSmartLocalized
    }

    return "Observed position changed from %@ to %@ on %@. This is a public account action, not a stated investment thesis."
        .bSmartLocalized(
            compactUSD(movement.notionalBefore),
            compactUSD(movement.notionalAfter),
            movement.market
        )
}

private func moneyAuditText(_ movement: TodayMoneyActivity) -> String {
    var details = [
        "Action: %@".bSmartLocalized(movement.action.label.bSmartLocalized),
        "Before: %@".bSmartLocalized(compactUSD(movement.notionalBefore)),
        "After: %@".bSmartLocalized(compactUSD(movement.notionalAfter)),
        "Change: %@".bSmartLocalized(compactSignedUSD(movement.notionalChange)),
    ]
    if movement.transactionCount > 1 {
        details.append("Transactions: %d".bSmartLocalized(movement.transactionCount))
    }
    if let leverage = movement.leverage {
        details.append("Leverage: %@x".bSmartLocalized(
            leverage.formatted(.number.precision(.fractionLength(1)))
        ))
    }
    return details.joined(separator: " · ")
}

private func compactUSD(_ value: Double) -> String {
    switch abs(value) {
    case 1_000_000...:
        return String(format: "$%.1fM", value / 1_000_000)
    case 1_000...:
        return String(format: "$%.1fK", value / 1_000)
    default:
        return value.formatted(.bSmartDollars.precision(.fractionLength(0)))
    }
}

private func compactSignedUSD(_ value: Double) -> String {
    (value >= 0 ? "+" : "-") + compactUSD(abs(value))
}

private func compactCountForToday(_ value: Int) -> String {
    switch value {
    case 1_000_000...:
        return String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...:
        return String(format: "%.1fK", Double(value) / 1_000)
    default:
        return value.formatted()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct EventCard: View {
    let signal: PortfolioSignal
    let personalization: PortfolioSignalPersonalization
    let userState: SignalUserState
    let isPriority: Bool

    var body: some View {
        if isPriority {
            priorityCard
        } else {
            compactRow
        }
    }

    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.small) {
                Circle()
                    .fill(personalization.attention.color)
                    .frame(width: 6, height: 6)
                Text("%@ · %@".bSmartLocalized(signal.ticker, personalization.attention.label.bSmartLocalized))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(personalization.attention.color)
                if !userState.isRead {
                    Text("NEW".bSmartLocalized)
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.65)
                        .foregroundStyle(BSmartColor.pulse)
                }
                Spacer()
                Text(signal.occurredAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Text(signal.title.bSmartLocalized)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            Text(signal.summary.bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: BSmartSpacing.small) {
                Image(systemName: relationshipSymbol)
                    .font(.caption2.weight(.bold))
                Text(relationshipLabel.bSmartLocalized)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(signal.direction.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(signal.direction.color)
            }
            .foregroundStyle(relationshipColor)
            .padding(.top, BSmartSpacing.small)
            .overlay(alignment: .top) {
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            }

            HStack(spacing: BSmartSpacing.small) {
                relationshipContext
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: BSmartSpacing.small)

                if signal.smartMoneyCoverage == .unavailable {
                    Text(signal.smartMoneyCoverage.label)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.gold)
                        .lineLimit(1)
                }

                if userState.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                        .accessibilityLabel("Saved")
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens the signal evidence and portfolio context")
        .bSmartPanel(
            padding: BSmartSpacing.large,
            fill: BSmartColor.surface,
            border: BSmartColor.pulse.opacity(0.42)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BSmartColor.pulse)
                .frame(width: 3)
                .padding(.vertical, 1)
        }
    }

    private var compactRow: some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: signal.ticker, size: 36)
                .bSmartTickerDestination(signal.ticker)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    if !userState.isRead {
                        Circle()
                            .fill(BSmartColor.pulse)
                            .frame(width: 5, height: 5)
                    }
                    Text(signal.title.bSmartLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Text(signal.summary.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Label(relationshipLabel.bSmartLocalized, systemImage: relationshipSymbol)
                        .foregroundStyle(relationshipColor)
                    Text("·")
                    relationshipContext
                    if signal.smartMoneyCoverage == .unavailable {
                        Text("·")
                        Text(signal.smartMoneyCoverage.label)
                            .foregroundStyle(BSmartColor.gold)
                    }
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Text(signal.occurredAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(BSmartSpacing.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens the signal evidence and portfolio context")
    }

    private var leadEvidence: PortfolioSignalEvidence? {
        signal.evidence.max { $0.observedAt < $1.observedAt }
    }

    private var localizedLeadMetric: String? {
        guard let metric = leadEvidence?.metric else { return nil }
        if metric.hasPrefix("Score ") {
            return "Score %@".bSmartLocalized(String(metric.dropFirst("Score ".count)))
        }
        return metric
    }

    private var relationshipLabel: String {
        switch signal.kind {
        case .confirmation: "Views and capital agree"
        case .divergence: "Views and capital diverge"
        case .accountLeads: "Account view moved first"
        case .moneyLeads: "Capital moved first"
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus: "Smart Account changed"
        case .smartMoneyMovement: "Smart Money changed"
        }
    }

    private var relationshipSymbol: String {
        switch signal.kind {
        case .confirmation: "checkmark.seal.fill"
        case .divergence: "arrow.left.arrow.right"
        case .accountLeads: "person.wave.2"
        case .moneyLeads: "wallet.bifold"
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus: "person.crop.circle.badge.clock"
        case .smartMoneyMovement: "arrow.up.arrow.down"
        }
    }

    private var relationshipColor: Color {
        switch signal.kind {
        case .confirmation: BSmartColor.brand
        case .divergence: BSmartColor.bear
        case .accountLeads, .smartAccountNewView, .smartAccountShift, .smartAccountConsensus: BSmartColor.sky
        case .moneyLeads, .smartMoneyMovement: BSmartColor.gold
        }
    }

    @ViewBuilder
    private var relationshipContext: some View {
        switch personalization.relationship {
        case .position:
            Label(personalization.localizedContextSummary, systemImage: "briefcase.fill")
                .foregroundStyle(BSmartColor.primaryText)
        case .watchlist:
            Label("Watching", systemImage: "eye")
                .foregroundStyle(BSmartColor.sky)
        case .untracked:
            Label("Not tracked", systemImage: "plus.circle")
                .foregroundStyle(BSmartColor.gold)
        }
    }

    private var accessibilitySummary: String {
        let readState = userState.isRead ? "Read" : "Unread"
        let relation = switch personalization.relationship {
        case .position: "held position"
        case .watchlist: "watchlist"
        case .untracked: "not tracked"
        }
        return "\(readState), \(signal.ticker), \(personalization.attention.label), \(signal.title), \(relation), \(signal.kind.label)"
    }
}

private struct OpportunityRadarPreview: View {
    let signal: PortfolioSignal
    let count: Int

    var body: some View {
        HStack(spacing: BSmartSpacing.medium) {
            Image(systemName: "scope")
                .font(.headline.weight(.bold))
                .foregroundStyle(BSmartColor.gold)
                .frame(width: 42, height: 42)
                .background(BSmartColor.gold.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(signal.ticker) · \(signal.kind.label)")
                    .font(.subheadline.weight(.bold))
                Text(signal.title.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: BSmartSpacing.small)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(count)")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                Text("to review")
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .bSmartSurface(padding: BSmartSpacing.medium)
    }
}
