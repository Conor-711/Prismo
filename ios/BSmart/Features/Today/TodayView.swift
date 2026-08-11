import SwiftUI

private enum TodaySignalFilter: String, CaseIterable, Identifiable {
    case all
    case risk
    case opportunity
    case unread

    var id: Self { self }

    var label: String {
        let key = switch self {
        case .all: "All"
        case .risk: "Risk"
        case .opportunity: "Opportunity"
        case .unread: "Unread"
        }
        return key.bSmartLocalized
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .risk: "exclamationmark.triangle.fill"
        case .opportunity: "arrow.up.right"
        case .unread: "circle.fill"
        }
    }
}

private enum TodayEvidenceFilter: String, CaseIterable, Identifiable {
    case all
    case accounts
    case money
    case relationships

    var id: Self { self }

    var label: String {
        let key = switch self {
        case .all: "All evidence"
        case .accounts: "Smart Account"
        case .money: "Smart Money"
        case .relationships: "Evidence relationships"
        }
        return key.bSmartLocalized
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .accounts: SignalEvidenceSource.smartAccount.symbol
        case .money: SignalEvidenceSource.smartMoney.symbol
        case .relationships: "arrow.left.arrow.right"
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isAddingPosition = false
    @State private var isShowingSignalLibrary = false
    @State private var isShowingNotificationSettings = false
    @State private var isShowingEvidenceFilters = false
    @State private var signalFilter: TodaySignalFilter = .all
    @State private var evidenceFilter: TodayEvidenceFilter = .all

    private var filteredPortfolioSignals: [PersonalizedPortfolioSignal] {
        model.personalizedPortfolioSignals.filter { item in
            let signal = item.signal
            let matchesSignal = switch signalFilter {
            case .all:
                true
            case .risk:
                item.personalization.attention == .priority
                    || signal.direction == .bearish
                    || signal.direction == .mixed
                    || signal.kind == .divergence
            case .opportunity:
                signal.direction == .bullish && signal.kind != .divergence
            case .unread:
                !model.signalUserState(for: signal.id).isRead
            }

            let matchesEvidence = switch evidenceFilter {
            case .all:
                true
            case .accounts:
                signal.evidence.contains { $0.source == .smartAccount }
            case .money:
                signal.evidence.contains { $0.source == .smartMoney }
            case .relationships:
                signal.kind == .confirmation || signal.kind == .divergence
            }

            return matchesSignal && matchesEvidence
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
                        portfolioStatusStrip

                        if let lead = model.personalizedPortfolioSignals.first {
                            BSmartSectionTitle(
                                title: "Top priority",
                                detail: "Ranked by portfolio impact"
                            )

                            NavigationLink(value: lead.signal) {
                                EventCard(
                                    signal: lead.signal,
                                    personalization: lead.personalization,
                                    userState: model.signalUserState(for: lead.id),
                                    isPriority: true
                                )
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                model.markSignalRead(lead.id)
                            })
                        } else {
                            noRelevantEvents
                        }

                        NavigationLink {
                            DailyDigestView()
                        } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                Image(systemName: "text.page.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BSmartColor.pulse)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Daily portfolio brief".bSmartLocalized)
                                        .font(.subheadline.weight(.semibold))
                                    Text("A concise review of the last 24 hours".bSmartLocalized)
                                        .font(.caption2)
                                        .foregroundStyle(BSmartColor.tertiaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BSmartColor.tertiaryText)
                            }
                            .padding(.vertical, BSmartSpacing.small)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.daily-digest")

                        if model.personalizedPortfolioSignals.count > 1 {
                            signalFeedHeader
                            signalFilters

                            if secondaryFilteredSignals.isEmpty {
                                noFilteredEvents
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(secondaryFilteredSignals.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 {
                                            Divider().overlay(BSmartColor.line)
                                        }
                                NavigationLink(value: item.signal) {
                                    EventCard(
                                        signal: item.signal,
                                        personalization: item.personalization,
                                        userState: model.signalUserState(for: item.id),
                                                isPriority: false
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    model.markSignalRead(item.id)
                                })
                            }
                                }
                                .background(BSmartColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                                        .stroke(BSmartColor.line, lineWidth: 0.6)
                                }
                            }
                        }

                        if !model.ignoredPortfolioSignals.isEmpty {
                            Button {
                                isShowingSignalLibrary = true
                            } label: {
                                Label(
                                    "Review \(model.ignoredPortfolioSignals.count) ignored signal\(model.ignoredPortfolioSignals.count == 1 ? "" : "s")",
                                    systemImage: "eye.slash"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BSmartColor.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BSmartSpacing.medium)
                            }
                            .buttonStyle(.plain)
                        }

                        if !model.followedIntelligenceSignals.isEmpty {
                            BSmartSectionHeader(
                                title: "From people you track",
                                detail: "Outside your current portfolio"
                            )

                            ForEach(model.followedIntelligenceSignals) { signal in
                                NavigationLink(value: signal) {
                                    EventCard(
                                        signal: signal,
                                        personalization: model.personalization(for: signal),
                                        userState: model.signalUserState(for: signal.id),
                                        isPriority: false
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    model.markSignalRead(signal.id)
                                })
                            }
                        }

                        if !unfollowedOpportunitySignals.isEmpty {
                            BSmartSectionHeader(
                                title: "Opportunity radar",
                                detail: "Qualified changes outside your portfolio"
                            )

                            NavigationLink {
                                OpportunityRadarView()
                            } label: {
                                OpportunityRadarPreview(
                                    signal: unfollowedOpportunitySignals[0],
                                    count: model.opportunitySignals.count
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.opportunity-radar")
                        }
                    }
                }
                .padding(BSmartSpacing.large)
                .padding(.bottom, BSmartSpacing.small)
            }
            .accessibilityIdentifier("today.screen")
            .background(BSmartColor.ink)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PortfolioSignal.self) { signal in
                EventDetailView(signal: signal)
            }
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
            .sheet(isPresented: $isShowingSignalLibrary) {
                SignalLibraryView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $isShowingNotificationSettings) {
                NotificationSettingsView()
            }
            .sheet(isPresented: $isShowingEvidenceFilters) {
                TodayEvidenceFilterSheet(selection: $evidenceFilter)
                    .presentationDetents([.height(330), .medium])
                    .presentationDragIndicator(.visible)
            }
            .task(id: router.pendingSignalID) {
                router.resolvePendingSignal(from: model.signals)
            }
            .onChange(of: model.signals) { _, signals in
                router.resolvePendingSignal(from: signals)
            }
        }
        // Today is a dense monitoring surface. Keep its dashboard hierarchy usable at
        // extreme accessibility sizes; evidence detail screens remain fully scalable.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .bSmartPage()
    }

    private var unfollowedOpportunitySignals: [PortfolioSignal] {
        let followedIDs = Set(model.followedIntelligenceSignals.map(\.id))
        return model.opportunitySignals.filter { !followedIDs.contains($0.id) }
    }

    private var secondaryFilteredSignals: [PersonalizedPortfolioSignal] {
        guard let leadID = model.personalizedPortfolioSignals.first?.id else {
            return filteredPortfolioSignals
        }
        return filteredPortfolioSignals.filter { $0.id != leadID }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack(alignment: .center, spacing: BSmartSpacing.medium) {
                BSmartPageTitle(
                    eyebrow: "Portfolio monitor",
                    title: "Today",
                    subtitle: pageSubtitle
                )

                Spacer()

                if model.isUsingDemoData {
                    BSmartTag(text: "DEMO", color: BSmartColor.gold)
                        .accessibilityLabel("Demo data")
                }

                BSmartIconButton(
                    symbol: "bell.fill",
                    accessibilityLabel: "Open alert settings"
                ) {
                    isShowingNotificationSettings = true
                }

                if !model.savedSignals.isEmpty || !model.ignoredPortfolioSignals.isEmpty {
                    BSmartIconButton(
                        symbol: "tray.full.fill",
                        accessibilityLabel: "Open saved and ignored signals"
                    ) {
                        isShowingSignalLibrary = true
                    }
                }
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

    private var portfolioStatusStrip: some View {
        BSmartMetricStrip(metrics: portfolioStatusMetrics)
        .accessibilityIdentifier("today.portfolio-status")
    }

    private var portfolioStatusMetrics: [BSmartStripMetric] {
        if !model.hasAnyPortfolioValuation, !model.heldPositions.isEmpty {
            return [
                BSmartStripMetric(
                    id: "positions",
                    label: "Positions",
                    value: portfolioHeadlineValue
                ),
                BSmartStripMetric(
                    id: "allocation",
                    label: "Declared allocation",
                    value: model.declaredPortfolioWeight > 0
                        ? model.declaredPortfolioWeight.formatted(.percent.precision(.fractionLength(0)))
                        : "Optional"
                ),
                BSmartStripMetric(
                    id: "attention",
                    label: "Needs attention",
                    value: "\(model.unreadPortfolioSignalCount)",
                    color: model.unreadPortfolioSignalCount > 0 ? BSmartColor.bear : BSmartColor.primaryText
                ),
            ]
        }

        return [
            BSmartStripMetric(
                id: "status",
                label: "Portfolio status",
                value: priorityLabel,
                color: priorityColor
            ),
            BSmartStripMetric(
                id: "attention",
                label: "Needs attention",
                value: "\(model.unreadPortfolioSignalCount)",
                color: model.unreadPortfolioSignalCount > 0 ? BSmartColor.bear : BSmartColor.primaryText
            ),
            BSmartStripMetric(
                id: "checked",
                label: "Last check",
                value: model.lastDataRefreshAt?.bSmartRelativeTimestamp ?? "Waiting",
                color: BSmartColor.primaryText
            ),
        ]
    }

    private var pageSubtitle: String {
        if model.positions.isEmpty {
            return "Build your portfolio to start monitoring changes".bSmartLocalized
        }
        if model.heldPositions.isEmpty {
            return "For your watchlist".bSmartLocalized
        }
        return "%d changes are connected to your portfolio".bSmartLocalized(model.portfolioSignals.count)
    }

    @ViewBuilder
    private func sourceFreshnessLabel(
        _ key: String,
        freshness: BSmartDataFreshness?
    ) -> some View {
        if let freshness {
            HStack(spacing: 4) {
                Circle()
                    .fill(BSmartColor.brand)
                    .frame(width: 5, height: 5)
                Text(key.bSmartLocalized(freshness.checkedAt.bSmartDataTimestamp))
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .monospacedDigit()
            }
        }
    }

    private var portfolioHeader: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack(alignment: .top, spacing: BSmartSpacing.large) {
                    VStack(alignment: .leading, spacing: 3) {
                        portfolioValueLabel
                        Text(portfolioHeadlineValue)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                    }

                    Spacer(minLength: BSmartSpacing.small)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(model.unreadPortfolioSignalCount)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(model.unreadPortfolioSignalCount > 0 ? BSmartColor.brand : BSmartColor.primaryText)
                            .monospacedDigit()
                        Text("New signals")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BSmartSpacing.small) {
                        portfolioPerformanceLine
                        Spacer(minLength: BSmartSpacing.small)
                        portfolioCountText
                        statusDot
                        Text(priorityLabel.bSmartLocalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(priorityColor)
                    }
                    VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                        portfolioPerformanceLine
                        HStack(spacing: BSmartSpacing.small) {
                            portfolioCountText
                            statusDot
                            Text(priorityLabel.bSmartLocalized)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(priorityColor)
                        }
                    }
                }
            }
            .bSmartPanel(
                padding: BSmartSpacing.large,
                fill: BSmartColor.elevated,
                border: BSmartColor.brand.opacity(0.24)
            )
        }
    }

    private var watchlistHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .top, spacing: BSmartSpacing.large) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Watchlist monitor")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                    Text((model.watchlist.count == 1 ? "%d stock monitored" : "%d stocks monitored").bSmartLocalized(model.watchlist.count))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(model.unreadPortfolioSignalCount)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(model.unreadPortfolioSignalCount > 0 ? BSmartColor.brand : BSmartColor.primaryText)
                        .monospacedDigit()
                    Text("New signals")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }

            HStack(spacing: BSmartSpacing.small) {
                Label(watchlistCoverageLabel.bSmartLocalized, systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.sky)
                Spacer()
                statusDot
                Text(priorityLabel.bSmartLocalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(priorityColor)
            }
        }
        .bSmartPanel(
            padding: BSmartSpacing.large,
            fill: BSmartColor.elevated,
            border: BSmartColor.sky.opacity(0.28)
        )
    }

    private var portfolioValueLabel: some View {
        Text(portfolioValueTitle.bSmartLocalized)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BSmartColor.secondaryText)
    }

    private var portfolioValueTitle: String {
        if model.hasCompletePortfolioValuation { return "Portfolio value" }
        if model.hasAnyPortfolioValuation { return "Known market value" }
        return "Portfolio monitor"
    }

    private var portfolioHeadlineValue: String {
        if model.hasAnyPortfolioValuation {
            return model.portfolioValue.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        }
        let count = model.heldPositions.count
        return (count == 1 ? "%d position" : "%d positions").bSmartLocalized(count)
    }

    private var portfolioCountText: some View {
        Text(portfolioCountLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BSmartColor.tertiaryText)
    }

    private var portfolioGainLabel: some View {
        Label(
            model.portfolioGain.formatted(.currency(code: "USD").precision(.fractionLength(0)).sign(strategy: .always())),
            systemImage: model.portfolioGain >= 0 ? "arrow.up.right" : "arrow.down.right"
        )
        .font(.subheadline.weight(.bold))
        .foregroundStyle(model.portfolioGain >= 0 ? BSmartColor.brand : BSmartColor.bear)
    }

    private var portfolioGainPercentText: some View {
        Text(model.portfolioGainPercent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(model.portfolioGain >= 0 ? BSmartColor.brand : BSmartColor.bear)
            .monospacedDigit()
    }

    private var unrealizedText: some View {
        Text((model.hasCompletePortfolioReturn ? "unrealized" : "known positions only").bSmartLocalized)
            .font(.caption)
            .foregroundStyle(BSmartColor.tertiaryText)
    }

    @ViewBuilder
    private var portfolioPerformanceLine: some View {
        if model.hasAnyPortfolioReturn {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BSmartSpacing.small) {
                    portfolioGainLabel
                    portfolioGainPercentText
                    unrealizedText
                }
                VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                    HStack(spacing: BSmartSpacing.small) {
                        portfolioGainLabel
                        portfolioGainPercentText
                    }
                    unrealizedText
                }
            }
        } else if model.hasAnyPortfolioValuation {
            Label("Add cost basis to calculate return", systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.secondaryText)
        } else {
            Label(allocationContextLabel, systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BSmartColor.sky)
        }
    }

    private var allocationContextLabel: String {
        guard model.declaredPortfolioWeight > 0 else {
            return "Monitoring qualified changes; position size is optional".bSmartLocalized
        }
        return "%@ declared allocation".bSmartLocalized(
            model.declaredPortfolioWeight.formatted(.percent.precision(.fractionLength(0)))
        )
    }

    @ViewBuilder
    private var portfolioMetrics: some View {
        if model.portfolioCostBasis > 0 {
            compactMetric(
                label: model.hasCompletePortfolioReturn ? "Cost basis" : "Known cost",
                value: model.portfolioCostBasis.formatted(.currency(code: "USD").precision(.fractionLength(0)))
            )
        } else {
            compactMetric(
                label: "Declared allocation",
                value: model.declaredPortfolioWeight > 0
                    ? model.declaredPortfolioWeight.formatted(.percent.precision(.fractionLength(0)))
                    : "Optional"
            )
        }
        compactMetric(label: "Priority", value: priorityLabel)
        compactMetric(label: "New signals", value: "\(model.unreadPortfolioSignalCount)")
    }

    private var portfolioCountLabel: String {
        let positionCount = model.heldPositions.count
        let watchCount = model.watchlist.count
        if watchCount == 0 {
            return (positionCount == 1 ? "%d position" : "%d positions").bSmartLocalized(positionCount)
        }
        return "%d held · %d watched".bSmartLocalized(positionCount, watchCount)
    }

    private var priorityLabel: String {
        guard let signal = model.portfolioSignals.first else { return "Clear" }
        return model.personalization(for: signal).attention.label
    }

    private var priorityColor: Color {
        guard let signal = model.portfolioSignals.first else { return BSmartColor.brand }
        return model.personalization(for: signal).attention.color
    }

    private var statusDot: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }

    private var liveSignalLabel: String {
        let count = filteredPortfolioSignals.count
        let unread = model.unreadPortfolioSignalCount
        if signalFilter == .all && evidenceFilter == .all {
            return "%d new · %d live".bSmartLocalized(unread, count)
        }
        return "%d matching · %d new".bSmartLocalized(count, unread)
    }

    private var signalFeedHeader: some View {
        HStack(alignment: .center, spacing: BSmartSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text("More changes".bSmartLocalized)
                    .font(.headline)
                Text(liveSignalLabel)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                isShowingEvidenceFilters = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: evidenceFilter.symbol)
                        .font(.caption.weight(.bold))
                    Text((evidenceFilter == .all ? "Evidence".bSmartLocalized : evidenceFilter.label))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(evidenceFilter == .all ? BSmartColor.secondaryText : BSmartColor.electric)
                .padding(.horizontal, BSmartSpacing.small)
                .frame(height: 32)
                .background(BSmartColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .stroke(evidenceFilter == .all ? BSmartColor.line : BSmartColor.electric.opacity(0.7), lineWidth: 0.75)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.filter.evidence")
            .accessibilityLabel("Evidence filter")
        }
    }

    private var signalFilters: some View {
        HStack(spacing: 0) {
            ForEach(TodaySignalFilter.allCases) { filter in
                Button {
                    withAnimation(BSmartMotion.quick) {
                        signalFilter = filter
                    }
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 5) {
                            Image(systemName: filter.symbol)
                                .font(.caption2.weight(.bold))
                            Text(filter.label)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(signalFilter == filter ? BSmartColor.primaryText : BSmartColor.tertiaryText)

                        Rectangle()
                            .fill(signalFilter == filter ? BSmartColor.brand : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.filter.\(filter.rawValue)")
                .accessibilityAddTraits(signalFilter == filter ? .isSelected : [])
            }
        }
        .padding(.horizontal, BSmartSpacing.xSmall)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.5)
        }
        .sensoryFeedback(.selection, trigger: signalFilter)
    }

    private var monitorStatusText: String {
        if model.errorMessage != nil { return "Cached" }
        if model.isLoading || model.isRefreshingLiveIntelligence { return "Updating" }
        return "Live"
    }

    private var monitorStatusColor: Color {
        model.errorMessage == nil ? BSmartColor.brand : BSmartColor.gold
    }

    private var watchlistCoverageLabel: String {
        let sources = Set(model.portfolioSignals.flatMap { $0.evidence.map(\.source) })
        if sources == Set(SignalEvidenceSource.allCases) { return "Both" }
        if sources == [.smartAccount] { return "Account" }
        if sources == [.smartMoney] { return "Money" }
        return "Waiting"
    }

    private func compactMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyPortfolio: some View {
        ContentUnavailableView {
            Label("Build your portfolio", systemImage: "plus.circle.fill")
        } description: {
            Text("Add positions or watched stocks to receive a personal stream of important changes.")
        } actions: {
            Button("Add ticker") {
                isAddingPosition = true
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("today.empty-portfolio")
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var noRelevantEvents: some View {
        ContentUnavailableView {
            Label("No important changes", systemImage: "checkmark.circle")
        } description: {
            Text("Your tracked tickers have no new signals that meet the current evidence threshold.")
        }
        .accessibilityIdentifier("today.no-signals")
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var noFilteredEvents: some View {
        VStack(spacing: BSmartSpacing.medium) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text("No matching changes")
                .font(.headline)
            Text("No current signal matches these filters.")
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Show all") {
                signalFilter = .all
                evidenceFilter = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .accessibilityIdentifier("today.no-filtered-signals")
    }
}

private struct TodayEvidenceFilterSheet: View {
    @Binding var selection: TodayEvidenceFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence filter")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Choose which evidence should appear in your signal feed.")
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                }

                VStack(spacing: 0) {
                    ForEach(TodayEvidenceFilter.allCases) { filter in
                        Button {
                            selection = filter
                            dismiss()
                        } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                Image(systemName: filter.symbol)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(selection == filter ? BSmartColor.ink : BSmartColor.secondaryText)
                                    .frame(width: 34, height: 34)
                                    .background(selection == filter ? BSmartColor.brand : BSmartColor.elevated)
                                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))

                                Text(filter.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BSmartColor.primaryText)

                                Spacer()

                                if selection == filter {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(BSmartColor.brand)
                                }
                            }
                            .frame(minHeight: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.filter.\(filter.rawValue)")
                        .accessibilityAddTraits(selection == filter ? .isSelected : [])

                        if filter != TodayEvidenceFilter.allCases.last {
                            Divider().overlay(BSmartColor.line)
                        }
                    }
                }
                .padding(.horizontal, BSmartSpacing.medium)
                .background(BSmartColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                        .stroke(BSmartColor.line, lineWidth: 0.5)
                }

                Spacer(minLength: 0)
            }
            .padding(BSmartSpacing.large)
            .background(BSmartColor.ink.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .bSmartPage()
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
