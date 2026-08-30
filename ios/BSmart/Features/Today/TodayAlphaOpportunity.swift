import SwiftUI

enum TodayAlphaOpportunitySource: Hashable {
    case account([SmartAccountUpdate])
    case money([SmartMoneyMovement])
}

struct TodayAlphaOpportunity: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case smartAccount
        case smartMoney
    }

    let ticker: String
    let companyName: String
    let source: TodayAlphaOpportunitySource
    let sourceCount: Int
    let occurredAt: Date
    let priority: Double
    let lookbackDays: Int
    let sourceRankLabels: [String: String]

    var id: String { "smart-alpha:\(kind.rawValue):\(ticker.uppercased())" }

    var kind: Kind {
        switch source {
        case .account: .smartAccount
        case .money: .smartMoney
        }
    }

    var localizedSourceLabel: String {
        switch kind {
        case .smartAccount: "Smart Account"
        case .smartMoney: "Smart Money"
        }
    }

    var localizedHeadline: String {
        switch source {
        case let .account(updates):
            guard let update = updates.first else { return ticker }
            let thesis = conciseAlphaText(localizedAlphaText(update), limit: 66)
            if updates.count > 1 {
                return "%d top Smart Accounts independently surfaced %@: %@"
                    .bSmartLocalized(updates.count, ticker, thesis)
            }
            return "%@ surfaced %@: %@".bSmartLocalized(update.authorName, ticker, thesis)
        case let .money(movements):
            guard let movement = movements.first else { return ticker }
            if movements.count > 1 {
                return "%d high-score public accounts acted on %@ before it became crowded"
                    .bSmartLocalized(movements.count, ticker)
            }
            return "%@ %@ %@ %@ exposure"
                .bSmartLocalized(
                    movement.publicIdentity.displayName,
                    movement.action.label.lowercased(),
                    movement.direction.label.lowercased(),
                    ticker
                )
        }
    }

    var localizedSummary: String {
        switch source {
        case .account:
            return "Only %d top-ranked source(s) covered %@ in the last %d days. It has not entered Smart Consensus."
                .bSmartLocalized(sourceCount, ticker, lookbackDays)
        case let .money(movements):
            let change = movements.reduce(0) { $0 + abs($1.notionalChange) }
            return "Observed exposure changed by %@ across %d qualified public account(s); no broader Smart Money cluster yet."
                .bSmartLocalized(alphaCurrency(change), sourceCount)
        }
    }

    var localizedDiscoveryType: String {
        switch source {
        case let .account(updates):
            guard let lifecycle = updates.first?.lifecycle else { return "New research lead".bSmartLocalized }
            switch lifecycle {
            case .new: return "First coverage".bSmartLocalized
            case .reversed: return "Direction reversed".bSmartLocalized
            case .strengthened: return "View strengthened".bSmartLocalized
            case .weakened: return "View weakened".bSmartLocalized
            case .closed: return "View closed".bSmartLocalized
            case .invalidated: return "View invalidated".bSmartLocalized
            }
        case let .money(movements):
            return movements.first?.action.label.bSmartLocalized ?? "Capital action".bSmartLocalized
        }
    }

    var localizedRankMetric: String {
        switch source {
        case let .account(updates):
            let percentile = updates.map { normalizedAlphaPercentile($0.platformPercentile) }.min() ?? 1
            return "Top %d%%".bSmartLocalized(max(1, Int(ceil(percentile * 100))))
        case let .money(movements):
            let score = movements.map(\.accountScore).max() ?? 0
            return "Score %@".bSmartLocalized(score.formatted(.number.precision(.fractionLength(0))))
        }
    }

    var localizedCoverageMetric: String {
        "%d source(s) / %dD".bSmartLocalized(sourceCount, lookbackDays)
    }

    var localizedWhySurfaced: String {
        switch source {
        case let .account(updates):
            let ranks = updates
                .map { max(1, Int(ceil(normalizedAlphaPercentile($0.platformPercentile) * 100))) }
            let bestRank = ranks.min() ?? 10
            return "The best source ranks in the top %d%% and the view contains a ticker, direction and decision-relevant thesis. Only %d qualified source(s) covered %@ during the lookback window, so this remains an individual discovery rather than a consensus."
                .bSmartLocalized(bestRank, sourceCount, ticker)
        case let .money(movements):
            let change = movements.reduce(0) { $0 + abs($1.notionalChange) }
            return "The action is material enough to change visible exposure by %@, while only %d qualified public account(s) acted on %@ during the lookback window."
                .bSmartLocalized(alphaCurrency(change), sourceCount, ticker)
        }
    }

    var localizedRiskBoundary: String {
        switch source {
        case let .account(updates):
            if let invalidation = updates.compactMap(\.invalidation).first, !invalidation.isEmpty {
                return invalidation
            }
            return "This is an individual high-ranked view, not a market consensus. Review the original thesis and wait for later evidence or a stated invalidation condition."
                .bSmartLocalized
        case .money:
            return "Public position snapshots show exposure changes, not the account's motive or a guaranteed executable fill. The position may change before the next snapshot."
                .bSmartLocalized
        }
    }

    var evidenceURL: URL? {
        switch source {
        case let .account(updates): updates.first?.sourceURL ?? updates.first?.evidenceURL
        case let .money(movements): movements.first?.evidenceURL
        }
    }

    var accountPriceEvidence: SmartAccountPriceEvidence? {
        guard case let .account(updates) = source else { return nil }
        return updates.compactMap(\.priceEvidence).max { $0.candles.count < $1.candles.count }
    }

    static func opportunities(
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement],
        excluding excludedTickers: Set<String>,
        lookbackDays: Int = 30,
        maximumSourceCount: Int = 2
    ) -> [TodayAlphaOpportunity] {
        let normalizedExcluded = Set(excludedTickers.map { $0.uppercased() })
        let referenceDate = (accountUpdates.map(\.publishedAt) + moneyMovements.map(\.observedAt)).max()
            ?? Date()
        let cutoff = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -lookbackDays,
            to: referenceDate
        ) ?? referenceDate.addingTimeInterval(-Double(lookbackDays) * 86_400)

        let accountCandidates = accountOpportunities(
            from: accountUpdates,
            cutoff: cutoff,
            referenceDate: referenceDate,
            excludedTickers: normalizedExcluded,
            lookbackDays: lookbackDays,
            maximumSourceCount: maximumSourceCount
        )
        let primaryAccount = accountCandidates.first
        let reservedTicker = primaryAccount?.ticker.uppercased()
        let primaryMoney = moneyOpportunities(
            from: moneyMovements,
            cutoff: cutoff,
            referenceDate: referenceDate,
            excludedTickers: normalizedExcluded,
            lookbackDays: lookbackDays,
            maximumSourceCount: maximumSourceCount
        ).first { $0.ticker.uppercased() != reservedTicker }

        return [primaryAccount, primaryMoney].compactMap { $0 }
    }

    private static func accountOpportunities(
        from updates: [SmartAccountUpdate],
        cutoff: Date,
        referenceDate: Date,
        excludedTickers: Set<String>,
        lookbackDays: Int,
        maximumSourceCount: Int
    ) -> [TodayAlphaOpportunity] {
        let qualified = updates.filter { update in
            update.publishedAt >= cutoff
                && !excludedTickers.contains(update.ticker.uppercased())
                && normalizedAlphaPercentile(update.platformPercentile) <= 0.10
                && [.new, .strengthened, .reversed].contains(update.lifecycle)
                && (update.evidenceURL != nil || update.sourceURL != nil)
        }

        return Dictionary(grouping: qualified, by: { $0.ticker.uppercased() })
            .compactMap { ticker, tickerUpdates -> TodayAlphaOpportunity? in
                var latestByAuthor: [String: SmartAccountUpdate] = [:]
                for update in tickerUpdates {
                    let key = update.authorId.lowercased()
                    if latestByAuthor[key].map({ $0.publishedAt < update.publishedAt }) ?? true {
                        latestByAuthor[key] = update
                    }
                }
                guard !latestByAuthor.isEmpty, latestByAuthor.count <= maximumSourceCount else { return nil }
                let selected = latestByAuthor.values.sorted {
                    let lhsPriority = accountPriority($0, referenceDate: referenceDate, lookbackDays: lookbackDays)
                    let rhsPriority = accountPriority($1, referenceDate: referenceDate, lookbackDays: lookbackDays)
                    if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                    return $0.publishedAt > $1.publishedAt
                }
                guard let primary = selected.first else { return nil }
                return TodayAlphaOpportunity(
                    ticker: ticker,
                    companyName: primary.companyName,
                    source: .account(selected),
                    sourceCount: selected.count,
                    occurredAt: selected.map(\.publishedAt).max() ?? primary.publishedAt,
                    priority: accountPriority(primary, referenceDate: referenceDate, lookbackDays: lookbackDays),
                    lookbackDays: lookbackDays,
                    sourceRankLabels: Dictionary(uniqueKeysWithValues: selected.map { update in
                        let percentile = max(1, Int(ceil(normalizedAlphaPercentile(update.platformPercentile) * 100)))
                        return (update.authorId.lowercased(), "Top %d%%".bSmartLocalized(percentile))
                    })
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.occurredAt > rhs.occurredAt
            }
    }

    private static func moneyOpportunities(
        from movements: [SmartMoneyMovement],
        cutoff: Date,
        referenceDate: Date,
        excludedTickers: Set<String>,
        lookbackDays: Int,
        maximumSourceCount: Int
    ) -> [TodayAlphaOpportunity] {
        let globalRankByAccount = Dictionary(grouping: movements, by: { $0.accountId.lowercased() })
            .map { accountID, accountMovements in
                (accountID, accountMovements.map(\.accountScore).max() ?? 0)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0 < rhs.0
            }
            .enumerated()
            .reduce(into: [String: Int]()) { result, entry in
                result[entry.element.0] = entry.offset + 1
            }

        let qualified = movements.filter { movement in
            let relativeChange = abs(movement.notionalChange) / max(abs(movement.notionalBefore), 1)
            let material = abs(movement.notionalChange) >= 250_000 || relativeChange >= 0.20
            return movement.observedAt >= cutoff
                && !excludedTickers.contains(movement.ticker.uppercased())
                && movement.accountScore >= 75
                && [.opened, .increased, .flipped].contains(movement.action)
                && material
                && movement.evidenceURL != nil
        }

        return Dictionary(grouping: qualified, by: { $0.ticker.uppercased() })
            .compactMap { ticker, tickerMovements -> TodayAlphaOpportunity? in
                var latestByAccount: [String: SmartMoneyMovement] = [:]
                for movement in tickerMovements {
                    let key = movement.accountId.lowercased()
                    if latestByAccount[key].map({ $0.observedAt < movement.observedAt }) ?? true {
                        latestByAccount[key] = movement
                    }
                }
                guard !latestByAccount.isEmpty, latestByAccount.count <= maximumSourceCount else { return nil }
                let selected = latestByAccount.values.sorted {
                    let lhsPriority = moneyPriority($0, referenceDate: referenceDate, lookbackDays: lookbackDays)
                    let rhsPriority = moneyPriority($1, referenceDate: referenceDate, lookbackDays: lookbackDays)
                    if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
                    return $0.observedAt > $1.observedAt
                }
                guard let primary = selected.first else { return nil }
                return TodayAlphaOpportunity(
                    ticker: ticker,
                    companyName: primary.companyName,
                    source: .money(selected),
                    sourceCount: selected.count,
                    occurredAt: selected.map(\.observedAt).max() ?? primary.observedAt,
                    priority: moneyPriority(primary, referenceDate: referenceDate, lookbackDays: lookbackDays),
                    lookbackDays: lookbackDays,
                    sourceRankLabels: Dictionary(uniqueKeysWithValues: selected.map { movement in
                        let accountID = movement.accountId.lowercased()
                        let rank = globalRankByAccount[accountID] ?? 0
                        return (accountID, rank > 0 ? "#\(rank)" : "Score %@".bSmartLocalized(
                            movement.accountScore.formatted(.number.precision(.fractionLength(0)))
                        ))
                    })
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.occurredAt > rhs.occurredAt
            }
    }

    private static func accountPriority(
        _ update: SmartAccountUpdate,
        referenceDate: Date,
        lookbackDays: Int
    ) -> Double {
        let quality = 1 - normalizedAlphaPercentile(update.platformPercentile)
        let lifecycle: Double = switch update.lifecycle {
        case .reversed: 1
        case .new: 0.92
        case .strengthened: 0.82
        default: 0.4
        }
        let specificityItems = [
            update.targetPrice != nil,
            update.invalidation?.isEmpty == false,
            isSpecifiedAlphaHorizon(update.horizon),
        ]
        let specificity = Double(specificityItems.filter { $0 }.count) / 3
        let recency = alphaRecency(
            update.publishedAt,
            referenceDate: referenceDate,
            lookbackDays: lookbackDays
        )
        return (quality * 0.45) + (lifecycle * 0.25) + (specificity * 0.15) + (recency * 0.15)
    }

    private static func moneyPriority(
        _ movement: SmartMoneyMovement,
        referenceDate: Date,
        lookbackDays: Int
    ) -> Double {
        let quality = min(max((movement.accountScore - 75) / 25, 0), 1)
        let action: Double = switch movement.action {
        case .flipped: 1
        case .opened: 0.92
        case .increased: 0.78
        default: 0.35
        }
        let magnitude = min(log10(max(abs(movement.notionalChange), 1)) / 7, 1)
        let recency = alphaRecency(
            movement.observedAt,
            referenceDate: referenceDate,
            lookbackDays: lookbackDays
        )
        return (quality * 0.40) + (action * 0.25) + (magnitude * 0.20) + (recency * 0.15)
    }

    private static func alphaRecency(
        _ date: Date,
        referenceDate: Date,
        lookbackDays: Int
    ) -> Double {
        let age = max(referenceDate.timeIntervalSince(date), 0)
        return max(0, 1 - age / (Double(lookbackDays) * 86_400))
    }
}

struct TodayAlphaOpportunityRail: View {
    let opportunities: [TodayAlphaOpportunity]
    @Namespace private var alphaTransition
    @State private var visibleOpportunityID: String?

    private var selectedIndex: Int {
        guard let visibleOpportunityID,
              let index = opportunities.firstIndex(where: { $0.id == visibleOpportunityID })
        else { return 0 }
        return index
    }

    var body: some View {
        VStack(spacing: BSmartSpacing.medium) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: BSmartSpacing.medium) {
                    ForEach(opportunities) { opportunity in
                        NavigationLink {
                            TodayAlphaOpportunityDetailView(opportunity: opportunity)
                                .bSmartZoomNavigationTransition(
                                    sourceID: opportunity.id,
                                    in: alphaTransition
                                )
                        } label: {
                            TodayAlphaOpportunityCard(opportunity: opportunity)
                                .bSmartMatchedTransitionSource(
                                    id: opportunity.id,
                                    in: alphaTransition
                                )
                        }
                        .id(opportunity.id)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.smart-alpha.\(opportunity.kind.rawValue).\(opportunity.ticker.lowercased())")
                    }
                }
                .scrollTargetLayout()
                .padding(.trailing, BSmartSpacing.large)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $visibleOpportunityID)

            TodayCarouselProgress(count: opportunities.count, selectedIndex: selectedIndex)
        }
        .onAppear {
            if visibleOpportunityID == nil { visibleOpportunityID = opportunities.first?.id }
        }
        .onChange(of: opportunities.map(\.id)) { _, ids in
            if visibleOpportunityID.map({ ids.contains($0) }) != true {
                visibleOpportunityID = ids.first
            }
        }
    }
}

private struct TodayAlphaOpportunityCard: View {
    let opportunity: TodayAlphaOpportunity

    private var accent: Color {
        opportunity.kind == .smartAccount ? BSmartColor.pulse : BSmartColor.sky
    }

    private var fill: Color {
        opportunity.kind == .smartAccount
            ? BSmartColor.pulse.opacity(0.06)
            : BSmartColor.sky.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityBand

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SMART ALPHA")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(BSmartColor.secondaryText)
                }

                Text(opportunity.localizedHeadline)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)

                Text(opportunity.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 5)

                Spacer(minLength: 6)

                subjectEvidenceStrip

                HStack(spacing: 0) {
                    alphaMetric("Discovery", opportunity.localizedDiscoveryType)
                    alphaMetric("Coverage", opportunity.localizedCoverageMetric)
                    alphaMetric("Updated", opportunity.occurredAt.bSmartRelativeTimestamp)
                }
                .padding(.top, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                }
            }
            .padding(BSmartSpacing.large)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 344, height: 300, alignment: .topLeading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(accent.opacity(0.48), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
    }

    private var identityBand: some View {
        HStack(spacing: BSmartSpacing.small) {
            BSmartAssetMark(ticker: opportunity.ticker, size: 36)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.ticker)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text(opportunity.localizedSourceLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Spacer(minLength: BSmartSpacing.small)

            headerActorRanks
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(accent.opacity(0.055))
        .overlay(alignment: .bottom) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var headerActorRanks: some View {
        HStack(spacing: 6) {
            switch opportunity.source {
            case let .account(updates):
                ForEach(Array(updates.prefix(2))) { update in
                    VStack(spacing: 2) {
                        BSmartAvatar(
                            url: update.authorAvatarURL,
                            name: update.authorName,
                            size: 28,
                            fallbackColor: update.direction.color
                        )
                        .overlay { Circle().stroke(accent, lineWidth: 1.1) }
                        Text(opportunity.sourceRankLabels[update.authorId.lowercased()] ?? opportunity.localizedRankMetric)
                            .font(.system(size: 7, weight: .black).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                }
            case let .money(movements):
                ForEach(Array(movements.prefix(2))) { movement in
                    VStack(spacing: 2) {
                        BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 28)
                            .overlay { Circle().stroke(accent, lineWidth: 1.1) }
                        Text(opportunity.sourceRankLabels[movement.accountId.lowercased()] ?? opportunity.localizedRankMetric)
                            .font(.system(size: 7, weight: .black).monospacedDigit())
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subjectEvidenceStrip: some View {
        HStack(spacing: 8) {
            switch opportunity.source {
            case let .account(updates):
                ForEach(Array(updates.prefix(2))) { update in
                    accountEvidence(update)
                }
            case let .money(movements):
                ForEach(Array(movements.prefix(2))) { movement in
                    moneyEvidence(movement)
                }
            }
        }
    }

    private func accountEvidence(_ update: SmartAccountUpdate) -> some View {
        HStack(spacing: 7) {
            BSmartAvatar(
                url: update.authorAvatarURL,
                name: update.authorName,
                size: 28,
                fallbackColor: update.direction.color
            )
            .overlay { Circle().stroke(accent, lineWidth: 1.2) }

            VStack(alignment: .leading, spacing: 1) {
                Text(update.authorName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                Text("%@ · %@".bSmartLocalized(update.direction.label, update.horizon.bSmartLocalized))
                    .font(.system(size: 8, weight: .black).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func moneyEvidence(_ movement: SmartMoneyMovement) -> some View {
        HStack(spacing: 7) {
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 28)
                .overlay { Circle().stroke(accent, lineWidth: 1.2) }

            VStack(alignment: .leading, spacing: 1) {
                Text(movement.publicIdentity.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                Text("%@ · %@".bSmartLocalized(
                    movement.action.label.bSmartLocalized,
                    alphaCurrency(abs(movement.notionalChange))
                ))
                    .font(.system(size: 8, weight: .black).monospacedDigit())
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func alphaMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayAlphaOpportunityDetailView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    let opportunity: TodayAlphaOpportunity
    @State private var expandedUpdateIDs = Set<UUID>()

    private var accent: Color {
        opportunity.kind == .smartAccount ? BSmartColor.pulse : BSmartColor.sky
    }

    var body: some View {
        VStack(spacing: 0) {
            detailNavigationBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    hero
                    surfacedPanel
                    sourceSection

                    if let evidence = opportunity.accountPriceEvidence, !evidence.candles.isEmpty {
                        priceContext(evidence)
                    }

                    evidenceSection
                    riskSection
                }
                .padding(.bottom, BSmartSpacing.xxxLarge)
            }
            .background(BSmartColor.ink)
        }
        .background(BSmartColor.ink)
        .toolbar(.hidden, for: .navigationBar)
        .bSmartDetailPage()
        .bSmartPage()
    }

    private var detailNavigationBar: some View {
        HStack(spacing: BSmartSpacing.medium) {
            Button(action: dismissDetail) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .frame(width: 42, height: 42)
                    .background(BSmartColor.elevated, in: Circle())
                    .overlay { Circle().stroke(BSmartColor.line, lineWidth: 0.75) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back".bSmartLocalized)
            .accessibilityIdentifier("today.smart-alpha.back")

            Spacer(minLength: 0)

            Text(opportunity.ticker)
                .font(.headline.weight(.black))
                .lineLimit(1)

            Spacer(minLength: 0)

            Color.clear.frame(width: 42, height: 42).accessibilityHidden(true)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, 7)
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
    }

    private func dismissDetail() {
        router.restoreTabBarImmediately()
        DispatchQueue.main.async {
            dismiss()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.large) {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: opportunity.ticker, size: 48)
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("SMART ALPHA")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                    Text(opportunity.ticker)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                    Text(opportunity.companyName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(opportunity.localizedSourceLabel)
                    Text(opportunity.occurredAt.bSmartRelativeTimestamp)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.secondaryText)
            }

            Text(opportunity.localizedHeadline)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Research candidate · not a recommendation".bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.gold)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.top, BSmartSpacing.medium)
    }

    private var surfacedPanel: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            Text("WHY THIS SURFACED".bSmartLocalized)
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(accent)

            Text(opportunity.localizedWhySurfaced)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineSpacing(3)

            HStack(spacing: 0) {
                detailMetric("Discovery", opportunity.localizedDiscoveryType)
                detailMetric("Rank", opportunity.localizedRankMetric)
                detailMetric("Coverage", opportunity.localizedCoverageMetric)
            }
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Who surfaced it", detail: nil)

            VStack(spacing: 0) {
                switch opportunity.source {
                case let .account(updates):
                    ForEach(Array(updates.enumerated()), id: \.element.id) { index, update in
                        if index > 0 { Divider().overlay(BSmartColor.line) }
                        Button {
                            toggleOpinion(update.id)
                        } label: {
                            alphaAccountRow(update, isExpanded: expandedUpdateIDs.contains(update.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.smart-alpha-account.\(index)")

                        if expandedUpdateIDs.contains(update.id) {
                            TodayInlineAccountOpinion(update: update)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                case let .money(movements):
                    ForEach(Array(movements.enumerated()), id: \.element.id) { index, movement in
                        if index > 0 { Divider().overlay(BSmartColor.line) }
                        alphaMoneyRow(movement)
                    }
                }
            }
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.6)
            }
        }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private func alphaAccountRow(_ update: SmartAccountUpdate, isExpanded: Bool) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAvatar(
                url: update.authorAvatarURL,
                name: update.authorName,
                size: 42,
                fallbackColor: update.direction.color
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(update.authorName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("%@ · %@ · %@".bSmartLocalized(
                    update.platform,
                    update.direction.label,
                    update.horizon
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
            }
            Spacer(minLength: BSmartSpacing.small)
            Text("Top %d%%".bSmartLocalized(
                max(1, Int(ceil(normalizedAlphaPercentile(update.platformPercentile) * 100)))
            ))
            .font(.subheadline.weight(.black))
            .foregroundStyle(accent)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(BSmartSpacing.medium)
        .contentShape(Rectangle())
    }

    private func alphaMoneyRow(_ movement: SmartMoneyMovement) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(movement.publicIdentity.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("%@ · %@ · %@".bSmartLocalized(
                    movement.market,
                    movement.action.label,
                    movement.direction.label
                ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
            }
            Spacer(minLength: BSmartSpacing.small)
            VStack(alignment: .trailing, spacing: 3) {
                Text(alphaCurrency(abs(movement.notionalChange)))
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .foregroundStyle(accent)
                Text("Score %@".bSmartLocalized(
                    movement.accountScore.formatted(.number.precision(.fractionLength(0)))
                ))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(BSmartSpacing.medium)
    }

    private func priceContext(_ evidence: SmartAccountPriceEvidence) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Price context", detail: nil)

            TodayEvidenceTimeline(
                ticker: opportunity.ticker,
                evidence: evidence,
                accountUpdates: alphaAccountUpdates,
                moneyMovements: alphaMoneyMovements
            )
        }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private var alphaAccountUpdates: [SmartAccountUpdate] {
        guard case let .account(updates) = opportunity.source else { return [] }
        return updates
    }

    private var alphaMoneyMovements: [SmartMoneyMovement] {
        guard case let .money(movements) = opportunity.source else { return [] }
        return movements
    }

    private func toggleOpinion(_ id: UUID) {
        withAnimation(BSmartMotion.quick) {
            if expandedUpdateIDs.contains(id) {
                expandedUpdateIDs.remove(id)
            } else {
                expandedUpdateIDs.insert(id)
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Original evidence", detail: nil)

            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                Text(localizedEvidenceText)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = opportunity.evidenceURL {
                    Link(destination: url) {
                        Label("Open evidence".bSmartLocalized, systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .overlay {
                                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                    .stroke(BSmartColor.brand, lineWidth: 0.8)
                            }
                    }
                }
            }
            .padding(BSmartSpacing.large)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.6)
            }
        }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text("RISK BOUNDARY".bSmartLocalized)
                .font(.system(size: 9, weight: .black))
                .tracking(0.7)
                .foregroundStyle(BSmartColor.gold)
            Text(opportunity.localizedRiskBoundary)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineSpacing(3)
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .overlay(alignment: .leading) { Rectangle().fill(BSmartColor.gold).frame(width: 2) }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private var localizedEvidenceText: String {
        switch opportunity.source {
        case let .account(updates):
            guard let update = updates.first else { return "No evidence available".bSmartLocalized }
            if BSmartLocalization.isSimplifiedChinese {
                return update.translatedTextZH ?? update.translatedText ?? update.originalText ?? update.thesis
            }
            return update.translatedTextEN ?? update.translatedText ?? update.originalText ?? update.thesis
        case let .money(movements):
            guard let movement = movements.first else { return "No evidence available".bSmartLocalized }
            return "Observed %@ %@ exposure change on %@. Visible notional moved from %@ to %@."
                .bSmartLocalized(
                    movement.action.label.lowercased(),
                    movement.direction.label.lowercased(),
                    movement.market,
                    alphaCurrency(movement.notionalBefore),
                    alphaCurrency(movement.notionalAfter)
                )
        }
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.bSmartLocalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func normalizedAlphaPercentile(_ value: Double) -> Double {
    min(max(value > 1 ? value / 100 : value, 0), 1)
}

private func isSpecifiedAlphaHorizon(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !normalized.isEmpty && !["unknown", "unspecified", "n/a", "—"].contains(normalized)
}

private func localizedAlphaText(_ update: SmartAccountUpdate) -> String {
    if BSmartLocalization.isSimplifiedChinese {
        return update.activityTitleZH
            ?? update.translatedTextZH
            ?? update.translatedText
            ?? update.thesis
    }
    return update.activityTitleEN
        ?? update.translatedTextEN
        ?? update.translatedText
        ?? update.thesis
}

private func conciseAlphaText(_ value: String, limit: Int) -> String {
    let compact = value
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard compact.count > limit else { return compact }
    return String(compact.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

private func alphaCurrency(_ value: Double) -> String {
    let absolute = abs(value)
    let sign = value < 0 ? "−" : ""
    let formatted: String
    switch absolute {
    case 1_000_000...:
        formatted = "$\((absolute / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
    case 1_000...:
        formatted = "$\((absolute / 1_000).formatted(.number.precision(.fractionLength(1))))K"
    default:
        formatted = absolute.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    return sign + formatted
}
