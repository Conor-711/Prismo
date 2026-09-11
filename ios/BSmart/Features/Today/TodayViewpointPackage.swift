import SwiftUI

struct TodayViewpointPackage: Identifiable, Hashable {
    let ticker: String
    let companyName: String
    let updates: [SmartAccountUpdate]

    var id: String { ticker.uppercased() }

    var accountCount: Int {
        Set(updates.map { $0.authorId.lowercased() }).count
    }

    var rankedUpdates: [SmartAccountUpdate] {
        updates.sorted { lhs, rhs in
            if lhs.platformPercentile != rhs.platformPercentile {
                return lhs.platformPercentile < rhs.platformPercentile
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.publishedAt != rhs.publishedAt { return lhs.publishedAt > rhs.publishedAt }
            return lhs.authorId.localizedCaseInsensitiveCompare(rhs.authorId) == .orderedAscending
        }
    }

    var leadingUpdates: [SmartAccountUpdate] {
        Array(rankedUpdates.prefix(3))
    }

    var latestPreviewAuthors: [SmartAccountUpdate] {
        Array(updates.sorted {
            if $0.publishedAt != $1.publishedAt { return $0.publishedAt > $1.publishedAt }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(3))
    }

    var latestAt: Date {
        updates.map(\.publishedAt).max() ?? .distantPast
    }

    var previewUpdate: SmartAccountUpdate? {
        let highRanked = updates.filter {
            let percentile = $0.platformPercentile > 1 ? $0.platformPercentile / 100 : $0.platformPercentile
            return percentile.isFinite && percentile >= 0 && percentile <= 0.25
        }
        return highRanked.sorted {
            if $0.publishedAt != $1.publishedAt { return $0.publishedAt > $1.publishedAt }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id.uuidString < $1.id.uuidString
        }.first ?? rankedUpdates.first
    }

    var dominantDirection: SignalDirection {
        let counts = Dictionary(grouping: updates, by: \.direction).mapValues(\.count)
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return directionPriority(lhs.key) > directionPriority(rhs.key)
        }?.key ?? .mixed
    }

    var bullishCount: Int { updates.filter { $0.direction == .bullish }.count }
    var bearishCount: Int { updates.filter { $0.direction == .bearish }.count }
    var neutralCount: Int { updates.count - bullishCount - bearishCount }

    var headlineUpdates: [SmartAccountUpdate] {
        let ordered = updates.sorted {
            if $0.publishedAt != $1.publishedAt { return $0.publishedAt > $1.publishedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let first = ordered.first else { return [] }
        let other = ordered.dropFirst().first { $0.direction != first.direction }
            ?? ordered.dropFirst().first
        return [first] + (other.map { [$0] } ?? [])
    }

    var sourceHeadlines: [TodaySourceHeadline] {
        headlineUpdates.map(TodaySourceHeadline.account)
    }

    var localizedHeadline: String {
        ticker + " · " + sourceHeadlines.map(\.text).joined(separator: " / ")
    }

    var representativeUpdate: SmartAccountUpdate {
        updates.max { lhs, rhs in
            if lhs.priceEvidence != nil, rhs.priceEvidence == nil { return false }
            if lhs.priceEvidence == nil, rhs.priceEvidence != nil { return true }
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.publishedAt < rhs.publishedAt
        } ?? updates[0]
    }

    var chartEvidence: SmartAccountPriceEvidence? {
        updates
            .compactMap(\.priceEvidence)
            .max { $0.candles.count < $1.candles.count }
    }

    static func packages(
        from source: [SmartAccountUpdate],
        minimumAccounts: Int = 2,
        maximumPackages: Int = 4,
        maximumAccountsPerPackage: Int = 5
    ) -> [TodayViewpointPackage] {
        Dictionary(grouping: source, by: { $0.ticker.uppercased() })
            .compactMap { ticker, tickerUpdates -> TodayViewpointPackage? in
                let sorted = tickerUpdates.sorted {
                    if $0.publishedAt != $1.publishedAt { return $0.publishedAt > $1.publishedAt }
                    return $0.score > $1.score
                }
                var seenAuthors = Set<String>()
                let distinctAccounts = sorted.filter { update in
                    seenAuthors.insert(update.authorId.lowercased()).inserted
                }
                guard distinctAccounts.count >= minimumAccounts else { return nil }
                let selected = Array(distinctAccounts.prefix(maximumAccountsPerPackage))
                return TodayViewpointPackage(
                    ticker: ticker,
                    companyName: selected.first?.companyName ?? ticker,
                    updates: selected
                )
            }
            .sorted { lhs, rhs in
                if lhs.latestAt != rhs.latestAt { return lhs.latestAt > rhs.latestAt }
                return lhs.accountCount > rhs.accountCount
            }
            .prefix(maximumPackages)
            .map { $0 }
    }
}

struct TodayViewpointPage: Identifiable {
    let index: Int
    let packages: [TodayViewpointPackage]
    var id: String { packages[0].id }

    static func pages(from packages: [TodayViewpointPackage]) -> [Self] {
        stride(from: 0, to: packages.count, by: 2).map { start in
            Self(index: start / 2, packages: Array(packages[start..<min(start + 2, packages.count)]))
        }
    }
}

private enum TodayViewpointCardMetrics {
    static let stackedHeight = 232.0
    static let rowSpacing = 12.0
}

struct TodayViewpointPackageRail: View {
    let packages: [TodayViewpointPackage]
    @Namespace private var consensusTransition
    @State private var visiblePageID: String?
    @ScaledMetric(relativeTo: .body) private var cardHeight = TodayViewpointCardMetrics.stackedHeight

    private var pages: [TodayViewpointPage] { TodayViewpointPage.pages(from: packages) }
    private var pageHeight: CGFloat {
        cardHeight * CGFloat(min(packages.count, 2)) + (packages.count > 1 ? TodayViewpointCardMetrics.rowSpacing : 0)
    }

    private var selectedIndex: Int {
        guard let visiblePageID,
              let index = pages.firstIndex(where: { $0.id == visiblePageID })
        else { return 0 }
        return index
    }

    var body: some View {
        VStack(spacing: BSmartSpacing.medium) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(pages) { page in
                        VStack(spacing: TodayViewpointCardMetrics.rowSpacing) {
                            ForEach(Array(page.packages.enumerated()), id: \.element.id) { row, package in
                                NavigationLink {
                                    TodayViewpointPackageDetailView(package: package, style: row % 2)
                                        .bSmartZoomNavigationTransition(sourceID: package.id, in: consensusTransition)
                                } label: {
                                    TodayViewpointPackageCard(package: package, style: row % 2, width: nil, isStacked: true)
                                        .bSmartMatchedTransitionSource(id: package.id, in: consensusTransition)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("today.viewpoint-package.\(package.ticker.lowercased())")
                            }
                        }
                        .frame(height: pageHeight, alignment: .top)
                        .containerRelativeFrame(.horizontal) { width, _ in max(0, width - 20) }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("today.viewpoint-page.\(page.index)")
                        .id(page.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.trailing, 20)
            }
            .frame(height: pageHeight)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $visiblePageID)
            .accessibilityIdentifier("today.viewpoint-pages")

            TodayCarouselProgress(count: pages.count, selectedIndex: selectedIndex)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Trending Tickers".bSmartLocalized)
                .accessibilityValue("\(selectedIndex + 1)/\(pages.count)")
                .accessibilityIdentifier("today.viewpoint-page-progress")
        }
        .onAppear {
            if visiblePageID == nil { visiblePageID = pages.first?.id }
        }
        .onChange(of: pages.map(\.id)) { _, ids in
            if visiblePageID.map({ ids.contains($0) }) != true {
                visiblePageID = ids.first
            }
        }
    }
}

struct TodayViewpointPackageCard: View {
    let package: TodayViewpointPackage
    let style: Int
    var width: CGFloat? = 344
    var isStacked = false
    @ScaledMetric(relativeTo: .body) private var cardHeight = 264.0
    @ScaledMetric(relativeTo: .body) private var stackedHeight = TodayViewpointCardMetrics.stackedHeight
    @ScaledMetric(relativeTo: .body) private var summarySize = 18.0
    @ScaledMetric(relativeTo: .body) private var stackedSummarySize = 17.0

    private var fill: Color {
        style == 0
            ? BSmartColor.consensusSurface
            : BSmartColor.consensusAlternateSurface
    }

    private var foreground: Color {
        BSmartColor.pulseInk
    }

    private var bandFill: Color {
        BSmartColor.pulseInk.opacity(0.04)
    }

    private var rankAccent: Color {
        Color(red: 0 / 255, green: 104 / 255, blue: 78 / 255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityBand

            if let update = package.previewUpdate {
                VStack(alignment: .leading, spacing: isStacked ? 8 : 12) {
                    Text(TodaySourceHeadline.account(update).text)
                        .font(.system(size: isStacked ? stackedSummarySize : summarySize, weight: .semibold))
                        .foregroundStyle(foreground)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .accessibilityIdentifier("today.consensus-card.summary")

                    sourceFooter(update)
                }
                .padding(isStacked ? 14 : 16)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .topLeading)
        .frame(height: isStacked ? stackedHeight : cardHeight, alignment: .topLeading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(foreground.opacity(0.16), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
    }

    private func sourceFooter(_ update: SmartAccountUpdate) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 30,
                             fallbackColor: update.direction.color)
                SmartPlatformMark(platform: update.platform, size: 13)
                    .offset(x: 3, y: 3)
            }
            .accessibilityLabel(update.authorName)
            .accessibilityIdentifier("today.consensus-card.summary-author")

            VStack(alignment: .leading, spacing: 3) {
                Text(update.authorName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("today.consensus-card.author-name")
                Text(update.publishedAt.bSmartRelativeTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(foreground.opacity(0.6))
                    .lineLimit(1)
                    .accessibilityIdentifier("today.consensus-card.published-at")
            }

            Spacer(minLength: 0)

            Text(packageRank(update))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(rankAccent)
                .fixedSize()
        }
        .frame(height: 34)
        .bSmartSubjectDestination(update)
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(foreground.opacity(0.12)).frame(height: 0.5)
        }
    }

    private var identityBand: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                BSmartAssetMark(ticker: package.ticker, size: 34)
                    .bSmartTickerDestination(package.ticker)
                    .frame(width: 38, height: 38)

                Text(package.ticker)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 98, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                ForEach(Array(package.latestPreviewAuthors.enumerated()), id: \.element.id) { index, update in
                    TodayConsensusAccountChip(
                        update: update,
                        foreground: foreground,
                        accent: rankAccent,
                        compact: true
                    )
                    .accessibilityIdentifier("today.consensus-card.account.\(index)")
                }
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 13)
        .padding(.vertical, isStacked ? 8 : 11)
        .background(bandFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(foreground.opacity(0.14)).frame(height: 0.5)
        }
    }
}

private struct TodayConsensusAccountChip: View {
    let update: SmartAccountUpdate
    let foreground: Color
    let accent: Color
    var compact = false

    var body: some View {
        let layout = compact ? AnyLayout(VStackLayout(spacing: 5)) : AnyLayout(HStackLayout(spacing: 9))
        layout {
            ZStack(alignment: .bottomTrailing) {
                BSmartAvatar(
                    url: update.authorAvatarURL,
                    name: update.authorName,
                    size: compact ? 28 : 36,
                    fallbackColor: update.direction.color
                )
                .overlay { Circle().stroke(accent, lineWidth: 1.5) }

                SmartPlatformMark(platform: update.platform, size: compact ? 12 : 15)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).stroke(foreground.opacity(0.25), lineWidth: 0.5)
                    }
                    .offset(x: 3, y: 3)
            }

            Text(packageRank(update))
                .font(.system(size: compact ? 9 : 12, weight: .black, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: compact ? 49 : nil)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("%@, %@".bSmartLocalized(update.authorName, packageRank(update)))
        .bSmartSubjectDestination(update)
    }
}

private struct PackageStanceBar: View {
    let package: TodayViewpointPackage
    let foreground: Color
    var showsLabels = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsLabels {
                HStack {
                    Text("%d%% bullish".bSmartLocalized(bullishPercentage))
                    Spacer()
                    Text("%d neutral · %d bearish".bSmartLocalized(package.neutralCount, package.bearishCount))
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(foreground.opacity(0.62))
            }

            GeometryReader { proxy in
                HStack(spacing: 1) {
                    segment(count: package.bullishCount, total: package.updates.count, color: BSmartColor.bull, width: proxy.size.width)
                    segment(count: package.neutralCount, total: package.updates.count, color: BSmartColor.gold, width: proxy.size.width)
                    segment(count: package.bearishCount, total: package.updates.count, color: BSmartColor.bear, width: proxy.size.width)
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())
        }
    }

    private func segment(count: Int, total: Int, color: Color, width: CGFloat) -> some View {
        color.frame(width: total > 0 ? width * CGFloat(count) / CGFloat(total) : 0)
    }

    private var bullishPercentage: Int {
        guard !package.updates.isEmpty else { return 0 }
        return Int((Double(package.bullishCount) / Double(package.updates.count) * 100).rounded())
    }
}

struct TodayViewpointPackageDetailView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    let package: TodayViewpointPackage
    var style = 0
    @State private var expandedUpdateIDs = Set<UUID>()

    var body: some View {
        VStack(spacing: 0) {
            detailNavigationBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    hero

                    leadingAccountsSection

                    consensusPanel


                    if let evidence = package.chartEvidence, !evidence.candles.isEmpty {
                        BSmartSectionHeader(
                            title: "Views on the price timeline",
                            detail: nil
                        )
                        .padding(.horizontal, BSmartSpacing.large)
                        TodayEvidenceTimeline(
                            ticker: package.ticker,
                            evidence: evidence,
                            accountUpdates: package.rankedUpdates
                        )
                        .padding(.horizontal, BSmartSpacing.large)
                    }

                    accountSection
                }
                .padding(.bottom, BSmartSpacing.xxxLarge)
            }
            .background(BSmartColor.ink)
        }
        .background(BSmartColor.ink)
        .toolbar(.hidden, for: .navigationBar)
        .bSmartDetailPage()
        .bSmartPage()
        .bSmartTradeDock(symbol: package.ticker)
    }

    private var detailNavigationBar: some View {
        HStack(spacing: BSmartSpacing.medium) {
            Button(action: dismissDetail) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .frame(width: 42, height: 42)
                    .background(BSmartColor.elevated, in: Circle())
                    .overlay {
                        Circle().stroke(BSmartColor.line, lineWidth: 0.75)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back".bSmartLocalized)
            .accessibilityIdentifier("today.viewpoint-package.back")

            Spacer(minLength: 0)

            Text(package.ticker)
                .font(.headline.weight(.black))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.vertical, 7)
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BSmartColor.line)
                .frame(height: 0.5)
        }
    }

    private func dismissDetail() {
        router.restoreTabBarImmediately()
        DispatchQueue.main.async {
            dismiss()
        }
    }

    private var hero: some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: package.ticker, size: 48)
                .bSmartTickerDestination(package.ticker)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(package.ticker)
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(BSmartColor.primaryText)
                Text(package.companyName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text("%d accounts".bSmartLocalized(package.accountCount))
                Text("%d views".bSmartLocalized(package.updates.count))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(BSmartColor.secondaryText)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.top, BSmartSpacing.medium)
    }

    private var leadingAccountsSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Leading Smart Accounts", detail: nil)

            VStack(spacing: BSmartSpacing.small) {
                ForEach(Array(package.leadingUpdates.enumerated()), id: \.element.id) { index, update in
                    Button {
                        toggleOpinion(update.id)
                    } label: {
                        TodayConsensusLeadingAccountRow(
                            update: update,
                            isExpanded: expandedUpdateIDs.contains(update.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.consensus-leading-account.\(index)")

                    if expandedUpdateIDs.contains(update.id) {
                        TodayInlineAccountOpinion(update: update)
                            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private var consensusPanel: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            Text("TRENDING TICKERS".bSmartLocalized)
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(BSmartColor.brand)

            TodaySourceHeadlineList(label: "Collected views", headlines: package.sourceHeadlines)

            PackageStanceBar(package: package, foreground: BSmartColor.primaryText)
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BSmartColor.brand)
                .frame(width: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
        .padding(.horizontal, BSmartSpacing.large)
    }





    private var accountSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Account judgments",
                detail: nil
            )

            VStack(spacing: 0) {
                ForEach(Array(package.rankedUpdates.enumerated()), id: \.element.id) { index, update in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    Button {
                        toggleOpinion(update.id)
                    } label: {
                        TodayViewpointPackageAccountRow(
                            index: index + 1,
                            update: update,
                            isExpanded: expandedUpdateIDs.contains(update.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.viewpoint-package-account.\(index)")

                    if expandedUpdateIDs.contains(update.id) {
                        TodayInlineAccountOpinion(update: update)
                            .transition(.opacity.combined(with: .move(edge: .top)))
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

    private func toggleOpinion(_ id: UUID) {
        withAnimation(BSmartMotion.quick) {
            if expandedUpdateIDs.contains(id) {
                expandedUpdateIDs.remove(id)
            } else {
                expandedUpdateIDs.insert(id)
            }
        }
    }
}

private struct TodayConsensusLeadingAccountRow: View {
    let update: SmartAccountUpdate
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAvatar(
                url: update.authorAvatarURL,
                name: update.authorName,
                size: 40,
                fallbackColor: update.direction.color
            )
            .overlay { Circle().stroke(BSmartColor.brand.opacity(0.8), lineWidth: 1.5) }
            .bSmartSubjectDestination(update)

            VStack(alignment: .leading, spacing: 4) {
                Text(update.authorName)
                    .bSmartSubjectDestination(update)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(update.platform)
                    Text("·")
                    Text(update.direction.label.bSmartLocalized)
                    if isSpecifiedPackageHorizon(update.horizon) {
                        Text("·")
                        Text(update.horizon)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
            }

            Spacer(minLength: BSmartSpacing.small)

            VStack(alignment: .trailing, spacing: 3) {
                Text(packageRank(update))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BSmartColor.brand)
                Text("Smart rank".bSmartLocalized)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(BSmartSpacing.medium)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
        .contentShape(Rectangle())
    }
}

private struct TodayViewpointPackageAccountRow: View {
    let index: Int
    let update: SmartAccountUpdate
    let isExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            ZStack(alignment: .bottomTrailing) {
                BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 42)
                    .bSmartSubjectDestination(update)
                Text("\(index)")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(BSmartColor.pulseInk)
                    .frame(width: 16, height: 16)
                    .background(BSmartColor.pulseFill, in: Circle())
                    .overlay { Circle().stroke(BSmartColor.surface, lineWidth: 2) }
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(update.authorName)
                        .bSmartSubjectDestination(update)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                    Text("·")
                    Text(update.platform)
                    Spacer()
                    Text(packageRank(update))
                        .foregroundStyle(BSmartColor.brand)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.tertiaryText)

                Text(packageLocalizedText(update))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    BSmartTag(text: update.direction.label, color: update.direction.color)
                    if isSpecifiedPackageHorizon(update.horizon) {
                        BSmartTag(text: update.horizon, color: BSmartColor.sky)
                    }
                    if let target = update.targetPrice {
                        BSmartTag(text: packageCurrency(target), color: BSmartColor.gold)
                    }
                }
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .padding(.top, 4)
        }
        .padding(BSmartSpacing.medium)
        .contentShape(Rectangle())
    }
}



private func packageLocalizedText(_ update: SmartAccountUpdate) -> String {
    if BSmartLocalization.isSimplifiedChinese {
        return update.translatedTextZH?.packageNonBlank
            ?? update.translatedText?.packageNonBlank
            ?? update.thesis
    }
    return update.translatedTextEN?.packageNonBlank
        ?? update.originalText?.packageNonBlank
        ?? update.thesis
}



private func directionPriority(_ direction: SignalDirection) -> Int {
    switch direction {
    case .bullish: 0
    case .bearish: 1
    case .neutral: 2
    case .mixed: 3
    }
}

private func isSpecifiedPackageHorizon(_ horizon: String) -> Bool {
    let normalized = horizon.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !normalized.isEmpty && !["unknown", "unspecified", "n/a", "na", "none"].contains(normalized)
}

private func packageRank(_ update: SmartAccountUpdate) -> String {
    let percentile = update.platformPercentile > 1 ? update.platformPercentile / 100 : update.platformPercentile
    guard percentile.isFinite else { return "—" }
    return "Top \(min(100, max(1, Int(ceil(percentile * 100)))))%"
}

private func packageCurrency(_ value: Double) -> String {
    value.formatted(.bSmartDollars.precision(.fractionLength(value < 100 ? 2 : 0)))
}

private extension String {
    var packageNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
