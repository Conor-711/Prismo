import Charts
import SwiftUI

private enum SmartSection: String, CaseIterable, Identifiable {
    case accounts = "Smart Account"
    case money = "Smart Money"

    var id: Self { self }

    var subtitle: String {
        switch self {
        case .accounts: "Qualified investors from public social platforms"
        case .money: "Scored capital accounts in tokenized US equities"
        }
    }
}

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
        NavigationStack {
            VStack(spacing: 0) {
                hubHeader

                List {
                    switch selection {
                    case .accounts:
                        accountRows
                    case .money:
                        moneyRows
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BSmartColor.ink)
            }
            .background(BSmartColor.ink)
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("smart.screen")
            .sheet(isPresented: $isShowingFilters) {
                smartFilterSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .bSmartPage()
    }

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .center, spacing: BSmartSpacing.medium) {
                BSmartPageTitle(
                    eyebrow: "Tracked intelligence",
                    title: "Smart",
                    subtitle: "Qualified public views and observable capital"
                )

                Spacer()

                Button {
                    followingOnly.toggle()
                } label: {
                    Image(systemName: followingOnly ? "star.fill" : "star")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(followingOnly ? BSmartColor.gold : BSmartColor.primaryText)
                        .frame(width: 38, height: 38)
                        .background(BSmartColor.surface)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(followingOnly ? BSmartColor.gold : BSmartColor.line, lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    (followingOnly ? "Show all intelligence" : "Show followed intelligence only")
                        .bSmartLocalized
                )
            }

            HStack(spacing: BSmartSpacing.small) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                    TextField(searchPrompt.bSmartLocalized, text: $searchText)
                        .font(.subheadline)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, BSmartSpacing.medium)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(BSmartColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .stroke(BSmartColor.line, lineWidth: 0.6)
                }
            }

            HStack(spacing: BSmartSpacing.small) {
                ForEach(SmartSection.allCases) { section in
                    Button {
                        withAnimation(BSmartMotion.quick) {
                            selection = section
                            searchText = ""
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(section.rawValue.bSmartLocalized)
                                .font(.caption.weight(.bold))
                            Text(sectionCount(section).formatted())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(selection == section ? BSmartColor.brand : BSmartColor.tertiaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.secondaryText)
                        .background(selection == section ? BSmartColor.pulse.opacity(0.09) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                .stroke(selection == section ? BSmartColor.pulse.opacity(0.72) : BSmartColor.line, lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(section.rawValue.bSmartLocalized)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeFilterSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                        .lineLimit(1)
                    Text(summaryLabel)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    isShowingFilters = true
                } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.pulse)
                        .padding(.horizontal, BSmartSpacing.medium)
                        .frame(height: 34)
                        .background(BSmartColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                .stroke(BSmartColor.pulse.opacity(0.52), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(selection == .accounts ? "smart.account.filters" : "smart.money.filters")
            }

            if let freshness = selectedFreshness {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BSmartColor.brand)
                        .frame(width: 5, height: 5)
                    Text("Checked %@".bSmartLocalized(freshness.checkedAt.bSmartDataTimestamp))
                    if let latestContentAt = freshness.latestContentAt {
                        Text("·")
                        Text(latestContentLabel(latestContentAt))
                    }
                    Spacer(minLength: BSmartSpacing.small)
                    if selection == .accounts, freshness.hasNoNewQualifiedContent {
                        Text("No newer qualified view".bSmartLocalized)
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .monospacedDigit()
                .accessibilityIdentifier("smart.source-freshness")
            }
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, BSmartSpacing.medium)
        .background(BSmartColor.ink)
    }

    private var activeFilterSummary: String {
        switch selection {
        case .accounts:
            let values = [
                accountPlatform,
                accountRankBand.rawValue,
                accountHorizon.rawValue,
                accountSpecialty,
                accountStyle,
            ].filter { !$0.hasPrefix("All ") }
            return values.isEmpty ? "Official ranking · all qualified accounts".bSmartLocalized : values.joined(separator: " · ")
        case .money:
            let values = [moneyStyle, moneySize, moneySide].filter { !$0.hasPrefix("All ") }
            return values.isEmpty ? "Scored capital accounts".bSmartLocalized : values.joined(separator: " · ")
        }
    }

    private var smartFilterSheet: some View {
        NavigationStack {
            Form {
                if selection == .accounts {
                    Section("Smart Account".bSmartLocalized) {
                        Picker("Platform".bSmartLocalized, selection: $accountPlatform) {
                            ForEach(accountPlatforms, id: \.self) { Text($0.bSmartLocalized).tag($0) }
                        }
                        Picker("Rank band".bSmartLocalized, selection: $accountRankBand) {
                            ForEach(SmartAccountRankBand.allCases) { Text($0.rawValue.bSmartLocalized).tag($0) }
                        }
                        Picker("Best horizon".bSmartLocalized, selection: $accountHorizon) {
                            ForEach(SmartAccountHorizonFilter.allCases) { Text($0.rawValue.bSmartLocalized).tag($0) }
                        }
                        Picker("Sector".bSmartLocalized, selection: $accountSpecialty) {
                            ForEach(accountSpecialties, id: \.self) { Text($0.bSmartLocalized).tag($0) }
                        }
                        Picker("Style".bSmartLocalized, selection: $accountStyle) {
                            ForEach(accountStyles, id: \.self) { Text($0.bSmartLocalized).tag($0) }
                        }
                    }
                } else {
                    Section("Smart Money".bSmartLocalized) {
                        Picker("Style".bSmartLocalized, selection: $moneyStyle) {
                            ForEach(moneyStyles, id: \.self) { Text($0.bSmartLocalized).tag($0) }
                        }
                        Picker("Account size".bSmartLocalized, selection: $moneySize) {
                            ForEach(moneySizes, id: \.self) { Text($0.bSmartLocalized).tag($0) }
                        }
                        Picker("Direction".bSmartLocalized, selection: $moneySide) {
                            ForEach(["All sides", "Long", "Short"], id: \.self) { Text($0.bSmartLocalized).tag($0) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BSmartColor.ink)
            .navigationTitle("Filters".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".bSmartLocalized) { isShowingFilters = false }
                }
            }
        }
    }

    private var selectedFreshness: BSmartDataFreshness? {
        switch selection {
        case .accounts: model.smartAccountFreshness
        case .money: model.smartMoneyFreshness
        }
    }

    private func latestContentLabel(_ date: Date) -> String {
        switch selection {
        case .accounts:
            "Latest qualified view %@".bSmartLocalized(date.bSmartDataTimestamp)
        case .money:
            "Latest capital move %@".bSmartLocalized(date.bSmartDataTimestamp)
        }
    }

    private var accountFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                rankingMenu(title: accountPlatform, options: accountPlatforms, selection: $accountPlatform)

                Menu {
                    Picker("Rank band", selection: $accountRankBand) {
                        ForEach(SmartAccountRankBand.allCases) { band in
                            Text(band.rawValue.bSmartLocalized).tag(band)
                        }
                    }
                } label: {
                    rankingFilterLabel(accountRankBand.rawValue, isActive: accountRankBand != .all)
                }

                Menu {
                    Picker("Best horizon", selection: $accountHorizon) {
                        ForEach(SmartAccountHorizonFilter.allCases) { horizon in
                            Text(horizon.rawValue.bSmartLocalized).tag(horizon)
                        }
                    }
                } label: {
                    rankingFilterLabel(accountHorizon.rawValue, isActive: accountHorizon != .all)
                }

                rankingMenu(title: accountSpecialty, options: accountSpecialties, selection: $accountSpecialty)
                rankingMenu(title: accountStyle, options: accountStyles, selection: $accountStyle)
            }
        }
        .accessibilityIdentifier("smart.account.filters")
    }

    private var moneyFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                rankingMenu(title: moneyStyle, options: moneyStyles, selection: $moneyStyle)
                rankingMenu(title: moneySize, options: moneySizes, selection: $moneySize)
                rankingMenu(title: moneySide, options: ["All sides", "Long", "Short"], selection: $moneySide)
            }
        }
        .accessibilityIdentifier("smart.money.filters")
    }

    private func rankingMenu(title: String, options: [String], selection: Binding<String>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.bSmartLocalized).tag(option)
                }
            }
        } label: {
            rankingFilterLabel(title, isActive: !title.hasPrefix("All "))
        }
    }

    private func rankingFilterLabel(_ title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title.bSmartLocalized)
                .font(.caption.weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(isActive ? BSmartColor.brand : BSmartColor.secondaryText)
        .padding(.horizontal, BSmartSpacing.small)
        .frame(height: 30)
        .background(isActive ? BSmartColor.brand.opacity(0.1) : BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(isActive ? BSmartColor.brand : BSmartColor.line, lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private var accountRows: some View {
        let latestTickers = recentTickersByAccount
        if filteredAccounts.isEmpty {
            smartEmptyState
        } else {
            ForEach(Array(filteredAccounts.enumerated()), id: \.element.id) { index, account in
                BSmartDetailNavigationLink(id: "smart-account-\(account.id)") {
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
                .listRowBackground(BSmartColor.ink)
                .listRowSeparatorTint(BSmartColor.line)
            }
        }
    }

    @ViewBuilder
    private var moneyRows: some View {
        if !model.smartMoney.isEmpty {
            SmartMoneySourceStatus(signals: model.smartMoney)
                .accessibilityIdentifier("smart.money.source-status")
                .listRowBackground(BSmartColor.ink)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(
                        top: BSmartSpacing.small,
                        leading: BSmartSpacing.large,
                        bottom: 0,
                        trailing: BSmartSpacing.large
                    )
                )
        }

        if filteredMoney.isEmpty {
            smartEmptyState
        } else {
            SmartMoneyCohortSummary(signals: filteredMoney)
                .accessibilityIdentifier("smart.money.cohort")
                .listRowBackground(BSmartColor.ink)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(
                        top: BSmartSpacing.small,
                        leading: BSmartSpacing.large,
                        bottom: BSmartSpacing.medium,
                        trailing: BSmartSpacing.large
                    )
                )

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
                .listRowBackground(BSmartColor.ink)
                .listRowSeparatorTint(BSmartColor.line)
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
            Text((followingOnly
                 ? "Open an account and follow it to monitor future changes."
                 : "Try a different account, ticker or specialty.").bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BSmartSpacing.xxxLarge)
        .listRowBackground(BSmartColor.ink)
        .listRowSeparator(.hidden)
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

    private func sectionCount(_ section: SmartSection) -> Int {
        switch section {
        case .accounts: model.smartAccounts.count
        case .money: model.smartMoney.count
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

private struct SmartMoneySourceStatus: View {
    let signals: [SmartMoneySignal]

    private var sourceUpdatedAt: Date? {
        signals.compactMap(\.sourceUpdatedAt).max()
    }

    private var sourceLabel: String {
        let sources = Set(signals.map(\.resolvedSource))
        guard sources.count == 1, let source = sources.first else { return "Mixed sources" }
        switch source {
        case "hyperdash": return "Hyperdash"
        case "hyperdash_cached": return "Hyperdash cache"
        case "hyperliquid_fallback": return "Hyperliquid fallback"
        default: return "Unverified"
        }
    }

    private var isDelayed: Bool {
        guard let sourceUpdatedAt else { return true }
        return Date().timeIntervalSince(sourceUpdatedAt) > 1_800
    }

    var body: some View {
        HStack(spacing: BSmartSpacing.small) {
            Image(systemName: isDelayed ? "clock.badge.exclamationmark" : "checkmark.shield.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(isDelayed ? BSmartColor.gold : BSmartColor.brand)

            VStack(alignment: .leading, spacing: 2) {
                Text("Scored capital accounts · Copy Score".bSmartLocalized)
                    .font(.caption.weight(.bold))
                if let sourceUpdatedAt {
                    Text("%@ data · as of %@ · %d accounts".bSmartLocalized(
                        sourceLabel,
                        sourceUpdatedAt.formatted(date: .omitted, time: .shortened),
                        signals.count
                    ))
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .monospacedDigit()
                }
            }

            Spacer()

            BSmartTag(
                text: (isDelayed ? "Delayed" : "Current").bSmartLocalized,
                color: isDelayed ? BSmartColor.gold : BSmartColor.brand
            )
        }
        .padding(.horizontal, BSmartSpacing.medium)
        .frame(minHeight: 52)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(isDelayed ? BSmartColor.gold.opacity(0.6) : BSmartColor.brand.opacity(0.45), lineWidth: 0.75)
        }
    }
}

private struct SmartMoneyCohortSummary: View {
    let signals: [SmartMoneySignal]

    private var positions: [SmartMoneyPosition] {
        signals.flatMap(\.resolvedPositions)
    }

    private var longNotional: Double {
        positions
            .filter { $0.direction.caseInsensitiveCompare("Long") == .orderedSame }
            .reduce(0) { $0 + abs($1.notional) }
    }

    private var shortNotional: Double {
        positions
            .filter { $0.direction.caseInsensitiveCompare("Short") == .orderedSame }
            .reduce(0) { $0 + abs($1.notional) }
    }

    private var grossNotional: Double { longNotional + shortNotional }

    private var netRatio: Double {
        guard grossNotional > 0 else { return 0 }
        return (longNotional - shortNotional) / grossNotional
    }

    private var longShare: CGFloat {
        guard grossNotional > 0 else { return 0.5 }
        return CGFloat(longNotional / grossNotional)
    }

    private var topAsset: (symbol: String, notional: Double)? {
        let grouped = Dictionary(grouping: positions, by: \.symbol)
            .map { symbol, values in
                (symbol: symbol, notional: values.reduce(0) { $0 + abs($1.notional) })
            }
        return grouped.max { $0.notional < $1.notional }
    }

    private var smartCount: Int {
        signals.filter { $0.resolvedTier == "Smart" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cohort positioning")
                        .font(.subheadline.weight(.bold))
                    Text("Current positions across selected accounts")
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                Spacer()
                Text(netLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(netRatio >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(BSmartColor.brand)
                        .frame(width: max(2, proxy.size.width * longShare))
                    Rectangle()
                        .fill(BSmartColor.bear)
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())

            HStack(spacing: BSmartSpacing.large) {
                cohortMetric("Long", compactCurrency(longNotional), BSmartColor.brand)
                cohortMetric("Short", compactCurrency(shortNotional), BSmartColor.bear)
                cohortMetric("Gross", compactCurrency(grossNotional), BSmartColor.primaryText)
                Spacer(minLength: 0)
                if let topAsset {
                    cohortMetric("Top exposure", "\(topAsset.symbol) · \(compactCurrency(topAsset.notional))", BSmartColor.gold)
                }
            }

            Text("%d scored accounts · %d Smart tier · %d open positions".bSmartLocalized(
                signals.count,
                smartCount,
                positions.count
            ))
                .font(.caption2)
                .foregroundStyle(BSmartColor.secondaryText)
                .monospacedDigit()
        }
        .bSmartSurface()
    }

    private var netLabel: String {
        let side = (netRatio >= 0 ? "Net long" : "Net short").bSmartLocalized
        return "\(side) \(abs(netRatio).formatted(.percent.precision(.fractionLength(0))))"
    }

    private func cohortMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct SmartRankBadge: View {
    let rank: Int

    private var accent: Color {
        switch rank {
        case 1: BSmartColor.pulse
        case 2: BSmartColor.sky
        case 3: BSmartColor.orange
        default: BSmartColor.secondaryText
        }
    }

    private var foreground: Color {
        rank == 1 ? BSmartColor.pulseInk : accent
    }

    private var fill: Color {
        rank == 1 ? BSmartColor.pulse : accent.opacity(rank <= 3 ? 0.14 : 0.055)
    }

    var body: some View {
        Text("\(rank)")
            .font(.caption.weight(.black))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 32, height: 32)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(accent.opacity(rank <= 3 ? 0.72 : 0.18), lineWidth: rank <= 3 ? 1 : 0.7)
            }
            .accessibilityLabel("Rank %d".bSmartLocalized(rank))
    }
}

private struct SmartAccountRow: View {
    let rank: Int
    let account: SmartAccountProfile
    let recentTickers: [String]
    let isFollowing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SmartRankBadge(rank: rank)

            BSmartAvatar(url: account.avatarURL, name: account.name, size: 38)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(account.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if isFollowing {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(BSmartColor.gold)
                            }
                        }
                        HStack(spacing: 5) {
                            SmartPlatformMark(platform: account.platform, size: 16)
                            Text(account.handle)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("smart.account.row.identity")
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    SmartAssetCluster(tickers: recentTickers)
                }

                SmartPreviewTraitRow(
                    sector: account.specialty,
                    horizon: account.horizon,
                    style: account.resolvedStyle
                )
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SmartMoneyRow: View {
    let signal: SmartMoneySignal
    let isFollowing: Bool

    private var isLong: Bool { signal.direction.lowercased() == "long" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SmartRankBadge(rank: signal.rank ?? 0)
                .padding(.top, 3)

            BSmartSmartMoneyAvatar(identity: signal.publicIdentity, size: 38)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(signal.publicIdentity.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if isFollowing {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(BSmartColor.gold)
                            }
                        }
                        HStack(spacing: 5) {
                            SmartPlatformMark(platform: signal.resolvedSource, size: 16)
                            Text(signal.resolvedAddress.shortWalletAddress)
                                .lineLimit(1)
                            if let accountValue = signal.accountValue, accountValue > 0 {
                                Text("·")
                                Text(compactCurrency(accountValue))
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.secondaryText)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(compactSignedCurrency(signal.netPnl ?? 0))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle((signal.netPnl ?? 0) >= 0 ? BSmartColor.brand : BSmartColor.bear)
                            .monospacedDigit()
                        Text("Win %@".bSmartLocalized(percent(signal.winRate)))
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.tertiaryText)
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 9) {
                    SmartAssetCluster(tickers: positionTickers)
                    Rectangle()
                        .fill(BSmartColor.line)
                        .frame(width: 0.6, height: 18)
                    SmartPreviewTraitRow(
                        sector: inferredSector(for: positionTickers),
                        horizon: inferredHorizon,
                        style: inferredBias
                    )
                }
            }
        }
        .padding(.vertical, 7)
    }

    private var positionTickers: [String] {
        let ranked = signal.resolvedPositions
            .sorted { abs($0.notional) > abs($1.notional) }
            .map { $0.symbol.uppercased() }
        var seen = Set<String>()
        return Array((ranked.isEmpty ? [signal.ticker.uppercased()] : ranked)
            .filter { seen.insert($0).inserted }
            .prefix(4))
    }

    private var inferredHorizon: String {
        switch signal.resolvedStyle.lowercased() {
        case "scalp", "intraday": "Short term"
        case "position", "long term": "Long term"
        default: "Medium term"
        }
    }

    private var inferredBias: String {
        guard let longBias = signal.longBias else {
            return isLong ? "Long biased" : "Short biased"
        }
        if longBias >= 0.65 { return "Long biased" }
        if longBias <= 0.35 { return "Short biased" }
        return "Two-sided"
    }

    private func inferredSector(for tickers: [String]) -> String {
        let sectors: [(String, Set<String>)] = [
            ("Semiconductors", ["NVDA", "AMD", "MU", "AVGO", "TSM", "ASML", "INTC", "ARM", "QCOM", "MRVL", "SMH", "SOXX"]),
            ("AI infrastructure", ["NBIS", "CRWV", "IREN", "CIFR", "APLD", "CORZ", "HUT", "WULF", "CLSK"]),
            ("Fintech", ["HOOD", "SOFI", "PYPL", "AFRM", "NU", "COIN"]),
            ("Crypto-linked equities", ["MSTR", "MARA", "RIOT", "CLSK", "CIFR", "IREN"]),
            ("Software", ["PLTR", "MSFT", "ORCL", "NOW", "CRM", "APP", "SNOW"]),
            ("Consumer", ["TSLA", "AMZN", "NFLX", "WMT", "COST"]),
            ("Broad market", ["SP500", "USTECH", "XYZ100", "QQQ", "IWM", "DIA", "SPCX", "JP225"]),
        ]
        for ticker in tickers {
            if let sector = sectors.first(where: { $0.1.contains(ticker.uppercased()) })?.0 {
                return sector
            }
        }
        return "Tokenized equities"
    }
}

private struct SmartAssetCluster: View {
    let tickers: [String]

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(tickers.prefix(3)), id: \.self) { ticker in
                BSmartAssetMark(ticker: ticker, size: 22)
                    .frame(width: 22, height: 22)
                    .background(BSmartColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(BSmartColor.line, lineWidth: 0.8)
                    }
                    .accessibilityLabel(ticker)
                    .accessibilityHint("Recently mentioned".bSmartLocalized)
                }
        }
        .frame(minWidth: tickers.isEmpty ? 0 : 22)
    }
}

private struct SmartPreviewTraitRow: View {
    let sector: String
    let horizon: String
    let style: String

    var body: some View {
        HStack(spacing: 7) {
            trait(icon: "square.grid.2x2.fill", value: sector, color: BSmartColor.sky)
            separator
            trait(icon: "clock.fill", value: horizon, color: BSmartColor.gold)
            separator
            trait(icon: "scope", value: style, color: BSmartColor.brand)
        }
    }

    private var separator: some View {
        Circle()
            .fill(BSmartColor.line)
            .frame(width: 3, height: 3)
    }

    private func trait(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(color)
            Text(value.bSmartLocalized)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .foregroundStyle(BSmartColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct SmartPlatformMark: View {
    let platform: String
    var size: CGFloat = 16

    private var normalized: String { platform.lowercased() }

    var body: some View {
        Group {
            if normalized.contains("youtube") {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(Color.red)
            } else if normalized.contains("reddit") {
                Text("r/")
                    .font(.system(size: size * 0.66, weight: .black, design: .rounded))
                    .foregroundStyle(Color.orange)
            } else if normalized.contains("xueqiu") || normalized.contains("雪球") {
                Text("雪")
                    .font(.system(size: size * 0.62, weight: .black))
                    .foregroundStyle(BSmartColor.sky)
            } else if normalized.contains("toss") {
                Text("T")
                    .font(.system(size: size * 0.68, weight: .black))
                    .foregroundStyle(BSmartColor.sky)
            } else if normalized.contains("hyper") {
                Text("H")
                    .font(.system(size: size * 0.66, weight: .black))
                    .foregroundStyle(BSmartColor.sky)
            } else if normalized == "x" || normalized.contains("twitter") {
                Text("X")
                    .font(.system(size: size * 0.7, weight: .black))
                    .foregroundStyle(BSmartColor.primaryText)
            } else {
                Image(systemName: "network")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .background(BSmartColor.elevated)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityLabel(platform)
    }
}

private enum SmartAccountDetailSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case views = "Views"
    case trackRecord = "Track record"

    var id: Self { self }
}

struct SmartAccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    let account: SmartAccountProfile
    @State private var section: SmartAccountDetailSection = .overview

    private var updates: [SmartAccountUpdate] { model.accountEvidence(for: account) }
    private var representativeWorks: [SmartAccountUpdate] {
        model.representativeAccountEvidence(for: account)
    }
    private var insights: SmartAccountProfileInsights {
        SmartAccountProfileInsights(
            account: account,
            evidenceUpdates: updates,
            recentUpdates: model.accountUpdates(for: account)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                identityHeader
                detailNavigation
                switch section {
                case .overview:
                    SmartAccountInvestorProfileSection(account: account)
                    SmartAccountCurrentViewsSection(insights: insights)
                    SmartAccountLatestViewsSection(
                        updates: insights.latestViews,
                        limit: 4,
                        onViewAll: {
                            withAnimation(BSmartMotion.quick) {
                                section = .views
                            }
                        }
                    )
                    scoreProvenance
                case .views:
                    SmartAccountLatestViewsSection(updates: insights.latestViews)
                case .trackRecord:
                    benchmarkAbility
                    viewEvidence
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Smart Account")
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .task(id: account.id) {
            await model.loadSmartAccountEvidence(for: account)
        }
    }

    private var detailNavigation: some View {
        Picker("Smart Account detail", selection: $section) {
            ForEach(SmartAccountDetailSection.allCases) { item in
                Text(item.rawValue.bSmartLocalized).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("smart.account.detail.section")
    }

    @ViewBuilder
    private var viewEvidence: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Representative works",
                detail: "Top 3 tickers by cumulative Score contribution"
            )

            if representativeWorks.isEmpty {
                HStack(spacing: BSmartSpacing.small) {
                    if model.isLoadingAccountEvidence(account) { ProgressView() }
                    Text("No settled representative work with price evidence is available yet.")
                }
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
            } else {
                ForEach(Array(representativeWorks.enumerated()), id: \.element.id) { index, update in
                    representativeEvidenceCard(update: update, index: index)
                }
            }
        }
    }

    @ViewBuilder
    private func representativeEvidenceCard(update: SmartAccountUpdate, index: Int) -> some View {
        if let evidence = update.priceEvidence {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack(alignment: .top) {
                    HStack(spacing: BSmartSpacing.small) {
                        BSmartAssetMark(ticker: update.ticker, size: 36)
                        Text(update.ticker)
                            .font(.title3.weight(.black))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        BSmartTag(text: directionLabel(update.direction), color: update.direction.color)
                        BSmartTag(text: update.horizon, color: BSmartColor.sky)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scoreContributionLabel(update.representativeTickerContribution))
                            .font(.headline.weight(.black))
                            .foregroundStyle(BSmartColor.brand)
                            .monospacedDigit()
                        Text("Score contribution".bSmartLocalized)
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                }

                HStack {
                    BSmartTag(
                        text: "Representative ticker #%d".bSmartLocalized(
                            update.representativeTickerRank ?? index + 1
                        ),
                        color: BSmartColor.gold
                    )
                    Text("%d contributing views".bSmartLocalized(
                        update.representativeCallCount ?? evidence.opinionMarkers?.count ?? 1
                    ))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    Spacer()
                }

                EvidenceChartGuide(kind: "Price history", detail: "1–3 match evidence below")

                PriceEvidenceChart(update: update, evidence: evidence)
                    .frame(height: 196)

                SmartAccountOpinionEvidenceList(update: update, evidence: evidence)

                Text("Highest-contributing view".bSmartLocalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)

                Text(update.originalText ?? update.thesis)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Label("%@ daily OHLC".bSmartLocalized(evidence.source), systemImage: "checkmark.shield")
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Spacer()
                    BSmartDetailNavigationLink(id: "account-evidence-\(update.id)") {
                        SmartAccountEvidenceDetailView(update: update)
                    } label: {
                        Label("View evidence", systemImage: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                    }
                }

            }
            .bSmartSurface()
            .accessibilityIdentifier("smart.account.representative-work.\(index)")
        }
    }

    private func scoreContributionLabel(_ contribution: Double?) -> String {
        guard let contribution else { return "—" }
        return contribution.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAvatar(url: account.avatarURL, name: account.name, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        SmartPlatformMark(platform: account.platform, size: 18)
                        Text(account.handle)
                    }
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                    if let followers = account.followersCount {
                        Text("%@ followers".bSmartLocalized(followers.formatted()))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(account.score.formatted(.number.precision(.fractionLength(0))))
                        .font(.title2.weight(.black))
                        .foregroundStyle(BSmartColor.brand)
                        .monospacedDigit()
                    Text("Account Score")
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }

            HStack(spacing: BSmartSpacing.small) {
                Button {
                    model.toggleSmartAccountFollow(account.id)
                } label: {
                    Label(
                        (model.isFollowingSmartAccount(account.id) ? "Tracking" : "Track").bSmartLocalized,
                        systemImage: model.isFollowingSmartAccount(account.id) ? "star.fill" : "star"
                    )
                    .smartProfileCommand(
                        accented: true,
                        selected: model.isFollowingSmartAccount(account.id)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("smart.account.follow")

                if let profileURL = account.profileURL {
                    Link(destination: profileURL) {
                        Label("Public profile", systemImage: "arrow.up.right")
                            .smartProfileCommand(accented: false, selected: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open public profile")
                }
            }
        }
    }

    private var scoreProvenance: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Why this account ranks here",
                detail: "Score provenance and evidence coverage"
            )
            HStack(spacing: 0) {
                detailMetric(label: "Platform rank", value: "#\(account.resolvedPlatformRank)")
                Divider().overlay(BSmartColor.line)
                detailMetric(
                    label: "Platform percentile",
                    value: "Top \(max(1, Int(ceil(account.resolvedPlatformPercentile * 100))))%"
                )
                Divider().overlay(BSmartColor.line)
                detailMetric(label: "Confidence", value: account.resolvedConfidence.capitalized)
            }
            Divider().overlay(BSmartColor.line)
            HStack(spacing: 0) {
                detailMetric(
                    label: "Evidence weight",
                    value: account.resolvedEffectiveSamples.formatted(.number.precision(.fractionLength(1)))
                )
                Divider().overlay(BSmartColor.line)
                detailMetric(label: "Settled calls", value: "\(account.resolvedSettledCalls)")
                Divider().overlay(BSmartColor.line)
                detailMetric(label: "Active days", value: "\(account.resolvedActiveDays)")
            }
            if let scoreAsOf = updates.compactMap(\.authorScoreAsOf).max() {
                Label("Score snapshot %@".bSmartLocalized(scoreAsOf.bSmartCompactDate), systemImage: "clock.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .bSmartSurface()
    }

    @ViewBuilder
    private var benchmarkAbility: some View {
        if account.marketSelectionScore != nil || account.industrySelectionScore != nil {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: "Selection ability", detail: "Two independent benchmarks")
                HStack(spacing: 0) {
                    detailMetric(
                        label: "vs S&P 500",
                        value: scoreLabel(account.marketSelectionScore)
                    )
                    Divider().overlay(BSmartColor.line)
                    detailMetric(
                        label: "vs sector ETF",
                        value: scoreLabel(account.industrySelectionScore)
                    )
                }
            }
            .bSmartSurface()
        }
    }

    private func detailMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private func scoreLabel(_ score: Double?) -> String {
        guard let score else { return "--" }
        return score.formatted(.number.precision(.fractionLength(0)))
    }

    private func directionLabel(_ direction: SignalDirection) -> String {
        switch direction {
        case .bullish: "Bullish"
        case .bearish: "Bearish"
        case .neutral: "Neutral"
        case .mixed: "Mixed"
        }
    }

}

struct SmartAccountEvidenceDetailView: View {
    let update: SmartAccountUpdate

    private var sourceURL: URL? { update.sourceURL ?? update.evidenceURL }
    private var preferredTranslation: String? {
        let candidate = BSmartLocalization.isSimplifiedChinese
            ? (update.translatedTextZH ?? update.translatedText)
            : (update.translatedTextEN ?? update.translatedText)
        guard let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              candidate != update.originalText else { return nil }
        return candidate
    }

    private func displayHorizon(_ value: String) -> String {
        value.lowercased() == "unknown" ? "Horizon unavailable".bSmartLocalized : value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                evidenceHeader
                structuredCall
                sourceEvidence
                if let settlement = update.settlement {
                    settlementEvidence(settlement)
                }
                if let priceEvidence = update.priceEvidence {
                    priceContext(priceEvidence)
                }
                auditTrail
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Call evidence".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("smart.account.evidence.detail")
        .bSmartDetailPage()
        .bSmartPage()
    }

    private var evidenceHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.authorName)
                        .font(.headline.weight(.bold))
                    Text("\(update.platform) · \(update.publishedAt.bSmartRelativeTimestamp)")
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                Spacer()
                Text(update.score.formatted(.number.precision(.fractionLength(0))))
                    .font(.title3.weight(.black))
                    .foregroundStyle(BSmartColor.brand)
                    .monospacedDigit()
            }
            HStack(spacing: BSmartSpacing.small) {
                BSmartAssetMark(ticker: update.ticker, size: 30)
                Text(update.ticker)
                    .font(.headline.weight(.black))
                BSmartTag(text: directionLabel, color: update.direction.color)
                BSmartTag(text: displayHorizon(update.horizon), color: BSmartColor.sky)
                if let role = update.evidenceRole {
                    BSmartTag(text: roleLabel(role), color: roleColor(role))
                }
            }
        }
    }

    private var structuredCall: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Structured Call",
                detail: "bSmart interpretation; verify against the source evidence below"
            )
            Text(update.thesis)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                evidenceMetric(label: "Direction", value: directionLabel)
                Divider().overlay(BSmartColor.line)
                evidenceMetric(label: "Horizon", value: displayHorizon(update.horizon))
                Divider().overlay(BSmartColor.line)
                evidenceMetric(label: "Target", value: targetLabel)
            }
            if let invalidation = update.invalidation, !invalidation.isEmpty {
                Label(invalidation, systemImage: "shield.slash")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .bSmartSurface()
    }

    private var sourceEvidence: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Source evidence",
                detail: "Exact public text kept separate from bSmart analysis"
            )
            if let span = update.evidenceSpan, !span.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Evidence excerpt", systemImage: "quote.opening")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                    Text(span)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BSmartSpacing.medium)
                .background(BSmartColor.brand.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(BSmartColor.brand.opacity(0.35), lineWidth: 1)
                }
            }
            if let translation = preferredTranslation {
                sourceText(title: "Complete translation", text: translation)
                Divider().overlay(BSmartColor.line)
            }
            if let original = update.originalText, !original.isEmpty {
                sourceText(title: "Original source text", text: original)
            } else {
                Text("The complete source text is unavailable; only the extracted evidence is shown.")
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            if let sourceURL {
                Link(destination: sourceURL) {
                    Label("Open original source", systemImage: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }
            }
        }
        .bSmartSurface()
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
                .foregroundStyle(settlement.actualHit == true ? BSmartColor.brand : BSmartColor.bear)
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
        .bSmartSurface()
    }

    private func priceContext(_ evidence: SmartAccountPriceEvidence) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Price timeline",
                detail: "Publication, entry and settlement windows on real daily OHLC"
            )
            EvidenceChartGuide(kind: "Price history", detail: "1–3 match evidence below")
            PriceEvidenceChart(update: update, evidence: evidence)
                .frame(height: 230)
            SmartAccountOpinionEvidenceList(update: update, evidence: evidence)
            PriceEvidenceMilestones(update: update, evidence: evidence, settlement: update.settlement)
        }
        .bSmartSurface()
    }

    private var auditTrail: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            BSmartSectionHeader(title: "Audit trail", detail: "Data and scoring provenance")
            auditRow("Published", update.publishedAt.formatted(date: .abbreviated, time: .shortened))
            if let sourcePostId = update.sourcePostId { auditRow("Source post ID", sourcePostId) }
            if let ingestedAt = update.ingestedAt {
                auditRow("Ingested", ingestedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let processedAt = update.processedAt {
                auditRow("Processed", processedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let scoreAsOf = update.authorScoreAsOf {
                auditRow("Account Score as of", scoreAsOf.formatted(date: .abbreviated, time: .shortened))
            }
            if let version = update.callScoringVersion { auditRow("Call model", version) }
            if let version = update.settlement?.settlementVersion { auditRow("Settlement model", version) }
        }
        .bSmartSurface()
    }

    private func sourceText(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.secondaryText)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private func auditRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.bSmartLocalized)
                .foregroundStyle(BSmartColor.tertiaryText)
            Spacer(minLength: BSmartSpacing.medium)
            Text(value)
                .foregroundStyle(BSmartColor.primaryText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private var directionLabel: String {
        switch update.direction {
        case .bullish: "Bullish".bSmartLocalized
        case .bearish: "Bearish".bSmartLocalized
        case .neutral: "Neutral".bSmartLocalized
        case .mixed: "Mixed".bSmartLocalized
        }
    }

    private var targetLabel: String {
        update.targetPrice.map(currency) ?? "Not stated".bSmartLocalized
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
        value.formatted(.currency(code: "USD").precision(.fractionLength(value >= 100 ? 0 : 2)))
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "strongest": "Representative hit".bSmartLocalized
        case "counterexample": "Representative miss".bSmartLocalized
        default: "Recent".bSmartLocalized
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "strongest": BSmartColor.brand
        case "counterexample": BSmartColor.bear
        default: BSmartColor.sky
        }
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

private struct PriceEvidenceChart: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence

    private var opinionMarkers: [SmartAccountOpinionMarker] {
        if let markers = evidence.opinionMarkers, !markers.isEmpty { return markers }
        return []
    }

    private var displayedMarkers: [SmartAccountOpinionMarker] {
        opinionMarkers
            .sorted { $0.contribution > $1.contribution }
            .prefix(3)
            .sorted { $0.publishedAt < $1.publishedAt }
    }

    private var range: ClosedRange<Double> {
        let markerPrices = opinionMarkers.map(\.viewPrice)
        let lows = evidence.candles.map(\.low) + markerPrices + [evidence.viewPrice]
        let highs = evidence.candles.map(\.high) + markerPrices + [evidence.viewPrice]
        let lower = lows.min() ?? evidence.viewPrice
        let upper = highs.max() ?? evidence.viewPrice
        let padding = max((upper - lower) * 0.08, upper * 0.005)
        return (lower - padding)...(upper + padding)
    }

    private var axisDays: [String] {
        let days = evidence.candles.map(\.day)
        guard days.count > 3 else { return days }
        let last = days.count - 1
        return [0, last / 2, last]
            .map { days[$0] }
            .reduce(into: [String]()) { result, day in
                if !result.contains(day) { result.append(day) }
            }
    }

    private var viewMarker: (day: String, price: Double) {
        if let candle = evidence.candles.first(where: { $0.day == evidence.viewDay }) {
            return (candle.day, evidence.viewPrice)
        }
        if let candle = evidence.candles.last(where: { $0.day <= evidence.viewDay }) ?? evidence.candles.last {
            return (candle.day, candle.close)
        }
        return (evidence.viewDay, evidence.viewPrice)
    }

    var body: some View {
        VStack(spacing: BSmartSpacing.xSmall) {
            Chart {
                ForEach(evidence.candles) { candle in
                    RuleMark(
                        x: .value("Session", candle.day),
                        yStart: .value("Low", candle.low),
                        yEnd: .value("High", candle.high)
                    )
                    .foregroundStyle(candleColor(candle).opacity(0.72))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                    RectangleMark(
                        x: .value("Session", candle.day),
                        yStart: .value("Open", candle.open),
                        yEnd: .value("Close", candle.close),
                        width: .fixed(3)
                    )
                    .foregroundStyle(candleColor(candle).opacity(0.78))
                }

                if displayedMarkers.isEmpty {
                    RuleMark(x: .value("Published", viewMarker.day))
                        .foregroundStyle(update.direction.color.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("Published", viewMarker.day),
                        y: .value("Price at view", viewMarker.price)
                    )
                    .foregroundStyle(update.direction.color)
                    .symbolSize(108)
                    .annotation(position: .overlay) {
                        markerNumber(1)
                    }
                } else {
                    ForEach(Array(displayedMarkers.enumerated()), id: \.element.id) { index, marker in
                        RuleMark(x: .value("Published", markerDay(marker)))
                            .foregroundStyle(marker.direction.color.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        PointMark(
                            x: .value("Published", markerDay(marker)),
                            y: .value("Price at view", marker.viewPrice)
                        )
                        .foregroundStyle(marker.direction.color)
                        .symbolSize(108)
                        .annotation(position: .overlay) {
                            markerNumber(index + 1)
                        }
                    }
                }
            }
            .chartYScale(domain: range)
            .chartXScale(range: .plotDimension(startPadding: 7, endPadding: 7))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(BSmartColor.line.opacity(0.55))
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(compactPrice(price))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    .foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            .chartPlotStyle { plot in
                plot.background(BSmartColor.recessed.opacity(0.68))
            }

            chartDayLabels
        }
        .accessibilityLabel("%@ candlestick chart with %d contributing views".bSmartLocalized(
            update.ticker,
            max(displayedMarkers.count, 1)
        ))
    }

    private var chartDayLabels: some View {
        HStack {
            ForEach(Array(axisDays.enumerated()), id: \.element) { index, day in
                if index > 0 { Spacer(minLength: 0) }
                Text(formattedDay(day))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(.trailing, 46)
    }

    private func markerNumber(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(BSmartColor.ink)
            .accessibilityHidden(true)
    }

    private func candleColor(_ candle: PriceCandle) -> Color {
        candle.close >= candle.open ? BSmartColor.brand : BSmartColor.bear
    }

    private func compactPrice(_ price: Double) -> String {
        switch abs(price) {
        case 1_000...: String(format: "$%.1fK", price / 1_000)
        case 100...: String(format: "$%.0f", price)
        default: String(format: "$%.2f", price)
        }
    }

    private func formattedDay(_ day: String) -> String {
        String(day.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }

    private func markerDay(_ marker: SmartAccountOpinionMarker) -> String {
        if evidence.candles.contains(where: { $0.day == marker.viewDay }) { return marker.viewDay }
        return evidence.candles.last(where: { $0.day <= marker.viewDay })?.day
            ?? evidence.candles.first?.day
            ?? marker.viewDay
    }

}

private struct SmartAccountOpinionEvidenceList: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence

    private var displayedMarkers: [SmartAccountOpinionMarker] {
        let markers = evidence.opinionMarkers ?? []
        return markers
            .sorted { $0.contribution > $1.contribution }
            .prefix(3)
            .sorted { $0.publishedAt < $1.publishedAt }
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
            .foregroundStyle(BSmartColor.ink)
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
        value.formatted(.currency(code: "USD").precision(.fractionLength(value >= 100 ? 0 : 2)))
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
        let formattedPrice = price.formatted(.currency(code: "USD").precision(.fractionLength(price >= 100 ? 0 : 2)))
        return "\(day) · \(formattedPrice)"
    }
}

private struct SmartMoneyEntryEvidenceChart: View {
    let evidence: SmartMoneyRepresentativeEvidence

    private var candles: [SmartMoneyCandle] { evidence.priceEvidence.candles }
    private var markers: [SmartMoneyEntryMarker] { evidence.priceEvidence.entryMarkers }
    private var displayedMarkers: [SmartMoneyEntryMarker] {
        markers
            .sorted { $0.entryNotional > $1.entryNotional }
            .prefix(3)
            .sorted { $0.observedAt < $1.observedAt }
    }
    private var priceRange: ClosedRange<Double> {
        let lows = candles.map(\.low) + markers.map(\.price)
        let highs = candles.map(\.high) + markers.map(\.price)
        let lower = lows.min() ?? 0
        let upper = highs.max() ?? max(lower + 1, 1)
        let padding = max((upper - lower) * 0.08, upper * 0.005)
        return (lower - padding)...(upper + padding)
    }

    var body: some View {
        if candles.isEmpty {
            ContentUnavailableView(
                "Price history unavailable".bSmartLocalized,
                systemImage: "chart.xyaxis.line",
                description: Text("Entry evidence is retained, but this contract has no matching candle history.".bSmartLocalized)
            )
        } else {
            VStack(spacing: BSmartSpacing.xSmall) {
                Chart {
                    ForEach(candles) { candle in
                        RuleMark(
                            x: .value("Time", candle.timestamp),
                            yStart: .value("Low", candle.low),
                            yEnd: .value("High", candle.high)
                        )
                        .foregroundStyle(candleColor(candle).opacity(0.72))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                        RectangleMark(
                            x: .value("Time", candle.timestamp),
                            yStart: .value("Open", candle.open),
                            yEnd: .value("Close", candle.close),
                            width: .fixed(3)
                        )
                        .foregroundStyle(candleColor(candle).opacity(0.78))
                    }

                    ForEach(Array(displayedMarkers.enumerated()), id: \.element.id) { index, marker in
                        RuleMark(x: .value("Observed", marker.observedAt))
                            .foregroundStyle(marker.direction.color.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        PointMark(
                            x: .value("Observed", marker.observedAt),
                            y: .value("Entry price", marker.price)
                        )
                        .foregroundStyle(marker.direction.color)
                        .symbolSize(108)
                        .annotation(position: .overlay) {
                            markerNumber(index + 1)
                        }
                    }
                }
                .chartYScale(domain: priceRange)
                .chartXScale(range: .plotDimension(startPadding: 7, endPadding: 7))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(BSmartColor.line.opacity(0.55))
                        AxisValueLabel {
                            if let price = value.as(Double.self) {
                                Text(compactPrice(price))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        .foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                .chartPlotStyle { plot in
                    plot.background(BSmartColor.recessed.opacity(0.68))
                }

                chartDateLabels
            }
            .accessibilityLabel("%@ candlestick chart with %d observed entries".bSmartLocalized(
                evidence.ticker,
                displayedMarkers.count
            ))
        }
    }

    private var chartDateLabels: some View {
        let dates: [Date] = candles.isEmpty
            ? []
            : [candles[0].timestamp, candles[candles.count / 2].timestamp, candles[candles.count - 1].timestamp]
        return HStack {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                if index > 0 { Spacer(minLength: 0) }
                Text(date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(.trailing, 42)
    }

    private func markerNumber(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(BSmartColor.ink)
            .accessibilityHidden(true)
    }

    private func candleColor(_ candle: SmartMoneyCandle) -> Color {
        candle.close >= candle.open ? BSmartColor.brand : BSmartColor.bear
    }

    private func compactPrice(_ price: Double) -> String {
        switch abs(price) {
        case 1_000...: String(format: "$%.1fK", price / 1_000)
        case 100...: String(format: "$%.0f", price)
        default: String(format: "$%.2f", price)
        }
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
            .foregroundStyle(BSmartColor.ink)
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
        value.formatted(.currency(code: "USD").precision(.fractionLength(value >= 100 ? 0 : 2)))
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
                        .foregroundStyle(netExposure >= 0 ? BSmartColor.brand : BSmartColor.bear)
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
                        .foregroundStyle(totalOpenPnl >= 0 ? BSmartColor.brand : BSmartColor.bear)
                        .monospacedDigit()
                }
            }

            Divider().overlay(BSmartColor.line)

            if let largestPosition {
                HStack(spacing: BSmartSpacing.medium) {
                    BSmartAssetMark(ticker: largestPosition.symbol, size: 42)
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

            if representativeEntries.isEmpty {
                HStack(spacing: BSmartSpacing.small) {
                    if model.isLoadingMoneyEvidence(signal) { ProgressView() }
                    Text("No representative entry with price evidence is available yet.")
                }
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
                    .foregroundStyle(evidence.assetNetPnl >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    .monospacedDigit()
                Text("Asset PNL".bSmartLocalized)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            EvidenceChartGuide(kind: "Price history", detail: "1–3 match entries below")

            SmartMoneyEntryEvidenceChart(evidence: evidence)
                .frame(height: 196)

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
                detailMetric(label: "Net PNL", value: compactSignedCurrency(displayedPnl), color: displayedPnl >= 0 ? BSmartColor.brand : BSmartColor.bear)
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
                Text(position.symbol)
                    .font(.headline.weight(.black))
                BSmartTag(text: position.direction, color: long ? BSmartColor.brand : BSmartColor.bear)
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
                positionMetric("Open PNL", compactSignedCurrency(position.unrealizedPnl), color: position.unrealizedPnl >= 0 ? BSmartColor.brand : BSmartColor.bear)
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
                    .foregroundStyle(asset.netPnl >= 0 ? BSmartColor.brand : BSmartColor.bear)
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
                detailMetric(label: "Long bias", value: percent(signal.longBias), color: BSmartColor.brand)
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
                            Image(systemName: trade.side == "Buy" ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                                .font(.caption)
                                .foregroundStyle(trade.side == "Buy" ? BSmartColor.brand : BSmartColor.bear)
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
                                    .foregroundStyle(trade.closedPnl >= 0 ? BSmartColor.brand : BSmartColor.bear)
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
        return value.formatted(.currency(code: "USD").precision(.fractionLength(value >= 100 ? 0 : 2)))
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
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
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
