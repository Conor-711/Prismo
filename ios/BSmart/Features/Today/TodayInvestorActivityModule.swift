import SwiftUI

struct TodayInvestorActivityModule: View {
    var body: some View {
        TodayInvestorActivityContent(isPreview: false)
    }
}

struct TodayInvestorActivityCollectionView: View {
    var body: some View {
        ScrollView {
            TodayInvestorActivityContent(isPreview: false)
                .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Smart updates".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("smart-updates.collection")
    }
}

private struct TodayInvestorActivityContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.bSmartPageIsActive) private var isPageActive
    let isPreview: Bool
    @State private var hasBuiltFeed = false
    @State private var feedItems: [TodayHomeFeedItem] = []
    @State private var displayedRuns: [TodayHomeFeedRun] = []
    @State private var preparedSources: [AccountPlatformFilter: TodayFeedSourceProjection] = [:]
    @State private var preparedConfiguration: DisplayConfiguration?
    @State private var displayedSource: AccountPlatformFilter?
    @State private var builtRevision: Int?
    @State private var builtDay: String?
    @State private var displayRevision = 0
    @State private var builtDisplayRevision: Int?
    @State private var visibleLimit = 60
    @State private var platform: AccountPlatformFilter = .all
    @State private var activityType: TodayFeedActivityType = .all
    @State private var timeSort: TodayFeedTimeSort = .newest
    @State private var trendingOnly = false
    @State private var followingOnly = false
    @State private var showsFilters = false
    @State private var showsPlatformSources = false

    private struct BuildKey: Hashable {
        let active: Bool
        let revision: Int
        let day: String
    }

    private var buildKey: BuildKey {
        .init(active: isPageActive && scenePhase == .active,
              revision: model.todayFeedRevision, day: SubjectFeedDay.format(Date()))
    }

    private struct DisplayKey: Hashable {
        let active: Bool
        let revision: Int
    }

    private var displayKey: DisplayKey { .init(active: buildKey.active, revision: displayRevision) }

    private struct DisplayConfiguration: Equatable {
        let options: TodayFeedDisplayOptions
        let accounts: Set<String>
        let money: Set<String>
        let subjects: Set<String>
    }

    private var displayConfiguration: DisplayConfiguration {
        .init(options: .init(activityType: activityType, followingOnly: followingOnly,
                            trendingOnly: trendingOnly, timeSort: timeSort, isPreview: isPreview),
              accounts: followingOnly ? model.followedSmartAccountIDs : [],
              money: followingOnly ? model.followedSmartMoneyIDs : [],
              subjects: followingOnly ? model.followedSubjectIDs : [])
    }

    private func isTracked(_ investor: TodayInvestorActivity) -> Bool {
        switch investor.latest {
        case let .account(account):
            return model.isFollowingSmartAccount(model.smartAccountProfile(for: account.latest).id)
        case let .money(money):
            return model.isFollowingSmartMoney(money.accountId)
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            if isPreview {
                BSmartDetailNavigationLink(id: "today-smart-updates-library") {
                    TodayInvestorActivityCollectionView()
                } label: {
                    TodayEditorialSectionTitle(title: "Smart updates", showsDisclosure: true)
                }
                .buttonStyle(.bSmartPlain)
                .accessibilityIdentifier("today.smart-updates.title")
            }
            if !isPreview {
                controls
                if model.nativeInvestorLoadFailed {
                    Button { Task { await model.refreshNativeInvestors() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                            Text("bSmart activity unavailable".bSmartLocalized)
                            Spacer(minLength: 8)
                            Text("Retry".bSmartLocalized)
                                .foregroundStyle(BSmartColor.brand)
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(BSmartColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bSmartPlain)
                    .accessibilityIdentifier("smart-updates.native-retry")
                }
            }

            if !hasBuiltFeed || builtDisplayRevision == nil || displayedSource == nil
                || (model.isLoading && feedItems.isEmpty) {
                BSmartSkeletonRows(style: .feed, count: isPreview ? 2 : 4)
            } else if displayedRuns.isEmpty {
                Label((followingOnly ? "No updates from tracked investors in the last 30 days" :
                    "No matching updates in the last 30 days").bSmartLocalized, systemImage: "text.bubble")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .padding(.vertical, 24)
                    .accessibilityIdentifier("smart-updates.empty")
            } else {
                ForEach(Array(displayedRuns.prefix(visibleLimit).enumerated()), id: \.element.id) { entry in
                    TodayHomeFeedRunView(run: entry.element, isFirstRun: entry.offset == 0)
                }
                if displayedRuns.count > visibleLimit {
                    Color.clear.frame(height: 1)
                        .onAppear { visibleLimit = min(visibleLimit + 60, displayedRuns.count) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-updates.feed")
        .accessibilityValue(displayedSource?.rawValue ?? "loading")
        .task(id: buildKey) {
            guard buildKey.active, builtRevision != buildKey.revision || builtDay != buildKey.day else { return }
            await rebuild()
        }
        .task(id: displayKey) {
            guard displayKey.active, hasBuiltFeed, builtDisplayRevision != displayRevision else { return }
            await updateDisplayedItems()
        }
        .onChange(of: model.followedSmartAccountIDs) { if followingOnly { refreshDisplayedItems() } }
        .onChange(of: model.followedSmartMoneyIDs) { if followingOnly { refreshDisplayedItems() } }
        .onChange(of: model.followedSubjectIDs) { if followingOnly { refreshDisplayedItems() } }
        .sheet(isPresented: $showsFilters) { selectionSheet }
    }

    private var controls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button { showsFilters = true } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(hasActiveFilters ? BSmartColor.brand : BSmartColor.primaryText)
                        .frame(width: 50, height: 46)
                        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(BSmartColor.line, lineWidth: 0.75))
                        .overlay(alignment: .topTrailing) {
                            if hasActiveFilters {
                                Circle().fill(BSmartColor.brand).frame(width: 6, height: 6).padding(5)
                            }
                        }
                }
                .buttonStyle(.bSmartPlain)
                .accessibilityLabel("Filters".bSmartLocalized)
                .accessibilityIdentifier("smart-updates.filters")

                ForEach(AccountPlatformFilter.quickOrder) { option in
                    Button {
                        if option == .social {
                            showsPlatformSources = true
                        } else {
                            withTransaction(Transaction(animation: nil)) {
                                selectSource(option)
                            }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            sourceLogo(option)
                            Text(option == .social ? socialSourceTitle : option.title.bSmartLocalized).lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected(option) ? BSmartColor.primaryText : BSmartColor.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 46)
                        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottom) {
                            if isSelected(option) { BSmartColor.brand.frame(height: 2) }
                        }
                    }
                    .buttonStyle(.bSmartPlain)
                    .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
                    .accessibilityIdentifier("smart-updates.platform.\(option.rawValue)")
                    .popover(isPresented: option == .social ? $showsPlatformSources : .constant(false), arrowEdge: .bottom) {
                        platformSourcePicker
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("smart-updates.sources")
    }

    private var hasActiveFilters: Bool {
        activityType != .all || followingOnly || trendingOnly || timeSort != .newest
    }

    private var socialSourceTitle: String {
        switch platform {
        case .x, .youtube, .reddit: "\("Platform".bSmartLocalized) · \(platform.title)"
        default: "Platform".bSmartLocalized
        }
    }

    private func isSelected(_ option: AccountPlatformFilter) -> Bool {
        option == .social ? platform.isSocial : platform == option
    }

    private var platformSourcePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AccountPlatformFilter.socialOptions) { option in
                Button {
                    withTransaction(Transaction(animation: nil)) {
                        selectSource(option)
                    }
                    showsPlatformSources = false
                } label: {
                    HStack(spacing: 10) {
                        sourceLogo(option)
                        Text(option == .social ? "All platforms".bSmartLocalized : option.title)
                        Spacer(minLength: 12)
                        if platform == option {
                            Image(systemName: "checkmark").foregroundStyle(BSmartColor.brand)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bSmartPlain)
                .accessibilityIdentifier("smart-updates.platform-choice.\(option.rawValue)")
            }
        }
        .padding(8)
        .frame(width: 220)
        .background(BSmartColor.surface)
    }

    private var selectionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filters".bSmartLocalized).font(.headline)
                Spacer()
                if hasActiveFilters {
                    Button("Reset".bSmartLocalized) {
                        withTransaction(Transaction(animation: nil)) {
                            activityType = .all
                            timeSort = .newest
                            trendingOnly = false
                            followingOnly = false
                            refreshDisplayedItems()
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSmartColor.brand)
                    .accessibilityIdentifier("smart-updates.filters.reset")
                }
                Button { showsFilters = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                    .buttonStyle(.bSmartPlain)
                    .accessibilityLabel("Close".bSmartLocalized)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sort by".bSmartLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                    selectionRow("Trending", symbol: "chart.line.uptrend.xyaxis", selected: trendingOnly) {
                        withTransaction(Transaction(animation: nil)) {
                            trendingOnly = true
                            refreshDisplayedItems()
                        }
                    }
                    .accessibilityIdentifier("smart-updates.sort.trending")
                    ForEach(TodayFeedTimeSort.allCases) { option in
                        selectionRow(option.title, symbol: option.symbol,
                                     selected: !trendingOnly && timeSort == option) {
                            withTransaction(Transaction(animation: nil)) {
                                timeSort = option
                                trendingOnly = false
                                refreshDisplayedItems()
                            }
                        }
                        .accessibilityIdentifier("smart-updates.sort.\(option.rawValue)")
                    }
                    Divider().overlay(BSmartColor.line)
                    Text("Tracking".bSmartLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                    selectionRow("Show tracked only", symbol: "checkmark.circle", selected: followingOnly) {
                        withTransaction(Transaction(animation: nil)) {
                            followingOnly.toggle()
                            refreshDisplayedItems()
                        }
                    }
                    .accessibilityIdentifier("smart-updates.following-only")
                    Divider().overlay(BSmartColor.line)
                    Text("Activity type".bSmartLocalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.secondaryText)
                    VStack(spacing: 9) {
                        HStack(spacing: 9) {
                            activityTypeChoice(.all)
                            activityTypeChoice(.opinions)
                        }
                        HStack(spacing: 9) {
                            activityTypeChoice(.trades)
                            activityTypeChoice(.holdings)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Button { showsFilters = false } label: {
                Text("Done".bSmartLocalized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BSmartColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.bSmartPlain)
            .accessibilityIdentifier("smart-updates.filters.done")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.ink.ignoresSafeArea())
        .presentationBackground(BSmartColor.ink)
        .presentationDetents([.height(640), .large])
        .presentationDragIndicator(.visible)
    }

    private func activityTypeChoice(_ option: TodayFeedActivityType) -> some View {
        selectionRow(option.title, symbol: option.symbol, selected: activityType == option) {
            withTransaction(Transaction(animation: nil)) {
                activityType = option
                refreshDisplayedItems()
            }
        }
        .accessibilityIdentifier("smart-updates.type.\(option.rawValue)")
    }

    private func selectionRow(_ title: String, symbol: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 20)
                Text(title.bSmartLocalized).lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(BSmartColor.brand) }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(selected ? BSmartColor.brand : BSmartColor.primaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                selected ? BSmartColor.brand.opacity(0.5) : BSmartColor.line, lineWidth: 0.75))
        }
        .buttonStyle(.bSmartPlain)
    }

    @ViewBuilder private func sourceLogo(_ option: AccountPlatformFilter) -> some View {
        switch option {
        case .x:
            Image("PlatformX").resizable().scaledToFit().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        case .youtube:
            Image("PlatformYouTube").resizable().scaledToFit().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        case .reddit:
            Image("PlatformReddit").resizable().scaledToFit().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        case .bsmart:
            Image("PlatformBSmart").resizable().scaledToFit().frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        case .politicians:
            SmartPlatformMark(platform: "congress", size: 32)
        case .celebrities:
            SmartPlatformMark(platform: "celebrity", size: 32)
        case .institutions:
            SmartPlatformMark(platform: "institution", size: 32)
        case .social:
            ZStack {
                Image("PlatformX").resizable().scaledToFill()
                    .frame(width: 20, height: 20).clipShape(Circle()).offset(x: -8, y: -5)
                Image("PlatformYouTube").resizable().scaledToFill()
                    .frame(width: 20, height: 20).clipShape(Circle()).offset(x: 8, y: -5)
                Image("PlatformReddit").resizable().scaledToFill()
                    .frame(width: 20, height: 20).clipShape(Circle()).offset(y: 8)
            }
            .frame(width: 36, height: 32)
        case .all:
            EmptyView()
        }
    }

    private func rebuild() async {
        let key = buildKey
        let updates = model.smartAccountUpdates
        let movements = BSmartProductVisibility.onchainSmartMoney ? model.smartMoneyMovements : []
        let subjects = model.subjectActivitySnapshot
        let preview = isPreview
        let worker = Task.detached(priority: .userInitiated) {
            Self.buildItems(updates: updates, movements: movements, snapshot: subjects, isPreview: preview)
        }
        let nextFeedItems = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        guard !Task.isCancelled, key == buildKey else { return }
        feedItems = nextFeedItems
        refreshDisplayedItems()
        builtRevision = key.revision
        builtDay = key.day
        hasBuiltFeed = true
    }

    nonisolated private static func buildItems(updates: [SmartAccountUpdate], movements: [SmartMoneyMovement],
                                               snapshot: TodaySubjectFeedSnapshot, isPreview: Bool) -> [TodayHomeFeedItem] {
        let nextInvestors = TodayInvestorActivity.groups(accountUpdates: updates, moneyMovements: movements)
        let nextSubjects = TodaySubjectActivity.groups(from: snapshot)
        let selected = isPreview ? TodayInvestorActivity.previewAccounts(from: nextInvestors.filter {
            $0.source == .accounts
        }) : nextInvestors
        let accounts = selected.flatMap { investor in
            (isPreview ? Array(investor.activities.prefix(1)) : investor.activities)
                .map { TodayHomeFeedItem.investor(.init(id: investor.id, activities: [$0])) }
        }
        let recentCutoff = Date().addingTimeInterval(-30 * 86_400)
        let others = isPreview ? [] : nextSubjects.flatMap { subject in
            subject.events.filter {
                $0.displayedAt >= recentCutoff || ($0.type == .holding && $0.id == subject.latest.id)
            }.map { TodayHomeFeedItem.subject(.init(subject: subject.subject, events: [$0]), subject) }
        }
        return accounts + others
    }

    private func refreshDisplayedItems() {
        displayRevision &+= 1
        visibleLimit = 60
    }

    private func selectSource(_ source: AccountPlatformFilter) {
        guard platform != source else { return }
        platform = source
        visibleLimit = 60
        // A background content refresh can keep the last complete, same-filter projection.
        if preparedConfiguration == displayConfiguration, let projection = preparedSources[source] {
            displayedRuns = projection.runs
            displayedSource = source
        } else {
            // Never leave the previous source's cards beneath a newly selected source.
            displayedRuns = []
            displayedSource = nil
        }
    }

    private func updateDisplayedItems() async {
        let key = displayKey
        let items = feedItems
        let configuration = displayConfiguration
        let options = configuration.options
        let trackedSubjects = configuration.subjects
        var seenInvestors = Set<String>()
        let trackedInvestors = followingOnly ? Set(items.compactMap { item -> String? in
            guard case let .investor(investor) = item, seenInvestors.insert(investor.id).inserted,
                  isTracked(investor) else { return nil }
            return investor.id
        }) : []
        let worker = Task.detached(priority: .userInitiated) {
            TodayFeedSourceProjection.prepare(from: items, options: options,
                trackedInvestors: trackedInvestors, trackedSubjects: trackedSubjects)
        }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, key == displayKey, configuration == displayConfiguration else { return }
        withTransaction(Transaction(animation: nil)) {
            preparedSources = result
            preparedConfiguration = configuration
            displayedRuns = result[platform]?.runs ?? []
            displayedSource = platform
            builtDisplayRevision = key.revision
        }
    }
}

private struct TodayHomeFeedRunView: View {
    let run: TodayHomeFeedRun
    let isFirstRun: Bool
    @State private var isExpanded = false

    private var visibleItems: [TodayHomeFeedItem] {
        isExpanded ? run.items : Array(run.items.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { entry in
                let hasDivider = !isFirstRun || entry.offset > 0
                card(for: entry.element, showsTopDivider: hasDivider)
                    .padding(.top, entry.offset > 0 ? 14 : (hasDivider ? 4 : 0))
                if entry.offset == 1 && run.items.count > 2 {
                    TodayActivityOverflowButton(name: run.actorName,
                                                remainingCount: run.hiddenEventCount,
                                                isExpanded: isExpanded) {
                        isExpanded.toggle()
                    }
                    .padding(.bottom, 2)
                    .accessibilityIdentifier("smart-updates.burst.\(run.id)")
                }
            }
        }
    }

    @ViewBuilder
    private func card(for item: TodayHomeFeedItem, showsTopDivider: Bool) -> some View {
        switch item {
        case let .investor(investor):
            TodayInvestorActivityCard(investor: investor, showsTopDivider: showsTopDivider)
        case let .subject(subject, _):
            TodaySubjectActivityCard(activity: subject, showsTopDivider: showsTopDivider)
        }
    }
}

enum AccountPlatformFilter: String, CaseIterable, Identifiable {
    case all, social, x, youtube, reddit, bsmart, politicians, celebrities, institutions

    var id: String { rawValue }
    static let quickOrder: [Self] = [.all, .bsmart, .social, .politicians, .celebrities, .institutions]
    static let socialOptions: [Self] = [.social, .x, .youtube, .reddit]
    var isSocial: Bool { self == .social || self == .x || self == .youtube || self == .reddit }
    var shortTitle: String {
        switch self {
        case .all: "Sources"
        case .celebrities: "Figures"
        default: title
        }
    }
    var title: String {
        switch self {
        case .all: "All sources"
        case .social: "Platform"
        case .x: "X"
        case .youtube: "YouTube"
        case .reddit: "Reddit"
        case .bsmart: "Live trading"
        case .politicians: "Politicians"
        case .celebrities: "Public figures"
        case .institutions: "Institutions"
        }
    }

    func matches(_ investor: TodayInvestorActivity) -> Bool {
        guard self != .all else { return true }
        guard case let .account(account) = investor.latest else { return false }
        let source = account.latest.platform.lowercased()
        switch self {
        case .all: return true
        case .social: return source == "x" || source.contains("twitter")
            || source.contains("youtube") || source.contains("reddit")
        case .x: return source == "x" || source.contains("twitter")
        case .youtube: return source.contains("youtube")
        case .reddit: return source.contains("reddit")
        case .bsmart: return source == "bsmart"
        case .politicians, .celebrities, .institutions: return false
        }
    }

    func matches(_ subject: TodaySubjectActivity) -> Bool {
        switch self {
        case .all: true
        case .politicians: subject.subject.kind == .politician
        case .celebrities: subject.subject.kind == .celebrity
        case .institutions: subject.subject.kind == .institution
        default: false
        }
    }
}

enum TodayFeedActivityType: String, CaseIterable, Identifiable {
    case all, opinions, trades, holdings

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All activity types"
        case .opinions: "Opinions"
        case .trades: "Trades"
        case .holdings: "Holdings"
        }
    }
    var shortTitle: String { self == .all ? "Type" : title }
    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease"
        case .opinions: "text.bubble"
        case .trades: "arrow.left.arrow.right"
        case .holdings: "square.stack"
        }
    }

    func matches(_ activity: TodayActivity) -> Bool {
        switch activity {
        case let .account(account):
            let isTrade = account.latest.platform == "bsmart"
            return self == .all || (isTrade ? self == .trades : self == .opinions)
        case .money: return self == .all || self == .trades
        }
    }

    func matches(_ event: TodaySubjectEvent) -> Bool {
        switch event.type {
        case .opinion: self == .all || self == .opinions
        case .trade: self == .all || self == .trades
        case .holding: self == .all || self == .holdings
        }
    }
}

enum TodayFeedTimeSort: String, CaseIterable, Identifiable {
    case newest, oldest
    var id: Self { self }
    var title: String { self == .newest ? "Newest first" : "Oldest first" }
    var symbol: String { self == .newest ? "arrow.down" : "arrow.up" }
}

enum TodayHomeFeedItem: Identifiable {
    case investor(TodayInvestorActivity)
    case subject(TodaySubjectActivity, TodaySubjectActivity)

    var id: String {
        switch self {
        case let .investor(value): "investor:\(value.latest.id)"
        case let .subject(value, _): "subject:\(value.latest.id)"
        }
    }

    var occurredAt: Date {
        switch self {
        case let .investor(value): value.latest.occurredAt
        case let .subject(value, _): value.latest.displayedAt
        }
    }

    var actorID: String {
        switch self {
        case let .investor(value): value.id
        case let .subject(value, _): value.id
        }
    }

    var actorName: String {
        switch self {
        case let .investor(value): value.name
        case let .subject(value, _): value.name
        }
    }

    var ticker: String? {
        switch self {
        case let .investor(value): value.latest.ticker.uppercased()
        case let .subject(value, _): value.latest.ticker?.uppercased()
        }
    }

    var eventCount: Int {
        switch self {
        case let .investor(value): value.activities.count
        case let .subject(value, _): value.events.count
        }
    }

    private var actorAndAsset: String? {
        switch self {
        case let .investor(value): "\(value.id):\(value.latest.ticker.uppercased())"
        case let .subject(value, _):
            value.latest.ticker.map { "\(value.id):\($0.uppercased())" }
        }
    }

    static func mergeAdjacent(_ items: [Self], dateForItem: (Self) -> Date = { $0.occurredAt }) -> [Self] {
        var result: [Self] = []
        for item in items {
            guard let last = result.last, let key = item.actorAndAsset,
                  key == last.actorAndAsset,
                  dateForItem(last).timeIntervalSince(dateForItem(item)) <= 3 * 86_400 else {
                result.append(item)
                continue
            }
            result.removeLast()
            switch (last, item) {
            case let (.investor(lhs), .investor(rhs)):
                result.append(.investor(.init(id: lhs.id, activities: lhs.activities + rhs.activities)))
            case let (.subject(lhs, parent), .subject(rhs, _)):
                result.append(.subject(.init(subject: lhs.subject, events: lhs.events + rhs.events), parent))
            default:
                result.append(last)
                result.append(item)
            }
        }
        return result
    }
}

struct TodayHomeFeedRun: Identifiable {
    let id: String
    let actorID: String
    let actorName: String
    var items: [TodayHomeFeedItem]

    var hiddenEventCount: Int {
        items.dropFirst(2).reduce(0) { $0 + $1.eventCount }
    }

    static func consecutive(_ items: [TodayHomeFeedItem]) -> [Self] {
        var runs: [Self] = []
        for item in items {
            if let lastIndex = runs.indices.last, runs[lastIndex].actorID == item.actorID {
                runs[lastIndex].items.append(item)
            } else {
                runs.append(Self(id: item.id, actorID: item.actorID,
                                 actorName: item.actorName, items: [item]))
            }
        }
        return runs
    }
}

enum TodayHomeFeedOrder {
    static func sorted(_ items: [TodayHomeFeedItem], trending: Bool,
                       timeSort: TodayFeedTimeSort, now: Date = Date(),
                       dateForItem: (TodayHomeFeedItem) -> Date = { $0.occurredAt }) -> [TodayHomeFeedItem] {
        let entries = items.map { (item: $0, id: $0.id, date: dateForItem($0)) }
        guard trending else {
            return entries.sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.id < rhs.id }
                return timeSort == .newest ? lhs.date > rhs.date : lhs.date < rhs.date
            }.map(\.item)
        }
        let recent = entries.filter { 0...7 * 86_400 ~= now.timeIntervalSince($0.date) }
        let tickerCounts = Dictionary(grouping: recent.compactMap { entry -> (String, String)? in
            let item = entry.item
            return item.ticker.map { ($0, item.actorID) }
        }, by: { $0.0 })
        let actorCounts = tickerCounts.mapValues { Set($0.map { $0.1 }).count }
        let eventCounts = tickerCounts.mapValues { $0.count }
        func score(_ item: TodayHomeFeedItem, date: Date) -> Double {
            let age = max(0, now.timeIntervalSince(date)) / 86_400
            let freshness = 2.0 / (1.0 + age / 2.0)
            guard let ticker = item.ticker, age <= 7 else { return freshness }
            return freshness + Double(actorCounts[ticker, default: 0]) * 2
                + Double(min(eventCounts[ticker, default: 0], 8)) * 0.25
        }
        let ranked = entries.map { (entry: $0, score: score($0.item, date: $0.date)) }
        return ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.date != rhs.entry.date { return lhs.entry.date > rhs.entry.date }
            return lhs.entry.id < rhs.entry.id
        }.map { $0.entry.item }
    }
}

struct TodayInvestorActivityTimelineView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    let investorID: String
    @State private var investor: TodayInvestorActivity?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let investor {
                    TodayInvestorActivityHeader(investor: investor)
                    ForEach(investor.activities) { activity in
                        Divider().overlay(BSmartColor.line)
                        TodayInvestorActivityEntry(activity: activity, isTimeline: true)
                    }
                } else {
                    Label("No matching updates in the last 30 days".bSmartLocalized, systemImage: "text.bubble")
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle(investor?.name ?? "Smart updates".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("smart-updates.timeline")
        .refreshable { await model.refreshLiveIntelligence() }
        .onAppear(perform: rebuild)
        .onChange(of: model.smartAccountUpdates) { rebuild() }
        .onChange(of: model.smartMoneyMovements) { rebuild() }
        .onChange(of: scenePhase) { if scenePhase == .active { rebuild() } }
    }

    private func rebuild() {
        investor = TodayInvestorActivity.groups(accountUpdates: model.smartAccountUpdates,
            moneyMovements: BSmartProductVisibility.onchainSmartMoney ? model.smartMoneyMovements : [])
            .first { $0.id == investorID }
    }
}
