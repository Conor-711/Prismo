import Charts
import SwiftUI


private enum SmartAccountRankBand: String, CaseIterable, Identifiable {
    case all = "All ranks"
    case top = "Top 25%"
    case middle = "Middle 50%"
    case bottom = "Bottom 25%"

    var id: Self { self }

    func contains(_ percentile: Double) -> Bool {
        switch self {
        case .all: true
        case .top: percentile <= 0.25
        case .middle: percentile > 0.25 && percentile < 0.75
        case .bottom: percentile >= 0.75
        }
    }
}

private enum SmartAccountHorizonFilter: String, CaseIterable, Identifiable {
    case all = "All horizons"
    case short = "Short term"
    case medium = "Medium term"
    case long = "Long term"

    var id: Self { self }
}

private extension String {
    var shortWalletAddress: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }
}

struct SmartHubView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var language: AppLanguageStore
    @State private var selection: SmartSection = .accounts
    @State private var searchText = ""
    @State private var followingOnly = false
    @State private var isShowingFilters = false
    @State private var accountPlatform = "All platforms"
    @State private var accountRankBand: SmartAccountRankBand = .all
    @State private var accountHorizon: SmartAccountHorizonFilter = .all
    @State private var accountSpecialty = "All sectors"
    @State private var accountStyle = "All styles"
    @State private var moneyStyle = "All styles"
    @State private var moneySize = "All sizes"
    @State private var moneySide = "All sides"

    private var accountPlatforms: [String] {
        ["All platforms"] + Set(model.smartAccounts.map(\.platform)).sorted()
    }

    private var accountSpecialties: [String] {
        ["All sectors"] + Set(model.smartAccounts.map(\.specialty)).sorted()
    }

    private var accountStyles: [String] {
        ["All styles"] + Set(model.smartAccounts.map(\.resolvedStyle)).sorted()
    }

    private var filteredAccounts: [SmartAccountProfile] {
        model.smartAccounts.filter { account in
            (!followingOnly || model.isFollowingSmartAccount(account.id))
                && (accountPlatform == "All platforms" || account.platform == accountPlatform)
                && accountRankBand.contains(account.resolvedPlatformPercentile)
                && (accountHorizon == .all || account.horizon == accountHorizon.rawValue)
                && (accountSpecialty == "All sectors" || account.specialty == accountSpecialty)
                && (accountStyle == "All styles" || account.resolvedStyle == accountStyle)
                && (searchText.isEmpty
                    || account.name.localizedCaseInsensitiveContains(searchText)
                    || account.handle.localizedCaseInsensitiveContains(searchText)
                    || account.specialty.localizedCaseInsensitiveContains(searchText)
                    || account.resolvedTopTickers.contains { $0.localizedCaseInsensitiveContains(searchText) })
        }
        .sorted { lhs, rhs in
            if accountPlatform == "All platforms" {
                return lhs.resolvedRank < rhs.resolvedRank
            }
            return lhs.resolvedPlatformRank < rhs.resolvedPlatformRank
        }
    }

    private var filteredMoney: [SmartMoneySignal] {
        model.smartMoney.filter { signal in
            (!followingOnly || model.isFollowingSmartMoney(signal.id))
                && (moneyStyle == "All styles" || signal.resolvedStyle == moneyStyle)
                && (moneySize == "All sizes" || smartMoneySizeLabel(signal.sizeCohort) == moneySize)
                && (moneySide == "All sides" || signal.direction == moneySide)
                && (searchText.isEmpty
                    || signal.publicIdentity.displayName.localizedCaseInsensitiveContains(searchText)
                    || signal.ticker.localizedCaseInsensitiveContains(searchText)
                    || signal.resolvedPositions.contains { $0.symbol.localizedCaseInsensitiveContains(searchText) })
        }
        .sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
    }

    private var moneyStyles: [String] {
        ["All styles"] + Set(model.smartMoney.map(\.resolvedStyle)).sorted()
    }

    private var moneySizes: [String] {
        ["All sizes"] + Set(model.smartMoney.map { smartMoneySizeLabel($0.sizeCohort) }).sorted()
    }

    private var recentTickersByAccount: [String: [String]] {
        var tickersByAccount: [String: [String]] = [:]
        for update in model.smartAccountUpdates {
            let ticker = update.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !ticker.isEmpty else { continue }

            var tickers = tickersByAccount[update.authorId, default: []]
            guard tickers.count < 4, !tickers.contains(ticker) else { continue }
            tickers.append(ticker)
            tickersByAccount[update.authorId] = tickers
        }
        return tickersByAccount
    }

    var body: some View {
        BSmartCollapsingPager(
            selection: $selection, sections: SmartSection.allCases,
            pageIdentifier: { "smart.page.\($0.key)" },
            header: { _ in searchHeader }, tabs: { hubControls },
            content: { section in
                LazyVStack(alignment: .leading, spacing: 0) {
                    if section == .accounts { accountRows } else { moneyRows }
                }
            }, refresh: { await model.refreshLiveIntelligence() }
        )
        .background(BSmartColor.ink)
        .navigationTitle("Smart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { followingOnly.toggle() } label: {
                    Image(systemName: followingOnly ? "star.fill" : "star")
                        .foregroundStyle(followingOnly ? BSmartColor.brand : BSmartColor.primaryText)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel((followingOnly ? "Show all intelligence" : "Show followed intelligence only").bSmartLocalized)
                .accessibilityIdentifier("smart.following")
                .accessibilityAddTraits(followingOnly ? .isSelected : [])
            }
        }
        .onChange(of: selection) { _, _ in searchText = "" }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart.screen")
        .sheet(isPresented: $isShowingFilters) {
            smartFilterSheet.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .bSmartPage()
        .bSmartDetailPage()
    }

    private var searchHeader: some View {
        SmartHubSearchField(prompt: searchPrompt, query: $searchText)
            .id(selection)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, BSmartSpacing.large)
            .padding(.top, 8).padding(.bottom, 12)
    }

    private var hubControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmartHubTabs(selection: $selection, accountCount: model.smartAccounts.count, moneyCount: model.smartMoney.count)
            HStack(spacing: 12) {
                Text(summaryLabel).font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("smart.results-count")
                Spacer(minLength: 0)
                Button { isShowingFilters = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Filters".bSmartLocalized)
                        if !activeFilters.isEmpty {
                            Text("\(activeFilters.count)").monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(activeFilters.isEmpty ? BSmartColor.primaryText : BSmartColor.brand)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(selection == .accounts ? "smart.account.filters" : "smart.money.filters")
            }
            .padding(.horizontal, BSmartSpacing.large)
            if !activeFilters.isEmpty {
                HStack(spacing: 8) {
                    Text(activeFilters.map { $0.bSmartLocalized }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(BSmartColor.brand)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button { resetSelectedFilters() } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(BSmartColor.secondaryText)
                    .accessibilityLabel("Reset".bSmartLocalized)
                    .accessibilityIdentifier("smart.filters.clear")
                }
                .padding(.horizontal, BSmartSpacing.large)
            }
            if let freshness = selectedFreshness {
                Text("Checked %@".bSmartLocalized(freshness.checkedAt.bSmartDataTimestamp))
                    .font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
                    .padding(.horizontal, BSmartSpacing.large).padding(.bottom, 8)
                    .accessibilityIdentifier("smart.source-freshness")
            }
        }.background(BSmartColor.ink)
    }

    private var activeFilters: [String] {
        switch selection {
        case .accounts:
            [accountPlatform, accountRankBand.rawValue, accountHorizon.rawValue, accountSpecialty, accountStyle]
                .filter { !$0.hasPrefix("All ") }
        case .money:
            [moneyStyle, moneySize, moneySide].filter { !$0.hasPrefix("All ") }
        }
    }

    private var smartFilterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                if selection == .accounts {
                    SmartFilterOptions(title: "Platform", identifier: "platform", options: accountPlatforms,
                                       selection: $accountPlatform, optionTitle: { $0 }, showsPlatform: true)
                    SmartFilterOptions(title: "Rank band", identifier: "rank", options: SmartAccountRankBand.allCases,
                                       selection: $accountRankBand, optionTitle: { $0.rawValue })
                    SmartFilterOptions(title: "Best horizon", identifier: "horizon", options: SmartAccountHorizonFilter.allCases,
                                       selection: $accountHorizon, optionTitle: { $0.rawValue })
                    SmartFilterOptions(title: "Sector", identifier: "sector", options: accountSpecialties,
                                       selection: $accountSpecialty, optionTitle: { $0 })
                    SmartFilterOptions(title: "Style", identifier: "account-style", options: accountStyles,
                                       selection: $accountStyle, optionTitle: { $0 })
                } else {
                    SmartFilterOptions(title: "Style", identifier: "money-style", options: moneyStyles,
                                       selection: $moneyStyle, optionTitle: { $0 })
                    SmartFilterOptions(title: "Account size", identifier: "size", options: moneySizes,
                                       selection: $moneySize, optionTitle: { $0 })
                    SmartFilterOptions(title: "Direction", identifier: "direction", options: ["All sides", "Long", "Short"],
                                       selection: $moneySide, optionTitle: { $0 })
                }
                }
                .padding(20)
            }
            .accessibilityIdentifier("smart.filters.options")
            .background(BSmartColor.ink)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { isShowingFilters = false } label: {
                    Text("View %d results".bSmartLocalized(selection == .accounts ? filteredAccounts.count : filteredMoney.count))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BSmartColor.ink)
                .background(BSmartColor.brand)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("smart.filters.results")
                .accessibilityValue(String(selection == .accounts ? filteredAccounts.count : filteredMoney.count))
                .padding(16)
                .background(BSmartColor.ink)
            }
            .navigationTitle("Filters".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset".bSmartLocalized) { resetSelectedFilters() }
                        .accessibilityIdentifier("smart.filters.reset")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".bSmartLocalized) { isShowingFilters = false }
                }
            }
            .bSmartPage()
        }
    }

    private func resetSelectedFilters() {
        if selection == .accounts {
            accountPlatform = "All platforms"
            accountRankBand = .all
            accountHorizon = .all
            accountSpecialty = "All sectors"
            accountStyle = "All styles"
        } else {
            moneyStyle = "All styles"
            moneySize = "All sizes"
            moneySide = "All sides"
        }
    }

    private var selectedFreshness: BSmartDataFreshness? {
        switch selection {
        case .accounts: model.smartAccountFreshness
        case .money: model.smartMoneyFreshness
        }
    }


    @ViewBuilder
    private var accountRows: some View {
        let latestTickers = recentTickersByAccount
        if filteredAccounts.isEmpty {
            smartEmptyState
        } else {
            ForEach(Array(filteredAccounts.enumerated()), id: \.element.id) { index, account in
                BSmartDetailNavigationLink(id: "smart-account-\(account.id)", usesZoomTransition: false) {
                    SmartAccountDetailView(account: account)
                } label: {
                    SmartAccountRow(
                        rank: displayedRank(for: account, fallback: index + 1),
                        account: account,
                        recentTickers: latestTickers[account.id] ?? Array(account.resolvedTopTickers.prefix(4)),
                        isFollowing: model.isFollowingSmartAccount(account.id)
                    )
                }
                .accessibilityIdentifier(index == 0 ? "smart.account.row.first" : "smart.account.row.\(account.id)")
                Divider().overlay(BSmartColor.line)
            }
        }
    }

    @ViewBuilder
    private var moneyRows: some View {
        if !model.smartMoney.isEmpty {
            SmartMoneySourceStatus(signals: model.smartMoney)
                .accessibilityIdentifier("smart.money.source-status")
        }

        if filteredMoney.isEmpty {
            smartEmptyState
        } else {
            SmartMoneyCohortSummary(signals: filteredMoney)
                .accessibilityIdentifier("smart.money.cohort")

            ForEach(Array(filteredMoney.enumerated()), id: \.element.id) { index, signal in
                BSmartDetailNavigationLink(id: "smart-money-\(signal.id)") {
                    SmartMoneyDetailView(signal: signal)
                } label: {
                    SmartMoneyRow(
                        signal: signal,
                        isFollowing: model.isFollowingSmartMoney(signal.id)
                    )
                }
                .accessibilityIdentifier(index == 0 ? "smart.money.row.first" : "smart.money.row.\(signal.id)")
                Divider().overlay(BSmartColor.line)
            }
        }
    }

    private var smartEmptyState: some View {
        VStack(spacing: BSmartSpacing.medium) {
            Image(systemName: followingOnly ? "star.slash" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text((followingOnly ? "Nothing followed yet" : "No matching results").bSmartLocalized)
                .font(.headline)
            if !activeFilters.isEmpty {
                Button("Reset".bSmartLocalized) { resetSelectedFilters() }
                    .frame(minHeight: 44).tint(BSmartColor.brand)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSmartSpacing.xxxLarge)
    }

    private var summaryLabel: String {
        switch selection {
        case .accounts:
            "%d ranked · %d followed".bSmartLocalized(
                filteredAccounts.count,
                model.followedSmartAccountIDs.count
            )
        case .money:
            "%d accounts · %d followed".bSmartLocalized(
                filteredMoney.count,
                model.followedSmartMoneyIDs.count
            )
        }
    }

    private func displayedRank(for account: SmartAccountProfile, fallback: Int) -> Int {
        let rank = accountPlatform == "All platforms"
            ? account.resolvedRank
            : account.resolvedPlatformRank
        return rank > 0 ? rank : fallback
    }

    private var searchPrompt: String {
        selection == .accounts ? "Investor or specialty" : "Name or ticker"
    }
}


private extension View {
    func smartProfileCommand(accented: Bool, selected: Bool) -> some View {
        self
            .font(.subheadline.weight(.bold))
            .foregroundStyle(accented ? BSmartColor.brand : BSmartColor.primaryText)
            .frame(maxWidth: .infinity, minHeight: 42)
            .padding(.horizontal, BSmartSpacing.medium)
            .background(
                accented && selected
                    ? BSmartColor.brand.opacity(0.14)
                    : BSmartColor.elevated
            )
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(
                        accented ? BSmartColor.brand.opacity(selected ? 0.95 : 0.55) : BSmartColor.strongLine,
                        lineWidth: accented && selected ? 1.2 : 0.7
                    )
            }
            .contentShape(Rectangle())
    }
}



struct SmartAccountEvidenceDetailView: View {
    let update: SmartAccountUpdate
    var priceContextNote: String? = nil
    @State private var traderRefresh = 0

    var body: some View {
        OpinionDetailLayout(update: update) {
            OpinionTradersSection(opinionID: update.id, ticker: update.ticker,
                                 referencePrice: update.priceEvidence?.latestPrice, refresh: traderRefresh)
                .id(update.id)
                .accessibilityIdentifier("opinion.traders.section")
            OpinionReaderView(update: update)
            if !update.displayableSupportingSources.isEmpty {
                OpinionSupportingSourcesSection(sources: update.displayableSupportingSources)
            }
            if let settlement = update.settlement {
                settlementEvidence(settlement)
            }
            if let priceEvidence = update.priceEvidence {
                priceContext(priceEvidence)
            }
            if let priceContextNote {
                DisclosureGroup("About these prices".bSmartLocalized) {
                    Text(priceContextNote).font(.footnote)
                        .foregroundStyle(BSmartColor.secondaryText).padding(.top, 10)
                }.font(.subheadline)
            }
        }
        .accessibilityIdentifier("smart.account.evidence.detail")
        .bSmartDetailPage()
        .bSmartTradeDock(symbol: update.ticker, opinionSource: .init(opinionID: update.id, ticker: update.ticker, authorID: update.authorId),
                        onTradeDismiss: { traderRefresh += 1 })
        .bSmartPage()
    }

    private func settlementEvidence(_ settlement: SmartAccountSettlementEvidence) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Historical outcome",
                detail: "Direction-aware settlement at the stated horizon"
            )
            HStack {
                Label(
                    settlementResultLabel(settlement),
                    systemImage: settlement.actualHit == true ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.headline.weight(.bold))
                .foregroundStyle(settlement.actualHit == true ? BSmartColor.bull : BSmartColor.bear)
                Spacer()
                Text(settlement.horizon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            HStack(spacing: 0) {
                evidenceMetric(label: "Underlying return", value: percentLabel(settlement.tickerReturnPercent))
                Divider().overlay(BSmartColor.line)
                evidenceMetric(label: "vs S&P 500", value: percentLabel(settlement.marketExcessReturnPercent))
                Divider().overlay(BSmartColor.line)
                evidenceMetric(
                    label: settlement.industryBenchmarkTicker ?? "Industry ETF",
                    value: percentLabel(settlement.industryExcessReturnPercent)
                )
            }
            if let entry = settlement.entryPrice {
                Text("Entry %@%@".bSmartLocalized(
                    currency(entry),
                    settlement.exitPrice.map { " · Exit \(currency($0))" } ?? ""
                ))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(BSmartColor.line) }
    }

    private func priceContext(_ evidence: SmartAccountPriceEvidence) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Price timeline",
                detail: "Publication, entry and settlement windows on real daily OHLC"
            )
            EvidenceChartGuide(kind: "Price history", detail: "1–3 match evidence below")
            PriceEvidenceChart(update: update, evidence: evidence)
                .frame(height: 286)
            SmartAccountOpinionEvidenceList(update: update, evidence: evidence)
            PriceEvidenceMilestones(update: update, evidence: evidence, settlement: update.settlement)
        }
        .padding(.vertical, 8)
    }


    private func evidenceMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value.bSmartLocalized)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }


    private func settlementResultLabel(_ settlement: SmartAccountSettlementEvidence) -> String {
        guard settlement.status == "settled" else { return "Pending settlement".bSmartLocalized }
        return (settlement.actualHit == true ? "Historical hit" : "Historical miss").bSmartLocalized
    }

    private func percentLabel(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))) + "%"
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.bSmartDollars.precision(.fractionLength(value >= 100 ? 0 : 2)))
    }

}

private struct EvidenceChartGuide: View {
    let kind: String
    let detail: String

    var body: some View {
        Label(kind.bSmartLocalized, systemImage: "chart.xyaxis.line")
            .foregroundStyle(BSmartColor.secondaryText)
        .font(.caption2.weight(.semibold))
    }
}


private struct SmartAccountOpinionEvidenceList: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence

    private var displayedMarkers: [SmartAccountOpinionMarker] {
        guard !(evidence.opinionMarkers ?? []).isEmpty else { return [] }
        return RepresentativeWorkChartModel(update: update, evidence: evidence).markers.map(\.opinion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Opinion markers".bSmartLocalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Text("Top 3 by Score".bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            .padding(.bottom, BSmartSpacing.small)

            if displayedMarkers.isEmpty {
                opinionRow(
                    number: 1,
                    direction: update.direction,
                    horizon: update.horizon,
                    day: evidence.viewDay,
                    price: evidence.viewPrice,
                    contribution: update.representativeTickerContribution
                )
            } else {
                ForEach(Array(displayedMarkers.enumerated()), id: \.element.id) { index, marker in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    opinionRow(
                        number: index + 1,
                        direction: marker.direction,
                        horizon: marker.horizon,
                        day: marker.viewDay,
                        price: marker.viewPrice,
                        contribution: marker.contribution
                    )
                }
            }
        }
        .padding(BSmartSpacing.medium)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private func opinionRow(
        number: Int,
        direction: SignalDirection,
        horizon: String,
        day: String,
        price: Double,
        contribution: Double?
    ) -> some View {
        HStack(spacing: BSmartSpacing.small) {
            evidenceNumber(number, color: direction.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(direction.label)
                        .foregroundStyle(direction.color)
                    Text("·")
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Text(horizon)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .font(.caption.weight(.bold))
                Text("%@ at %@".bSmartLocalized(formattedDay(day), currency(price)))
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .monospacedDigit()
            }
            Spacer(minLength: BSmartSpacing.small)
            VStack(alignment: .trailing, spacing: 2) {
                Text(contributionLabel(contribution))
                    .font(.caption.weight(.black))
                    .foregroundStyle(BSmartColor.primaryText)
                    .monospacedDigit()
                Text("Score".bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(.vertical, BSmartSpacing.small)
        .accessibilityElement(children: .combine)
    }

    private func evidenceNumber(_ value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(.caption2.weight(.black))
            .foregroundStyle(BSmartColor.onAccent)
            .frame(width: 22, height: 22)
            .background(color)
            .clipShape(Circle())
    }

    private func contributionLabel(_ contribution: Double?) -> String {
        guard let contribution else { return "—" }
        return contribution.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
    }

    private func formattedDay(_ day: String) -> String {
        String(day.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.bSmartDollars.precision(.fractionLength(value >= 100 ? 0 : 2)))
    }
}

private struct PriceEvidenceMilestones: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence
    let settlement: SmartAccountSettlementEvidence?

    private struct Milestone: Identifiable {
        let label: String
        let day: String
        let price: Double?
        let color: Color

        var id: String { "\(label)-\(day)" }
    }

    private var milestones: [Milestone] {
        var values = [
            Milestone(
                label: "Published",
                day: evidence.viewDay,
                price: evidence.viewPrice,
                color: update.direction.color
            )
        ]
        if let day = settlement?.entryDay {
            values.append(Milestone(label: "Entry", day: day, price: settlement?.entryPrice, color: BSmartColor.gold))
        }
        if let day = settlement?.exitDay {
            values.append(Milestone(label: "Settled", day: day, price: settlement?.exitPrice, color: BSmartColor.sky))
        }
        return values
    }

    var body: some View {
        HStack(spacing: BSmartSpacing.small) {
            ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(milestone.color)
                            .frame(width: 6, height: 6)
                        Text(milestone.label.bSmartLocalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    Text(milestoneValue(milestone))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < milestones.count - 1 {
                    Divider()
                        .frame(height: 34)
                        .overlay(BSmartColor.line)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func milestoneValue(_ milestone: Milestone) -> String {
        let day = String(milestone.day.suffix(5)).replacingOccurrences(of: "-", with: "/")
        guard let price = milestone.price else { return day }
        let formattedPrice = price.formatted(.bSmartDollars.precision(.fractionLength(price >= 100 ? 0 : 2)))
        return "\(day) · \(formattedPrice)"
    }
}


private struct SmartMoneyEntryEvidenceList: View {
    let evidence: SmartMoneyRepresentativeEvidence

    private var displayedMarkers: [SmartMoneyEntryMarker] {
        evidence.priceEvidence.entryMarkers
            .sorted { $0.entryNotional > $1.entryNotional }
            .prefix(3)
            .sorted { $0.observedAt < $1.observedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Entry markers".bSmartLocalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Text("Largest 3 entries".bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            .padding(.bottom, BSmartSpacing.small)

            ForEach(Array(displayedMarkers.enumerated()), id: \.element.id) { index, marker in
                if index > 0 { Divider().overlay(BSmartColor.line) }
                entryRow(number: index + 1, marker: marker)
            }
        }
        .padding(BSmartSpacing.medium)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
    }

    private func entryRow(number: Int, marker: SmartMoneyEntryMarker) -> some View {
        HStack(spacing: BSmartSpacing.small) {
            evidenceNumber(number, color: marker.direction.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(marker.action.label)
                        .foregroundStyle(marker.direction.color)
                    Text("·")
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Text(directionLabel(marker.direction))
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .font(.caption.weight(.bold))
                Text("%@ at %@".bSmartLocalized(formattedDate(marker.observedAt), currency(marker.price)))
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .monospacedDigit()
            }
            Spacer(minLength: BSmartSpacing.small)
            VStack(alignment: .trailing, spacing: 2) {
                Text(compactCurrency(marker.entryNotional))
                    .font(.caption.weight(.black))
                    .foregroundStyle(BSmartColor.primaryText)
                    .monospacedDigit()
                Text("Added exposure".bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            if let url = marker.evidenceURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("View original record".bSmartLocalized)
            }
        }
        .padding(.vertical, BSmartSpacing.small)
    }

    private func evidenceNumber(_ value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(.caption2.weight(.black))
            .foregroundStyle(BSmartColor.onAccent)
            .frame(width: 22, height: 22)
            .background(color)
            .clipShape(Circle())
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func directionLabel(_ direction: SignalDirection) -> String {
        switch direction {
        case .bullish: "Long".bSmartLocalized
        case .bearish: "Short".bSmartLocalized
        case .neutral: "Neutral".bSmartLocalized
        case .mixed: "Mixed".bSmartLocalized
        }
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.bSmartDollars.precision(.fractionLength(value >= 100 ? 0 : 2)))
    }
}

private enum SmartMoneyChartMetric: String, CaseIterable, Identifiable {
    case pnl = "PNL"
    case equity = "Equity"

    var id: Self { self }
}

private enum SmartMoneyDetailSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case positions = "Positions"
    case activity = "Activity"

    var id: Self { self }
}

struct SmartMoneyDetailView: View {
    @EnvironmentObject private var model: AppModel
    let signal: SmartMoneySignal
    @State private var period = "30D"
    @State private var chartMetric: SmartMoneyChartMetric = .pnl
    @State private var section: SmartMoneyDetailSection = .overview

    private var isLong: Bool { signal.direction.lowercased() == "long" }
    private var periods: [String] {
        ["1D", "7D", "30D"].filter { signal.resolvedPeriodMetrics[$0] != nil }
    }
    private var selectedMetric: SmartMoneyPeriodMetric? {
        signal.resolvedPeriodMetrics[period] ?? signal.resolvedPeriodMetrics[periods.first ?? ""]
    }
    private var chartPoints: [SmartMoneyMetricPoint] {
        guard let selectedMetric else { return [] }
        return chartMetric == .pnl ? selectedMetric.pnlHistory : selectedMetric.accountValueHistory
    }
    private var displayedPnl: Double { selectedMetric?.pnl ?? signal.netPnl ?? 0 }
    private var totalOpenPnl: Double { signal.resolvedPositions.reduce(0) { $0 + $1.unrealizedPnl } }
    private var netExposure: Double {
        signal.resolvedPositions.reduce(0) { partial, position in
            partial + (position.direction == "Long" ? position.notional : -position.notional)
        }
    }
    private var largestPosition: SmartMoneyPosition? {
        signal.resolvedPositions.max { $0.notional < $1.notional }
    }
    private var nearestLiquidationBuffer: Double? {
        signal.resolvedPositions.compactMap(\.liquidationDistance).min()
    }
    private var representativeEntries: [SmartMoneyRepresentativeEvidence] {
        model.moneyEvidence(for: signal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                identityHeader
                SubjectTradeStatsSection(subject: .init(money: signal))
                detailNavigation
                switch section {
                case .overview:
                    moneySnapshot
                    representativeEntryEvidence
                    performance
                    behaviorAndScore
                    disclosure
                case .positions:
                    currentPositions
                    assetEdge
                case .activity:
                    SmartMoneySourceActivity(movements: model.moneyMovements(for: signal))
                    recentTrades
                    capitalActivity
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Smart Money")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("smart.money.detail.\(signal.id)")
        .bSmartDetailPage()
        .bSmartPage()
        .onAppear {
            if !periods.contains(period), let first = periods.first { period = first }
        }
        .task(id: signal.id) {
            await model.loadSmartMoneyEvidence(for: signal)
        }
    }

    private var detailNavigation: some View {
        Picker("Smart Money detail", selection: $section) {
            ForEach(SmartMoneyDetailSection.allCases) { item in
                Text(item.rawValue.bSmartLocalized).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("smart.money.detail.section")
    }

    private var moneySnapshot: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Current read", detail: "Observable account state right now")

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text((netExposure >= 0 ? "Net long" : "Net short").bSmartLocalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(netExposure >= 0 ? BSmartColor.bull : BSmartColor.bear)
                    Text(compactCurrency(abs(netExposure)))
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Open PNL")
                        .font(.caption)
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Text(compactSignedCurrency(totalOpenPnl))
                        .font(.headline.weight(.black))
                        .foregroundStyle(totalOpenPnl >= 0 ? BSmartColor.bull : BSmartColor.bear)
                        .monospacedDigit()
                }
            }

            Divider().overlay(BSmartColor.line)

            if let largestPosition {
                HStack(spacing: BSmartSpacing.medium) {
                    BSmartAssetMark(ticker: largestPosition.symbol, size: 42)
                        .bSmartTickerDestination(largestPosition.symbol)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Largest position")
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.tertiaryText)
                        Text("\(largestPosition.direction.bSmartLocalized) \(largestPosition.symbol)")
                            .font(.subheadline.weight(.bold))
                    }
                    Spacer()
                    Text(compactCurrency(largestPosition.notional))
                        .font(.subheadline.weight(.black))
                        .monospacedDigit()
                }
            } else {
                Text("No covered position is currently open.")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
            }

            HStack(spacing: 0) {
                snapshotMetric(label: "Positions", value: "\(signal.resolvedPositions.count)")
                Divider().overlay(BSmartColor.line)
                snapshotMetric(label: "Account leverage", value: signal.currentLeverage.map { String(format: "%.1fx", $0) } ?? "--")
                Divider().overlay(BSmartColor.line)
                snapshotMetric(label: "Liquidation buffer", value: percent(nearestLiquidationBuffer))
            }
        }
        .bSmartSurface()
    }

    private var representativeEntryEvidence: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Representative entries",
                detail: "Top 3 markets by observed entry exposure"
            )

            if representativeEntries.isEmpty && model.isLoadingMoneyEvidence(signal) {
                BSmartSkeletonRows(style: .simple, count: 3)
            } else if representativeEntries.isEmpty {
                Text("No representative entry with price evidence is available yet.")
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
            } else {
                ForEach(Array(representativeEntries.prefix(3).enumerated()), id: \.element.id) { index, evidence in
                    representativeEntryCard(evidence, index: index)
                }
            }
        }
    }

    private func representativeEntryCard(
        _ evidence: SmartMoneyRepresentativeEvidence,
        index: Int
    ) -> some View {
        return VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .top) {
                HStack(spacing: BSmartSpacing.small) {
                    BSmartAssetMark(ticker: evidence.ticker, size: 36)
                        .bSmartTickerDestination(evidence.ticker)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evidence.ticker)
                            .font(.title3.weight(.black))
                        Text(evidence.market)
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(compactCurrency(evidence.cumulativeEntryNotional))
                        .font(.headline.weight(.black))
                        .foregroundStyle(BSmartColor.brand)
                        .monospacedDigit()
                    Text("Observed entry exposure".bSmartLocalized)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }

            HStack(spacing: BSmartSpacing.small) {
                BSmartTag(
                    text: "Representative market #%d".bSmartLocalized(
                        evidence.representativeRank
                    ),
                    color: BSmartColor.gold
                )
                Text("%d entry changes".bSmartLocalized(evidence.entryCount))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Text(compactSignedCurrency(evidence.assetNetPnl))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(evidence.assetNetPnl >= 0 ? BSmartColor.bull : BSmartColor.bear)
                    .monospacedDigit()
                Text("Asset PNL".bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            EvidenceChartGuide(kind: "Price history", detail: "1–3 match entries below")

            SmartMoneyEntryEvidenceChart(evidence: evidence)
                .frame(height: 270)

            SmartMoneyEntryEvidenceList(evidence: evidence)

            Text("Entry markers are reconstructed from public fills or observed position changes. Snapshot changes indicate timing and exposure, not a guaranteed executable fill.")
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bSmartSurface()
        .accessibilityIdentifier("smart.money.representative-entry.\(index)")
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartSmartMoneyAvatar(identity: signal.publicIdentity, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: BSmartSpacing.small) {
                        Text(signal.publicIdentity.displayName)
                            .font(.headline.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                        BSmartTag(text: signal.resolvedTier, color: BSmartColor.brand)
                    }
                    Text(signal.resolvedAddress.shortWalletAddress)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                        .lineLimit(1)
                    Text("Public activity record · %@ · %@".bSmartLocalized(
                        signal.resolvedStyle.bSmartLocalized,
                        smartMoneySizeLabel(signal.sizeCohort).bSmartLocalized
                    ))
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(signal.score.formatted(.number.precision(.fractionLength(0))))
                        .font(.title3.weight(.black))
                        .foregroundStyle(BSmartColor.brand)
                        .monospacedDigit()
                    Text("Score")
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Smart Money Score %@".bSmartLocalized(
                    signal.score.formatted(.number.precision(.fractionLength(0)))
                ))
            }

            HStack(spacing: BSmartSpacing.small) {
                Button {
                    model.toggleSmartMoneyFollow(signal.id)
                } label: {
                    Label(
                        (model.isFollowingSmartMoney(signal.id) ? "Tracking" : "Track").bSmartLocalized,
                        systemImage: model.isFollowingSmartMoney(signal.id) ? "star.fill" : "star"
                    )
                    .smartProfileCommand(
                        accented: true,
                        selected: model.isFollowingSmartMoney(signal.id)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("smart.money.follow.\(signal.id)")

                if let explorerURL = signal.sourceURL
                    ?? URL(string: "https://app.hyperliquid.xyz/explorer/address/\(signal.resolvedAddress)") {
                    Link(destination: explorerURL) {
                        Label("Public record", systemImage: "arrow.up.right")
                            .smartProfileCommand(accented: false, selected: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View original record")
                }
            }
        }
    }

    @ViewBuilder
    private var performance: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Performance & risk",
                detail: "Observed PNL and risk over the selected period".bSmartLocalized
            )

            if !periods.isEmpty {
                HStack(spacing: BSmartSpacing.small) {
                    Picker("Performance period", selection: $period) {
                        ForEach(periods, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Chart metric", selection: $chartMetric) {
                        ForEach(SmartMoneyChartMetric.allCases) { Text($0.rawValue.bSmartLocalized).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BSmartSpacing.medium) {
                detailMetric(label: "Net PNL", value: compactSignedCurrency(displayedPnl), color: displayedPnl >= 0 ? BSmartColor.bull : BSmartColor.bear)
                detailMetric(label: "Win rate", value: percent(signal.winRate), color: BSmartColor.primaryText)
                detailMetric(label: "Sharpe", value: decimal(selectedMetric?.sharpe ?? signal.sharpe), color: BSmartColor.sky)
                detailMetric(label: "Max drawdown", value: percent(selectedMetric?.maxDrawdownPercent ?? signal.maxDrawdownPercent), color: BSmartColor.bear)
            }

            if chartPoints.count > 1 {
                Chart(chartPoints, id: \.timestamp) { point in
                    AreaMark(
                        x: .value("Time", metricDate(point.timestamp)),
                        y: .value(chartMetric.rawValue, point.value)
                    )
                    .foregroundStyle(BSmartColor.brand.opacity(0.12))
                    LineMark(
                        x: .value("Time", metricDate(point.timestamp)),
                        y: .value(chartMetric.rawValue, point.value)
                    )
                    .foregroundStyle(BSmartColor.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine().foregroundStyle(BSmartColor.line)
                        AxisValueLabel().foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                .frame(height: 200)
                .accessibilityLabel("%@ %@ history".bSmartLocalized(
                    period,
                    chartMetric.rawValue.bSmartLocalized
                ))
            }
        }
        .bSmartSurface()
    }

    private func metricDate(_ timestamp: Double) -> Date {
        Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp)
    }

    @ViewBuilder
    private var currentPositions: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Current positions",
                detail: signal.resolvedPositions.isEmpty ? "No open TradFi exposure" : compactCurrency(signal.totalNotional ?? 0)
            )
            if signal.resolvedPositions.isEmpty {
                Text("The account has no observable open position in the supported tokenized-equity markets.")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
            } else {
                ForEach(Array(signal.resolvedPositions.enumerated()), id: \.element.id) { index, position in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    positionRow(position)
                }
            }
        }
        .bSmartSurface()
    }

    private func positionRow(_ position: SmartMoneyPosition) -> some View {
        let long = position.direction == "Long"
        return VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack {
                BSmartAssetMark(ticker: position.symbol, size: 34)
                    .bSmartTickerDestination(position.symbol)
                Text(position.symbol)
                    .font(.headline.weight(.black))
                BSmartTag(text: position.direction, color: long ? BSmartColor.bull : BSmartColor.bear)
                Text(position.dex.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
                Spacer()
                Text(compactCurrency(position.notional))
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
            }
            HStack {
                positionMetric("Entry", currency(position.entryPrice))
                positionMetric("Mark", currency(position.markPrice))
                positionMetric("Open PNL", compactSignedCurrency(position.unrealizedPnl), color: position.unrealizedPnl >= 0 ? BSmartColor.bull : BSmartColor.bear)
            }
            HStack {
                positionMetric("Leverage", position.leverage > 0 ? String(format: "%.1fx", position.leverage) : "--")
                positionMetric("Liquidation buffer", percent(position.liquidationDistance), color: liquidationColor(position.liquidationDistance))
                positionMetric("Funding", compactSignedCurrency(position.fundingSinceOpen))
            }
        }
        .padding(.vertical, BSmartSpacing.xSmall)
    }

    @ViewBuilder
    private var assetEdge: some View {
        let assets = Array((signal.assetPerformance ?? []).prefix(6))
        if !assets.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: "Edge by asset", detail: "Net PNL in observed window")
                Chart(assets) { asset in
                    BarMark(
                        x: .value("Net PNL", asset.netPnl),
                        y: .value("Asset", asset.symbol)
                    )
                    .foregroundStyle(asset.netPnl >= 0 ? BSmartColor.bull : BSmartColor.bear)
                    .annotation(position: asset.netPnl >= 0 ? .trailing : .leading) {
                        Text(compactSignedCurrency(asset.netPnl))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(BSmartColor.line)
                        AxisValueLabel().foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel().foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                .frame(height: CGFloat(max(150, assets.count * 34)))
            }
            .bSmartSurface()
        }
    }

    private var behaviorAndScore: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.large) {
            BSmartSectionHeader(title: "Account profile", detail: signal.pnlCohort ?? "Observed behavior")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BSmartSpacing.medium) {
                detailMetric(label: "Style", value: signal.resolvedStyle, color: BSmartColor.sky)
                detailMetric(label: "Median hold", value: holdDuration(signal.tradeDuration?.medianHoldHours), color: BSmartColor.primaryText)
                detailMetric(label: "Long bias", value: percent(signal.longBias), color: BSmartColor.bull)
                detailMetric(label: "Active days", value: signal.activeDays.map(String.init) ?? "--", color: BSmartColor.primaryText)
                detailMetric(label: "Account value", value: compactCurrency(signal.accountValue ?? 0), color: BSmartColor.primaryText)
                detailMetric(label: "Margin used", value: percent(signal.marginUtilization), color: liquidationColor(signal.marginUtilization))
            }

            if let components = signal.components {
                Divider().overlay(BSmartColor.line)
                Text("Smart Money Score breakdown")
                    .font(.subheadline.weight(.bold))
                ForEach(scoreComponents(components), id: \.0) { label, value in
                    HStack(spacing: BSmartSpacing.small) {
                        Text(label.bSmartLocalized)
                            .font(.caption)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .frame(width: 82, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(BSmartColor.line)
                                Capsule().fill(BSmartColor.brand).frame(width: proxy.size.width * value / 100)
                            }
                        }
                        .frame(height: 6)
                        Text(value.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(BSmartColor.tertiaryText)
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }
        }
        .bSmartSurface()
    }

    @ViewBuilder
    private var recentTrades: some View {
        let trades = Array((signal.recentTrades ?? []).prefix(10))
        if !trades.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: "Recent trades", detail: "Onchain fills")
                ForEach(Array(trades.enumerated()), id: \.element.id) { index, trade in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                        ZStack(alignment: .bottomTrailing) {
                            BSmartAssetMark(ticker: trade.symbol, size: 38)
                                .bSmartTickerDestination(trade.symbol)
                            Image(systemName: trade.side == "Buy" ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                                .font(.caption)
                                .foregroundStyle(trade.side == "Buy" ? BSmartColor.bull : BSmartColor.bear)
                                .background(BSmartColor.ink, in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(trade.direction) · \(trade.symbol)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(trade.coin) · \(trade.time.bSmartRelativeTimestamp)")
                                .font(.caption)
                                .foregroundStyle(BSmartColor.secondaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(compactCurrency(trade.notional))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                            if trade.closedPnl != 0 {
                                Text(compactSignedCurrency(trade.closedPnl))
                                    .font(.caption2)
                                    .foregroundStyle(trade.closedPnl >= 0 ? BSmartColor.bull : BSmartColor.bear)
                            }
                        }
                    }
                }
            }
            .bSmartSurface()
        }
    }

    @ViewBuilder
    private var capitalActivity: some View {
        let events = Array((signal.capitalActivity ?? []).filter { $0.direction != "internal" }.prefix(8))
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: "Capital activity", detail: "Public transfers")
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    HStack {
                        Image(systemName: event.direction == "in" ? "arrow.down.to.line" : "arrow.up.from.line")
                            .foregroundStyle(event.direction == "in" ? BSmartColor.brand : BSmartColor.gold)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((event.direction == "in" ? "Capital in" : "Capital out").bSmartLocalized)
                                .font(.subheadline.weight(.semibold))
                            Text(event.time.bSmartRelativeTimestamp)
                                .font(.caption2)
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                        Spacer()
                        Text(compactCurrency(event.amount))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
            .bSmartSurface()
        }
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Label("Anonymous capital account", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.bold))
            Text("This stable profile name represents a public derivatives account and is not the owner's verified identity. PNL, positions and activity are rebuilt from public records. The Score ranks observed behavior and is not a return guarantee.")
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bSmartSurface()
    }

    private func snapshotMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private func detailMetric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func positionMetric(_ label: String, _ value: String, color: Color = BSmartColor.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.bSmartLocalized).font(.caption2).foregroundStyle(BSmartColor.tertiaryText)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(color).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func liquidationColor(_ value: Double?) -> Color {
        guard let value else { return BSmartColor.tertiaryText }
        if value < 0.2 { return BSmartColor.bear }
        if value < 0.4 { return BSmartColor.gold }
        return BSmartColor.brand
    }

    private func scoreComponents(_ value: SmartMoneyScoreComponents) -> [(String, Double)] {
        [("Performance", value.performance), ("Consistency", value.consistency), ("Payoff", value.payoff), ("Risk", value.risk), ("Execution", value.execution)]
    }

    private func holdDuration(_ hours: Double?) -> String {
        guard let hours, hours > 0 else { return "--" }
        if hours < 1 { return "\(Int(hours * 60))m" }
        if hours < 48 { return "\(Int(hours))h" }
        return "\(Int(hours / 24))d"
    }

    private func currency(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.bSmartDollars.precision(.fractionLength(value >= 100 ? 0 : 2)))
    }
}

private struct BSmartIdentityMark: View {
    let text: String
    let color: Color
    var size: CGFloat = 38

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.32, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 0.5)
            }
    }
}

private func compactCurrency(_ value: Double) -> String {
    switch abs(value) {
    case 1_000_000...:
        String(format: "$%.1fM", value / 1_000_000)
    case 1_000...:
        String(format: "$%.0fK", value / 1_000)
    default:
        value.formatted(.bSmartDollars.precision(.fractionLength(0)))
    }
}

private func compactSignedCurrency(_ value: Double) -> String {
    let prefix = value >= 0 ? "+" : "-"
    return prefix + compactCurrency(abs(value))
}

private func compactCount(_ value: Int) -> String {
    switch value {
    case 1_000_000...:
        return String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...:
        return String(format: "%.1fK", Double(value) / 1_000)
    default:
        return value.formatted()
    }
}

private func percent(_ value: Double?) -> String {
    guard let value else { return "--" }
    return value.formatted(.percent.precision(.fractionLength(0)))
}

private func decimal(_ value: Double?) -> String {
    guard let value else { return "--" }
    return value.formatted(.number.precision(.fractionLength(2)))
}

private func smartMoneySizeLabel(_ cohort: String?) -> String {
    switch cohort?.lowercased() {
    case "kraken": "Mega account"
    case "whale": "Whale"
    case "shark": "Large account"
    case "dolphin": "Mid-size account"
    case "fish", "crab", "shrimp": "Small account"
    default: "Unclassified"
    }
}
