import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @State private var selectedScope: TodayActivityScope = .holdings
    @State private var selectedFilter: TodayActivityFilter = .accounts
    @State private var selectedPlatform: TodayActivityPlatform = .all
    @State private var selectedTicker = "ALL"
    @State private var maximumSmartRankPercentile = 100.0
    @State private var rankSliderValue = 100.0
    @State private var activitySnapshot: [TodayActivity] = []
    @State private var selectedSort: TodayActivitySort = .latest
    @State private var showsAllRepeatedActors = false
    @State private var expandedActivityID: UUID?
    @State private var isAddingPosition = false
    @State private var isShowingSettings = false
    @State private var showsActivityFilters = true

    private var scopePositions: [PortfolioPosition] {
        switch selectedScope {
        case .holdings: model.heldPositions
        case .watchlist: model.watchlist
        }
    }

    private var portfolioPositions: [PortfolioPosition] {
        let heldTickers = Set(model.heldPositions.map { $0.ticker.uppercased() })
        return model.heldPositions + model.watchlist.filter {
            !heldTickers.contains($0.ticker.uppercased())
        }
    }

    private var positionsByTicker: [String: PortfolioPosition] {
        Dictionary(
            portfolioPositions.map { ($0.ticker.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var scopeActivities: [TodayActivity] {
        activitySnapshot
    }

    private func rebuildActivitySnapshot() {
        activitySnapshot = TodayActivity.activities(
            scope: selectedScope,
            positions: model.positions,
            accountUpdates: model.smartAccountUpdates,
            moneyMovements: model.smartMoneyMovements,
            sort: selectedSort
        )
    }

    private var filteredActivities: [TodayActivity] {
        let matching = scopeActivities.filter { activity in
            let matchesType = activity.isSmartAccount
            let matchesPlatform = selectedPlatform == .all
                || activity.platform == selectedPlatform
                || (!activity.isSmartAccount && selectedPlatform == .all)
            let matchesTicker = selectedTicker == "ALL" || activity.ticker.caseInsensitiveCompare(selectedTicker) == .orderedSame
            return matchesType && matchesPlatform && matchesTicker && activity.smartRankPercentile <= maximumSmartRankPercentile
        }
        return showsAllRepeatedActors
            ? matching
            : TodayActivity.limitingRepeatedActors(matching)
    }

    private var homepageActivities: [TodayActivity] {
        Array(filteredActivities.prefix(3))
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

    private var interludeCandidates: [TodayInterludeItem] {
        let portfolioTickers = Set(portfolioPositions.map { $0.ticker.uppercased() })
        let ranked = model.smartAccountUpdates
            .filter { portfolioTickers.contains($0.ticker.uppercased()) }
            .sorted { lhs, rhs in
                let lhsRank = lhs.platformPercentile > 1 ? lhs.platformPercentile / 100 : lhs.platformPercentile
                let rhsRank = rhs.platformPercentile > 1 ? rhs.platformPercentile / 100 : rhs.platformPercentile
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.publishedAt != rhs.publishedAt { return lhs.publishedAt > rhs.publishedAt }
                return lhs.score > rhs.score
            }
        var seenAuthors = Set<String>()
        let accountUpdates = Array(ranked.filter { update in
            seenAuthors.insert(update.authorId.lowercased()).inserted
        }.prefix(3))

        let relevantMoney = model.smartMoney
            .filter { portfolioTickers.contains($0.ticker.uppercased()) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.changedAt > rhs.changedAt
            }
        let moneySignals = relevantMoney.isEmpty
            ? model.smartMoney.sorted { $0.score > $1.score }
            : relevantMoney

        func movement(for signal: SmartMoneySignal) -> SmartMoneyMovement? {
            let movement = model.smartMoneyMovements
                .filter { $0.accountId.caseInsensitiveCompare(signal.id) == .orderedSame }
                .max { $0.observedAt < $1.observedAt }
                ?? model.smartMoneyMovements
                    .filter { $0.ticker.caseInsensitiveCompare(signal.ticker) == .orderedSame }
                    .max { $0.observedAt < $1.observedAt }
            return movement
        }

        var items: [TodayInterludeItem] = []
        if let update = accountUpdates.first {
            items.append(.accountProfile(model.smartAccountProfile(for: update)))
        }
        if let signal = moneySignals.first {
            items.append(.moneyProfile(signal))
        }
        if let update = accountUpdates.dropFirst().first {
            items.append(.accountView(update, model.smartAccountProfile(for: update)))
        }
        if let signal = moneySignals.first {
            items.append(.moneyPosition(signal, movement(for: signal)))
        }
        if let update = accountUpdates.dropFirst().first {
            items.append(.accountProfile(model.smartAccountProfile(for: update)))
        }
        if let signal = moneySignals.dropFirst().first {
            items.append(.moneyProfile(signal))
        }
        if let update = accountUpdates.dropFirst(2).first {
            items.append(.accountView(update, model.smartAccountProfile(for: update)))
        }
        if let signal = moneySignals.dropFirst().first {
            items.append(.moneyPosition(signal, movement(for: signal)))
        }
        return items
    }

    private var interludeItems: [TodayInterludeItem] {
        Array(interludeCandidates.prefix(4))
    }

    private var secondaryInterludeItems: [TodayInterludeItem] {
        Array(interludeCandidates.dropFirst(4).prefix(4))
    }

    private var activePosition: PortfolioPosition? {
        if selectedTicker != "ALL",
           let selected = positionsByTicker[selectedTicker.uppercased()] {
            return selected
        }
        return portfolioPositions.first
    }

    private var activeTicker: String? {
        activePosition?.ticker.uppercased()
    }

    private var activeAccountUpdates: [SmartAccountUpdate] {
        guard let activeTicker else { return [] }
        return model.smartAccountUpdates.filter {
            $0.ticker.caseInsensitiveCompare(activeTicker) == .orderedSame
        }
    }

    private var activeMoneyMovements: [SmartMoneyMovement] {
        guard let activeTicker else { return [] }
        return model.smartMoneyMovements.filter {
            $0.ticker.caseInsensitiveCompare(activeTicker) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack(path: $router.todayPath) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                    pageHeader

                    if model.positions.isEmpty {
                        emptyPortfolio
                    } else {
                        TodayPortfolioNowModule(
                            positions: portfolioPositions,
                            selectedTicker: activeTicker,
                            accountUpdates: activeAccountUpdates,
                            moneyMovements: activeMoneyMovements,
                            onSelect: applyPosition
                        )

                        if !viewpointPackages.isEmpty {
                            BSmartDetailNavigationLink(id: "today-consensus-library") {
                                TodayConsensusCollectionView(packages: viewpointPackages)
                            } label: {
                                TodayEditorialSectionTitle(title: "Smart Consensus", showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.consensus.title")
                            TodayViewpointPackageRail(packages: viewpointPackages)
                        }

                        if !interludeItems.isEmpty {
                            TodayInterludeDeck(items: interludeItems)
                        }

                        if !alphaOpportunities.isEmpty {
                            BSmartDetailNavigationLink(id: "today-alpha-library") {
                                TodayAlphaCollectionView(opportunities: alphaOpportunities)
                            } label: {
                                TodayEditorialSectionTitle(title: "Smart Alpha", showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.alpha.title")
                            TodayAlphaOpportunityRail(opportunities: alphaOpportunities)
                        }

                        if let activeTicker, !activeMoneyMovements.isEmpty {
                            BSmartDetailNavigationLink(id: "today-money-library") {
                                TodaySmartMoneyCollectionView(
                                    signals: model.smartMoney,
                                    movements: model.smartMoneyMovements,
                                    initialTicker: activeTicker
                                )
                            } label: {
                                TodayEditorialSectionTitle(title: "What Smart Money just did", showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.smart-money.title")
                            TodaySmartMoneyFeature(
                                ticker: activeTicker,
                                movements: activeMoneyMovements
                            ) {
                                router.selection = .smart
                            }
                        }

                        if !secondaryInterludeItems.isEmpty {
                            TodayInterludeDeck(items: secondaryInterludeItems)
                        }

                        TodayTrackedActivityModule(
                            activities: trackedActivities,
                            recommendations: trackedAccountRecommendations
                        )

                        if scopeActivities.isEmpty {
                            noRecentActivity
                        } else {
                            activityFeedHeader
                            if showsActivityFilters {
                                activityControls
                                    .transition(.opacity)
                            }

                            if !homepageActivities.isEmpty {
                                LazyVStack(spacing: BSmartSpacing.medium) {
                                    ForEach(Array(homepageActivities.enumerated()), id: \.element.id) { index, activity in
                                        TodayActivityRow(
                                            activity: activity,
                                            position: positionsByTicker[activity.ticker.uppercased()],
                                            isRead: model.isTodayActivityRead(activity.id),
                                            isExpanded: expandedActivityID == activity.id,
                                            onOpen: { open(activity) }
                                        )
                                        .accessibilityIdentifier(index == 0
                                            ? "today.lead-activity"
                                            : "today.activity.\(activity.id.uuidString)")
                                    }
                                }
                            } else {
                                noFilteredActivity
                            }
                        }
                    }
                }
                .padding(BSmartSpacing.large)
                .padding(.bottom, BSmartSpacing.xLarge)
            }
            .accessibilityIdentifier("today.screen")
            .background(BSmartColor.ink)
            .task {
                rebuildActivitySnapshot()
            }
            .task(id: followedAccountSyncKey) {
                for account in model.smartAccounts where model.followedSmartAccountIDs.contains(where: {
                    $0.caseInsensitiveCompare(account.id) == .orderedSame
                }) {
                    await model.loadSmartAccountEvidence(for: account)
                }
            }
            .onChange(of: selectedScope) {
                syncSelectedTickerToScope()
                rebuildActivitySnapshot()
            }
            .onChange(of: selectedSort) { rebuildActivitySnapshot() }
            .onChange(of: model.positions) { rebuildActivitySnapshot() }
            .onChange(of: model.smartAccountUpdates) { rebuildActivitySnapshot() }
            .onChange(of: model.smartMoneyMovements) { rebuildActivitySnapshot() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .dailyDigest:
                    DailyDigestView()
                }
            }
            .refreshable {
                await model.refreshLiveIntelligence()
            }
            .sheet(isPresented: $isAddingPosition) {
                AddPositionView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $isShowingSettings) {
                AppSettingsView()
            }
            .task(id: router.pendingSignalID) {
                router.resolvePendingSignal(from: model.signals)
            }
            .onChange(of: model.signals) { _, signals in
                router.resolvePendingSignal(from: signals)
            }
            .onAppear(perform: chooseAvailableScope)
            .onChange(of: model.positions) { _, _ in
                chooseAvailableScope()
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .bSmartPage()
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack(alignment: .center, spacing: BSmartSpacing.medium) {
                BSmartPageTitle(
                    eyebrow: "Smart activity",
                    title: "Today",
                    subtitle: "Recent Smart Account views and Smart Money actions for stocks you track"
                )

                Spacer()

                BSmartIconButton(
                    symbol: "gearshape.fill",
                    accessibilityLabel: "Open settings"
                ) {
                    isShowingSettings = true
                }
                .accessibilityIdentifier("today.settings")
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(monitorStatusColor)
                    .frame(width: 6, height: 6)
                Text(monitorStatusText.bSmartLocalized)
                if let updatedAt = model.lastDataRefreshAt {
                    Text("·")
                    Text("Updated %@".bSmartLocalized(updatedAt.bSmartDataTimestamp))
                        .accessibilityIdentifier("today.data-updated-at")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(monitorStatusColor)
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
        .frame(minHeight: 54)
    }

    private var scopePicker: some View {
        HStack(spacing: BSmartSpacing.xSmall) {
            scopeButton(.holdings, count: model.heldPositions.count)
            scopeButton(.watchlist, count: model.watchlist.count)
        }
        .padding(3)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    private func scopeButton(_ scope: TodayActivityScope, count: Int) -> some View {
        Button {
            withAnimation(BSmartMotion.quick) {
                selectedScope = scope
                selectedFilter = .all
                showsAllRepeatedActors = false
                expandedActivityID = nil
            }
        } label: {
            HStack(spacing: 6) {
                Text(scope.label)
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(0.72)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(selectedScope == scope ? BSmartColor.ink : BSmartColor.tertiaryText)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(selectedScope == scope ? BSmartColor.pulseFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.58 : 1)
        .accessibilityIdentifier("today.scope.\(scope.rawValue)")
        .accessibilityAddTraits(selectedScope == scope ? .isSelected : [])
    }

    private var activityFeedHeader: some View {
        HStack {
            BSmartDetailNavigationLink(id: "standalone-opinions-\(selectedScope.rawValue)") {
                TodayStandaloneOpinionsView(scope: selectedScope)
            } label: {
                HStack(spacing: BSmartSpacing.small) {
                    Text("Standalone views".bSmartLocalized)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(BSmartColor.primaryText)
                    Text(filteredActivities.count.formatted())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.standalone.title")

            Spacer()

            Button {
                withAnimation(BSmartMotion.quick) { showsActivityFilters.toggle() }
            } label: {
                Image(systemName: showsActivityFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(showsActivityFilters ? BSmartColor.brand : BSmartColor.secondaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters".bSmartLocalized)
        }
    }

    private var activityControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                compactMenu(title: selectedTicker == "ALL" ? "Ticker".bSmartLocalized : selectedTicker, symbol: "tag") {
                    Button("All tickers".bSmartLocalized) { applyTicker("ALL") }
                    ForEach(availableTickers, id: \.self) { ticker in
                        Button(ticker) { applyTicker(ticker) }
                    }
                }
                compactMenu(title: selectedPlatform.label, symbol: "network") {
                    ForEach(TodayActivityPlatform.allCases) { platform in
                        Button(platform.label) { applyPlatform(platform) }
                    }
                }
                sortMenu
                compactMenu(title: "Top %@".bSmartLocalized(rankLabel(for: maximumSmartRankPercentile)), symbol: "chart.bar") {
                    ForEach([5.0, 10.0, 25.0, 50.0, 100.0], id: \.self) { rank in
                        Button("Top %@".bSmartLocalized(rankLabel(for: rank))) { applyRank(rank) }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedSort)
    }

    private var availableTickers: [String] {
        Set(scopeActivities.map { $0.ticker.uppercased() }).sorted()
    }

    private func compactMenu<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.primaryText)
                .padding(.horizontal, BSmartSpacing.small)
                .frame(minHeight: 32)
                .background(BSmartColor.surface)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(BSmartColor.line, lineWidth: 0.6) }
        }
    }

    private func resetFeedSelection() {
        showsAllRepeatedActors = false
        expandedActivityID = nil
    }

    private func applyTicker(_ ticker: String) {
        selectedTicker = ticker
        resetFeedSelection()
    }

    private func applyPosition(_ position: PortfolioPosition) {
        let scope: TodayActivityScope = position.resolvedKind == .watchlist ? .watchlist : .holdings
        withAnimation(BSmartMotion.quick) {
            selectedScope = scope
            selectedTicker = position.ticker.uppercased()
            selectedFilter = .accounts
            resetFeedSelection()
        }
    }

    private func applyPlatform(_ platform: TodayActivityPlatform) {
        selectedPlatform = platform
        resetFeedSelection()
    }

    private func applyScope(_ scope: TodayActivityScope) {
        guard selectedScope != scope else { return }
        withAnimation(BSmartMotion.quick) {
            selectedScope = scope
            selectedFilter = .accounts
            resetFeedSelection()
        }
    }

    private func applyRank(_ rank: Double) {
        maximumSmartRankPercentile = rank
        resetFeedSelection()
    }

    private var platformPicker: some View {
        HStack(spacing: BSmartSpacing.small) {
            Text("Platform".bSmartLocalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
            ForEach(TodayActivityPlatform.allCases) { platform in
                Button {
                    withAnimation(BSmartMotion.quick) {
                        selectedPlatform = platform
                        showsAllRepeatedActors = false
                        expandedActivityID = nil
                    }
                } label: {
                    platformLogo(platform)
                        .frame(width: 34, height: 30)
                        .background(selectedPlatform == platform ? BSmartColor.brand.opacity(0.16) : BSmartColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                .stroke(selectedPlatform == platform ? BSmartColor.brand : BSmartColor.line, lineWidth: selectedPlatform == platform ? 1 : 0.6)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(platform.label)
                .accessibilityAddTraits(selectedPlatform == platform ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func platformLogo(_ platform: TodayActivityPlatform) -> some View {
        switch platform {
        case .all:
            Image(systemName: "square.grid.2x2")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
        case .x:
            Text("X")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(BSmartColor.primaryText)
        case .youtube:
            Image(systemName: "play.rectangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.red)
        case .reddit:
            Text("r/")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color.orange)
        }
    }

    private var smartScorePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Smart ranking".bSmartLocalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
                Spacer()
                Text("Top %@".bSmartLocalized(rankLabel(for: maximumSmartRankPercentile)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
                    .monospacedDigit()
            }
            Slider(value: $rankSliderValue, in: 1...100, step: 1)
                .tint(BSmartColor.brand)
                .accessibilityLabel("Smart ranking".bSmartLocalized)
                .accessibilityValue("Top %@".bSmartLocalized(rankLabel(for: maximumSmartRankPercentile)))
                .onChange(of: rankSliderValue) {
                    maximumSmartRankPercentile = rankSliderValue
                    showsAllRepeatedActors = false
                    expandedActivityID = nil
                }
        }
    }

    private func rankLabel(for percentile: Double) -> String {
        switch percentile {
        case 1...5: "5%"
        case ...10: "10%"
        case ...25: "25%"
        case ...50: "50%"
        default: "100%"
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TodayActivitySort.allCases) { sort in
                Button {
                    withAnimation(BSmartMotion.quick) {
                        selectedSort = sort
                        showsAllRepeatedActors = false
                        expandedActivityID = nil
                    }
                } label: {
                    Label(sort.label, systemImage: sort.symbol)
                }
                .accessibilityIdentifier("today.sort.\(sort.rawValue)")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedSort.symbol)
                Text(selectedSort.label)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.horizontal, BSmartSpacing.small)
            .frame(minHeight: 32)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.6)
            }
        }
        .accessibilityIdentifier("today.sort.menu")
    }

    private var monitorStatusText: String {
        if model.errorMessage != nil { return "Cached" }
        if model.isLoading || model.isRefreshingLiveIntelligence { return "Updating" }
        return "Live"
    }

    private var monitorStatusColor: Color {
        model.errorMessage == nil ? BSmartColor.brand : BSmartColor.gold
    }

    private var emptyPortfolio: some View {
        ContentUnavailableView {
            Label("Build your portfolio", systemImage: "plus.circle.fill")
        } description: {
            Text("Add positions or watched stocks to receive Smart Account views and Smart Money actions that concern you.")
        } actions: {
            Button("Add ticker") {
                isAddingPosition = true
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("today.empty-portfolio")
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var emptyScope: some View {
        ContentUnavailableView {
            Label(
                selectedScope == .holdings ? "No holdings yet" : "No watched stocks yet",
                systemImage: selectedScope == .holdings ? "briefcase" : "eye"
            )
        } description: {
            Text(
                selectedScope == .holdings
                    ? "Add a position to monitor what smart accounts and public capital do next."
                    : "Add a stock to your watchlist to monitor it without recording a position."
            )
        } actions: {
            Button("Add ticker") {
                isAddingPosition = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .accessibilityIdentifier("today.empty-scope")
    }

    private var noRecentActivity: some View {
        ContentUnavailableView {
            Label("No recent smart activity", systemImage: "checkmark.circle")
        } description: {
            Text("No qualified Smart Account view or Smart Money action is available for this group yet.")
        }
        .accessibilityIdentifier("today.no-signals")
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var noFilteredActivity: some View {
        VStack(spacing: BSmartSpacing.medium) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text("No matching activity".bSmartLocalized)
                .font(.headline)
            Text("Choose another source or show all recent activity.".bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Show all".bSmartLocalized) {
                selectedFilter = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("today.no-filtered-activity")
    }

    private func chooseAvailableScope() {
        if selectedScope == .holdings, model.heldPositions.isEmpty, !model.watchlist.isEmpty {
            selectedScope = .watchlist
        } else if selectedScope == .watchlist, model.watchlist.isEmpty, !model.heldPositions.isEmpty {
            selectedScope = .holdings
        }
        syncSelectedTickerToScope()
    }

    private func syncSelectedTickerToScope() {
        let scopedTickers = Set(scopePositions.map { $0.ticker.uppercased() })
        if selectedTicker == "ALL" || !scopedTickers.contains(selectedTicker.uppercased()) {
            selectedTicker = scopePositions.first?.ticker.uppercased() ?? "ALL"
        }
    }

    private func open(_ activity: TodayActivity) {
        model.markTodayActivityRead(activity.id)
        expandedActivityID = expandedActivityID == activity.id ? nil : activity.id
    }

}

private struct TodayTrackedActivityModule: View {
    @EnvironmentObject private var model: AppModel

    let activities: [TodayActivity]
    let recommendations: [SmartAccountProfile]

    private var followedCount: Int {
        model.followedSmartAccountIDs.count + model.followedSmartMoneyIDs.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tracked activity".bSmartLocalized)
                    .font(.title3.weight(.black))
                    .foregroundStyle(BSmartColor.primaryText)
                Spacer(minLength: BSmartSpacing.small)
                if followedCount > 0 {
                    Text("%d tracked".bSmartLocalized(followedCount))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                        .monospacedDigit()
                }
            }

            if followedCount == 0 {
                recommendationList(title: "Track top Smart Accounts")
            } else if activities.isEmpty {
                HStack(spacing: BSmartSpacing.small) {
                    if !model.loadingSmartAccountEvidenceIDs.isEmpty {
                        ProgressView()
                            .tint(BSmartColor.brand)
                    } else {
                        Image(systemName: "clock")
                            .foregroundStyle(BSmartColor.secondaryText)
                    }
                    Text("Syncing tracked views".bSmartLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, BSmartSpacing.medium)
                .background(BSmartColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: BSmartSpacing.medium) {
                        ForEach(activities) { activity in
                            destination(for: activity) {
                                trackedCard(activity)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }
        }
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
            if let signal = moneySignal(for: moneyActivity.latest) {
                BSmartDetailNavigationLink(id: "tracked-money-\(activity.id)") {
                    SmartMoneyDetailView(signal: signal)
                } label: {
                    label()
                }
                .buttonStyle(.plain)
            } else {
                label()
            }
        }
    }

    private func trackedCard(_ activity: TodayActivity) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.small) {
                trackedAvatar(activity)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(actorName(activity))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                            .lineLimit(1)
                        sourceMark(activity)
                    }
                    Text(sourceName(activity))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(sourceColor(activity))
                }

                Spacer(minLength: 4)
                Text(compactRelativeTime(activity.occurredAt))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Text(activity.informativeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 7) {
                BSmartAssetMark(ticker: activity.ticker, size: 22)
                Text(activity.ticker)
                    .font(.caption.weight(.black))
                    .foregroundStyle(BSmartColor.primaryText)
                BSmartTag(text: activity.direction.label, color: activity.direction.color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(BSmartSpacing.medium)
        .frame(width: 286, height: 142, alignment: .topLeading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(sourceColor(activity).opacity(0.28), lineWidth: 0.8)
        }
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
            Image(systemName: "wallet.pass.fill")
                .font(.caption2)
                .foregroundStyle(BSmartColor.sky)
        }
    }

    private func actorName(_ activity: TodayActivity) -> String {
        switch activity {
        case let .account(accountActivity): accountActivity.latest.authorName
        case let .money(moneyActivity): moneyActivity.publicIdentity.displayName
        }
    }

    private func sourceName(_ activity: TodayActivity) -> String {
        activity.isSmartAccount ? "Smart Account" : "Smart Money"
    }

    private func sourceColor(_ activity: TodayActivity) -> Color {
        activity.isSmartAccount ? BSmartColor.brand : BSmartColor.sky
    }

    private func moneySignal(for movement: SmartMoneyMovement) -> SmartMoneySignal? {
        model.smartMoney.first {
            $0.id.caseInsensitiveCompare(movement.accountId) == .orderedSame
                || $0.resolvedAddress.caseInsensitiveCompare(movement.accountId) == .orderedSame
        } ?? model.smartMoney.first {
            $0.ticker.caseInsensitiveCompare(movement.ticker) == .orderedSame
        }
    }
}

private struct TodayStandaloneOpinionsView: View {
    @EnvironmentObject private var model: AppModel

    let scope: TodayActivityScope

    @State private var selectedPlatform: TodayActivityPlatform = .all
    @State private var selectedTicker = "ALL"
    @State private var selectedSort: TodayActivitySort = .latest
    @State private var maximumSmartRankPercentile = 100.0
    @State private var expandedActivityID: UUID?

    private var positions: [PortfolioPosition] {
        switch scope {
        case .holdings: model.heldPositions
        case .watchlist: model.watchlist
        }
    }

    private var positionsByTicker: [String: PortfolioPosition] {
        Dictionary(
            positions.map { ($0.ticker.uppercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var source: [TodayActivity] {
        TodayActivity.activities(
            scope: scope,
            positions: model.positions,
            accountUpdates: model.smartAccountUpdates,
            moneyMovements: [],
            sort: selectedSort
        )
        .filter(\.isSmartAccount)
    }

    private var filtered: [TodayActivity] {
        source.filter { activity in
            let platformMatches = selectedPlatform == .all || activity.platform == selectedPlatform
            let tickerMatches = selectedTicker == "ALL" || activity.ticker.caseInsensitiveCompare(selectedTicker) == .orderedSame
            return platformMatches && tickerMatches && activity.smartRankPercentile <= maximumSmartRankPercentile
        }
    }

    private var tickers: [String] {
        Set(source.map { $0.ticker.uppercased() }).sorted()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                BSmartPageTitle(
                    eyebrow: scope.label,
                    title: "All standalone views",
                    subtitle: "Every qualified Smart Account view for the selected portfolio group"
                )

                controls

                HStack {
                    Text("%d views".bSmartLocalized(filtered.count))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                    Spacer()
                    Text(selectedSort.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No matching activity",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVStack(spacing: BSmartSpacing.medium) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { _, activity in
                            TodayActivityRow(
                                activity: activity,
                                position: positionsByTicker[activity.ticker.uppercased()],
                                isRead: model.isTodayActivityRead(activity.id),
                                isExpanded: expandedActivityID == activity.id,
                                onOpen: {
                                    model.markTodayActivityRead(activity.id)
                                    withAnimation(BSmartMotion.quick) {
                                        expandedActivityID = expandedActivityID == activity.id ? nil : activity.id
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xxxLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Standalone views".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("today.standalone.full-list")
    }

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSmartSpacing.small) {
                menu(title: selectedTicker == "ALL" ? "Ticker".bSmartLocalized : selectedTicker, symbol: "tag") {
                    Button("All tickers".bSmartLocalized) { selectedTicker = "ALL" }
                    ForEach(tickers, id: \.self) { ticker in
                        Button(ticker) { selectedTicker = ticker }
                    }
                }
                menu(title: selectedPlatform.label, symbol: "network") {
                    ForEach(TodayActivityPlatform.allCases) { platform in
                        Button(platform.label) { selectedPlatform = platform }
                    }
                }
                menu(title: selectedSort.label, symbol: selectedSort.symbol) {
                    ForEach(TodayActivitySort.allCases) { sort in
                        Button(sort.label) { selectedSort = sort }
                    }
                }
                menu(title: "Top %@".bSmartLocalized(rankLabel), symbol: "chart.bar") {
                    ForEach([5.0, 10.0, 25.0, 50.0, 100.0], id: \.self) { rank in
                        Button("Top %@".bSmartLocalized(rank == 100 ? "100%" : "\(Int(rank))%")) {
                            maximumSmartRankPercentile = rank
                        }
                    }
                }
            }
        }
    }

    private var rankLabel: String {
        maximumSmartRankPercentile == 100 ? "100%" : "\(Int(maximumSmartRankPercentile))%"
    }

    private func menu<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSmartColor.primaryText)
                .padding(.horizontal, BSmartSpacing.small)
                .frame(minHeight: 34)
                .background(BSmartColor.surface)
                .clipShape(Capsule())
                .overlay { Capsule().stroke(BSmartColor.line, lineWidth: 0.6) }
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
                        .foregroundStyle(BSmartColor.pulseInk, BSmartColor.brand)
                        .background(BSmartColor.surface, in: Circle())
                        .offset(x: 3, y: 3)
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
            }
        case let .money(movement):
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 38)
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
        BSmartDetailNavigationLink(id: "activity-account-\(update.id)-\(source)") {
            SmartAccountTrustPreviewView(account: account)
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
                update.targetPrice?.formatted(.currency(code: "USD").precision(.fractionLength(0)))
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
                position.averageCost.formatted(.currency(code: "USD").precision(.fractionLength(2)))
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
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
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
