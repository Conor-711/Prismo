import SwiftUI

private enum TodayConsensusDirectionFilter: String, CaseIterable, Identifiable {
    case all
    case bullish
    case bearish
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All directions".bSmartLocalized
        case .bullish: "Bullish".bSmartLocalized
        case .bearish: "Bearish".bSmartLocalized
        case .split: "Split".bSmartLocalized
        }
    }

    func includes(_ package: TodayViewpointPackage) -> Bool {
        switch self {
        case .all: true
        case .bullish: package.bullishCount > package.bearishCount
        case .bearish: package.bearishCount > package.bullishCount
        case .split: package.bullishCount > 0 && package.bearishCount > 0
        }
    }
}

private enum TodayConsensusSort: String, CaseIterable, Identifiable {
    case latest
    case accounts
    case rank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latest: "Latest".bSmartLocalized
        case .accounts: "Most accounts".bSmartLocalized
        case .rank: "Best Smart rank".bSmartLocalized
        }
    }
}

struct TodayConsensusCollectionView: View {
    let packages: [TodayViewpointPackage]

    @State private var query = ""
    @State private var selectedTicker = "ALL"
    @State private var direction: TodayConsensusDirectionFilter = .all
    @State private var sort: TodayConsensusSort = .latest

    private var tickers: [String] {
        Set(packages.map { $0.ticker.uppercased() }).sorted()
    }

    private var filteredPackages: [TodayViewpointPackage] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = packages.filter { package in
            let tickerMatches = selectedTicker == "ALL" || package.ticker.caseInsensitiveCompare(selectedTicker) == .orderedSame
            let queryMatches = normalizedQuery.isEmpty
                || package.ticker.lowercased().contains(normalizedQuery)
                || package.companyName.lowercased().contains(normalizedQuery)
                || package.localizedHeadline.lowercased().contains(normalizedQuery)
            return tickerMatches && queryMatches && direction.includes(package)
        }

        return filtered.sorted { lhs, rhs in
            switch sort {
            case .latest:
                if lhs.latestAt != rhs.latestAt { return lhs.latestAt > rhs.latestAt }
                return lhs.accountCount > rhs.accountCount
            case .accounts:
                if lhs.accountCount != rhs.accountCount { return lhs.accountCount > rhs.accountCount }
                return lhs.latestAt > rhs.latestAt
            case .rank:
                let lhsRank = bestConsensusRank(lhs)
                let rhsRank = bestConsensusRank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.latestAt > rhs.latestAt
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                searchField
                controls

                Text("%d consensus".bSmartLocalized(filteredPackages.count))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(BSmartColor.tertiaryText)

                if filteredPackages.isEmpty {
                    ContentUnavailableView("No matching consensus".bSmartLocalized, systemImage: "rectangle.stack.badge.person.crop")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(Array(filteredPackages.enumerated()), id: \.element.id) { index, package in
                        BSmartDetailNavigationLink(id: "consensus-library-\(package.id)") {
                            TodayViewpointPackageDetailView(package: package, style: index % 2)
                        } label: {
                            TodayConsensusCollectionCard(package: package)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.consensus-library.\(package.ticker.lowercased())")
                    }
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xxxLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Smart Consensus".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("today.consensus-library")
    }

    private var searchField: some View {
        HStack(spacing: BSmartSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BSmartColor.tertiaryText)
            TextField("Search ticker or company".bSmartLocalized, text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .font(.subheadline)
        .padding(.horizontal, BSmartSpacing.medium)
        .frame(height: 42)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                TodayCollectionFilterMenu(title: selectedTicker == "ALL" ? "Ticker".bSmartLocalized : selectedTicker, symbol: "tag") {
                    Button("All tickers".bSmartLocalized) { selectedTicker = "ALL" }
                    ForEach(tickers, id: \.self) { ticker in
                        Button(ticker) { selectedTicker = ticker }
                    }
                }
                TodayCollectionFilterMenu(title: direction.label, symbol: "arrow.triangle.branch") {
                    ForEach(TodayConsensusDirectionFilter.allCases) { item in
                        Button(item.label) { direction = item }
                    }
                }
                TodayCollectionFilterMenu(title: sort.label, symbol: "arrow.up.arrow.down") {
                    ForEach(TodayConsensusSort.allCases) { item in
                        Button(item.label) { sort = item }
                    }
                }
            }
        }
    }
}

private struct TodayConsensusCollectionCard: View {
    let package: TodayViewpointPackage

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: package.ticker, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.ticker)
                        .font(.headline.weight(.black))
                    Text(package.companyName)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: BSmartSpacing.small)
                consensusActors
            }

            Text(package.localizedHeadline)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            stanceBar

            HStack {
                Text("%d accounts".bSmartLocalized(package.accountCount))
                Spacer()
                Text(package.latestAt.formatted(.relative(presentation: .named)))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
        .contentShape(Rectangle())
    }

    private var consensusActors: some View {
        HStack(spacing: -7) {
            ForEach(package.leadingUpdates) { update in
                VStack(spacing: 2) {
                    BSmartAvatar(
                        url: update.authorAvatarURL,
                        name: update.authorName,
                        size: 32,
                        fallbackColor: update.direction.color
                    )
                    .overlay { Circle().stroke(BSmartColor.brand, lineWidth: 1.3) }
                    Text(consensusRankLabel(update))
                        .font(.system(size: 7, weight: .black).monospacedDigit())
                        .foregroundStyle(BSmartColor.brand)
                        .padding(.horizontal, 3)
                        .background(BSmartColor.surface, in: Capsule())
                }
                .frame(width: 38)
            }
        }
    }

    private var stanceBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(BSmartColor.brand)
                    .frame(width: proxy.size.width * CGFloat(package.bullishCount) / CGFloat(max(package.updates.count, 1)))
                Rectangle()
                    .fill(BSmartColor.tertiaryText)
                    .frame(width: proxy.size.width * CGFloat(package.neutralCount) / CGFloat(max(package.updates.count, 1)))
                Rectangle()
                    .fill(BSmartColor.bear)
            }
            .clipShape(Capsule())
        }
        .frame(height: 7)
    }
}

private enum TodayAlphaSourceFilter: String, CaseIterable, Identifiable {
    case all
    case smartAccount
    case smartMoney

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All sources".bSmartLocalized
        case .smartAccount: "Smart Account".bSmartLocalized
        case .smartMoney: "Smart Money".bSmartLocalized
        }
    }
}

private enum TodayAlphaSort: String, CaseIterable, Identifiable {
    case priority
    case latest
    case coverage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .priority: "Priority".bSmartLocalized
        case .latest: "Latest".bSmartLocalized
        case .coverage: "Most coverage".bSmartLocalized
        }
    }
}

struct TodayAlphaCollectionView: View {
    let opportunities: [TodayAlphaOpportunity]

    @State private var selectedTicker = "ALL"
    @State private var source: TodayAlphaSourceFilter = .all
    @State private var sort: TodayAlphaSort = .priority

    private var tickers: [String] {
        Set(opportunities.map { $0.ticker.uppercased() }).sorted()
    }

    private var filtered: [TodayAlphaOpportunity] {
        opportunities
            .filter { opportunity in
                let tickerMatches = selectedTicker == "ALL" || opportunity.ticker.caseInsensitiveCompare(selectedTicker) == .orderedSame
                let sourceMatches = source == .all
                    || (source == .smartAccount && opportunity.kind == .smartAccount)
                    || (source == .smartMoney && opportunity.kind == .smartMoney)
                return tickerMatches && sourceMatches
            }
            .sorted { lhs, rhs in
                switch sort {
                case .priority:
                    if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                case .latest:
                    if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
                case .coverage:
                    if lhs.sourceCount != rhs.sourceCount { return lhs.sourceCount > rhs.sourceCount }
                }
                return lhs.ticker < rhs.ticker
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                controls
                Text("%d opportunities".bSmartLocalized(filtered.count))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(BSmartColor.tertiaryText)

                if filtered.isEmpty {
                    ContentUnavailableView("No matching opportunities".bSmartLocalized, systemImage: "scope")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(filtered) { opportunity in
                        BSmartDetailNavigationLink(id: "alpha-library-\(opportunity.id)") {
                            TodayAlphaOpportunityDetailView(opportunity: opportunity)
                        } label: {
                            TodayAlphaCollectionCard(opportunity: opportunity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xxxLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Smart Alpha".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("today.alpha-library")
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                TodayCollectionFilterMenu(title: selectedTicker == "ALL" ? "Ticker".bSmartLocalized : selectedTicker, symbol: "tag") {
                    Button("All tickers".bSmartLocalized) { selectedTicker = "ALL" }
                    ForEach(tickers, id: \.self) { ticker in
                        Button(ticker) { selectedTicker = ticker }
                    }
                }
                TodayCollectionFilterMenu(title: source.label, symbol: "person.2") {
                    ForEach(TodayAlphaSourceFilter.allCases) { item in
                        Button(item.label) { source = item }
                    }
                }
                TodayCollectionFilterMenu(title: sort.label, symbol: "arrow.up.arrow.down") {
                    ForEach(TodayAlphaSort.allCases) { item in
                        Button(item.label) { sort = item }
                    }
                }
            }
        }
    }
}

private struct TodayAlphaCollectionCard: View {
    let opportunity: TodayAlphaOpportunity

    private var accent: Color {
        opportunity.kind == .smartAccount ? BSmartColor.pulse : BSmartColor.sky
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: opportunity.ticker, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.ticker)
                        .font(.headline.weight(.black))
                    Text(opportunity.localizedSourceLabel.bSmartLocalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text(opportunity.localizedRankMetric)
                    .font(.caption.weight(.black))
                    .foregroundStyle(accent)
            }

            Text(opportunity.localizedHeadline)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(3)

            HStack {
                Text(opportunity.localizedDiscoveryType)
                Spacer()
                Text(opportunity.localizedCoverageMetric)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(accent.opacity(0.38), lineWidth: 0.7)
        }
        .contentShape(Rectangle())
    }
}

private enum TodayMoneySort: String, CaseIterable, Identifiable {
    case latest
    case score
    case notional

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latest: "Latest".bSmartLocalized
        case .score: "Account score".bSmartLocalized
        case .notional: "Largest change".bSmartLocalized
        }
    }
}

struct TodaySmartMoneyCollectionView: View {
    let signals: [SmartMoneySignal]
    let movements: [SmartMoneyMovement]
    let initialTicker: String?

    @State private var selectedTicker: String
    @State private var selectedAction: SmartMoneyAction?
    @State private var sort: TodayMoneySort = .latest

    init(signals: [SmartMoneySignal], movements: [SmartMoneyMovement], initialTicker: String?) {
        self.signals = signals
        self.movements = movements
        self.initialTicker = initialTicker
        _selectedTicker = State(initialValue: initialTicker?.uppercased() ?? "ALL")
    }

    private var tickers: [String] {
        Set(movements.map { $0.ticker.uppercased() }).sorted()
    }

    private var filtered: [SmartMoneyMovement] {
        movements
            .filter { movement in
                let tickerMatches = selectedTicker == "ALL" || movement.ticker.caseInsensitiveCompare(selectedTicker) == .orderedSame
                return tickerMatches && (selectedAction == nil || movement.action == selectedAction)
            }
            .sorted { lhs, rhs in
                switch sort {
                case .latest:
                    if lhs.observedAt != rhs.observedAt { return lhs.observedAt > rhs.observedAt }
                case .score:
                    if lhs.accountScore != rhs.accountScore { return lhs.accountScore > rhs.accountScore }
                case .notional:
                    if abs(lhs.notionalChange) != abs(rhs.notionalChange) { return abs(lhs.notionalChange) > abs(rhs.notionalChange) }
                }
                return lhs.accountId < rhs.accountId
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                controls
                Text("%d actions".bSmartLocalized(filtered.count))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(BSmartColor.tertiaryText)

                if filtered.isEmpty {
                    ContentUnavailableView("No matching actions".bSmartLocalized, systemImage: "wallet.bifold")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(filtered) { movement in
                        if let signal = signal(for: movement) {
                            BSmartDetailNavigationLink(id: "money-library-\(movement.id)") {
                                SmartMoneyDetailView(signal: signal)
                            } label: {
                                TodayMoneyCollectionCard(movement: movement)
                            }
                            .buttonStyle(.plain)
                        } else {
                            TodayMoneyCollectionCard(movement: movement)
                        }
                    }
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xxxLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("What Smart Money just did".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("today.smart-money-library")
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                TodayCollectionFilterMenu(title: selectedTicker == "ALL" ? "Ticker".bSmartLocalized : selectedTicker, symbol: "tag") {
                    Button("All tickers".bSmartLocalized) { selectedTicker = "ALL" }
                    ForEach(tickers, id: \.self) { ticker in
                        Button(ticker) { selectedTicker = ticker }
                    }
                }
                TodayCollectionFilterMenu(title: selectedAction?.label ?? "All actions".bSmartLocalized, symbol: "arrow.left.arrow.right") {
                    Button("All actions".bSmartLocalized) { selectedAction = nil }
                    ForEach(SmartMoneyAction.allCases, id: \.self) { action in
                        Button(action.label) { selectedAction = action }
                    }
                }
                TodayCollectionFilterMenu(title: sort.label, symbol: "arrow.up.arrow.down") {
                    ForEach(TodayMoneySort.allCases) { item in
                        Button(item.label) { sort = item }
                    }
                }
            }
        }
    }

    private func signal(for movement: SmartMoneyMovement) -> SmartMoneySignal? {
        signals.first {
            $0.id.caseInsensitiveCompare(movement.accountId) == .orderedSame
                || $0.resolvedAddress.caseInsensitiveCompare(movement.accountId) == .orderedSame
        }
    }
}

private struct TodayMoneyCollectionCard: View {
    let movement: SmartMoneyMovement

    var body: some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 44)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(movement.publicIdentity.displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text("Score %@".bSmartLocalized(movement.accountScore.formatted(.number.precision(.fractionLength(0)))))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(BSmartColor.sky)
                }
                Text("%@ %@ %@".bSmartLocalized(movement.action.label, movement.direction.label, movement.ticker.uppercased()))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(2)
                HStack {
                    Text(signedCollectionCurrency(movement.notionalChange))
                        .foregroundStyle(movement.notionalChange >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    Text(movement.observedAt.formatted(.relative(presentation: .named)))
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                .font(.caption.weight(.bold).monospacedDigit())
            }

            Spacer(minLength: BSmartSpacing.small)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.sky.opacity(0.32), lineWidth: 0.7)
        }
        .contentShape(Rectangle())
    }
}

private struct TodayCollectionFilterMenu<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.primaryText)
                .padding(.horizontal, BSmartSpacing.medium)
                .frame(minHeight: 36)
                .background(BSmartColor.surface)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(BSmartColor.line, lineWidth: 0.6) }
        }
    }
}

private func bestConsensusRank(_ package: TodayViewpointPackage) -> Double {
    package.updates
        .map { $0.platformPercentile > 1 ? $0.platformPercentile / 100 : $0.platformPercentile }
        .min() ?? 1
}

private func consensusRankLabel(_ update: SmartAccountUpdate) -> String {
    let normalized = update.platformPercentile > 1 ? update.platformPercentile / 100 : update.platformPercentile
    return "Top \(max(1, Int(ceil(normalized * 100))))%"
}

private func signedCollectionCurrency(_ value: Double) -> String {
    let sign = value > 0 ? "+" : value < 0 ? "−" : ""
    let absolute = abs(value)
    let valueText: String
    switch absolute {
    case 1_000_000...:
        valueText = "$\((absolute / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
    case 1_000...:
        valueText = "$\((absolute / 1_000).formatted(.number.precision(.fractionLength(1))))K"
    default:
        valueText = absolute.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    return sign + valueText
}
