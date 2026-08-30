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

    var latestAt: Date {
        updates.map(\.publishedAt).max() ?? .distantPast
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

    var localizedHeadline: String {
        if bullishCount > 0, bearishCount > 0 {
            if BSmartLocalization.isSimplifiedChinese {
                return "\(ticker) 核心判断分化：\(bullishCount) 位看多，\(bearishCount) 位看空"
            }
            return "The \(ticker) thesis is split: \(bullishCount) bullish, \(bearishCount) bearish"
        }

        let direction = dominantDirection.label.bSmartLocalized
        let reason = concisePackageText(localizedText(for: representativeUpdate), limit: 46)
        if BSmartLocalization.isSimplifiedChinese {
            return "\(accountCount) 位 Smart Account \(direction) \(ticker)：\(reason)"
        }
        return "\(accountCount) Smart Accounts are \(direction.lowercased()) on \(ticker): \(reason)"
    }

    var localizedSummary: String {
        let reason = concisePackageText(localizedText(for: representativeUpdate), limit: 104)
        if BSmartLocalization.isSimplifiedChinese {
            return "汇总最近 \(updates.count) 条高分观点。共同关注点是：\(reason)"
        }
        return "A synthesis of \(updates.count) recent high-ranked views. The shared focus: \(reason)"
    }

    var localizedCommonThread: String {
        let reason = concisePackageText(localizedText(for: representativeUpdate), limit: 150)
        if BSmartLocalization.isSimplifiedChinese {
            return "多数观点围绕同一核心判断展开：\(reason)"
        }
        return "Most views build around the same central thesis: \(reason)"
    }

    var localizedDifference: String {
        let directions = Set(updates.map(\.direction))
        if directions.count > 1 {
            if BSmartLocalization.isSimplifiedChinese {
                return "方向尚未形成一致判断：\(bullishCount) 条看多、\(bearishCount) 条看空、\(neutralCount) 条中性或混合。"
            }
            return "Direction remains contested: \(bullishCount) bullish, \(bearishCount) bearish and \(neutralCount) neutral or mixed."
        }

        let horizons = Array(Set(updates.map(\.horizon).filter(isSpecifiedPackageHorizon))).sorted()
        if horizons.count > 1 {
            if BSmartLocalization.isSimplifiedChinese {
                return "方向一致，但操作周期不同，覆盖 \(horizons.joined(separator: "、"))。"
            }
            return "Direction is aligned, but the stated horizons range across \(horizons.joined(separator: ", "))."
        }

        let targets = updates.compactMap(\.targetPrice)
        if targets.count > 1, let low = targets.min(), let high = targets.max(), low != high {
            let range = "\(packageCurrency(low))–\(packageCurrency(high))"
            if BSmartLocalization.isSimplifiedChinese {
                return "方向一致，但目标价与确认条件不同；已明确的目标区间为 \(range)。"
            }
            return "Direction is aligned, but target levels and confirmation conditions differ. Stated targets span \(range)."
        }

        if BSmartLocalization.isSimplifiedChinese {
            return "方向和周期较为一致，差异主要在入场位置、确认条件与失效条件。"
        }
        return "Direction and horizon are broadly aligned; differences center on entry, confirmation and invalidation levels."
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

struct TodayViewpointPackageRail: View {
    let packages: [TodayViewpointPackage]
    @Namespace private var consensusTransition
    @State private var visiblePackageID: String?

    private var selectedIndex: Int {
        guard let visiblePackageID,
              let index = packages.firstIndex(where: { $0.id == visiblePackageID })
        else { return 0 }
        return index
    }

    var body: some View {
        VStack(spacing: BSmartSpacing.medium) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: BSmartSpacing.medium) {
                    ForEach(Array(packages.enumerated()), id: \.element.id) { index, package in
                        NavigationLink {
                            TodayViewpointPackageDetailView(package: package, style: index % 2)
                                .bSmartZoomNavigationTransition(
                                    sourceID: package.id,
                                    in: consensusTransition
                                )
                        } label: {
                            TodayViewpointPackageCard(package: package, style: index % 2)
                                .bSmartMatchedTransitionSource(
                                    id: package.id,
                                    in: consensusTransition
                                )
                        }
                        .id(package.id)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.viewpoint-package.\(package.ticker.lowercased())")
                    }
                }
                .scrollTargetLayout()
                .padding(.trailing, BSmartSpacing.large)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $visiblePackageID)

            TodayCarouselProgress(count: packages.count, selectedIndex: selectedIndex)
        }
        .onAppear {
            if visiblePackageID == nil { visiblePackageID = packages.first?.id }
        }
        .onChange(of: packages.map(\.id)) { _, ids in
            if visiblePackageID.map({ ids.contains($0) }) != true {
                visiblePackageID = ids.first
            }
        }
    }
}

private struct TodayViewpointPackageCard: View {
    let package: TodayViewpointPackage
    let style: Int

    private var fill: Color {
        style == 0
            ? Color(red: 233 / 255, green: 238 / 255, blue: 235 / 255)
            : Color(red: 51 / 255, green: 47 / 255, blue: 82 / 255)
    }

    private var foreground: Color {
        style == 0 ? BSmartColor.pulseInk : .white
    }

    private var secondary: Color {
        style == 0 ? BSmartColor.pulseInk.opacity(0.62) : BSmartColor.secondaryText
    }

    private var bandFill: Color {
        style == 0 ? BSmartColor.pulseInk.opacity(0.055) : Color.black.opacity(0.16)
    }

    private var rankAccent: Color {
        style == 0
            ? Color(red: 0 / 255, green: 104 / 255, blue: 78 / 255)
            : BSmartColor.brand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityBand

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: BSmartSpacing.small) {
                    Text("SMART CONSENSUS".bSmartLocalized)
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.7)
                        .foregroundStyle(BSmartColor.brand)

                    Spacer(minLength: 4)

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(foreground.opacity(0.68))
                }

                Text(package.localizedHeadline)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                Text(package.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 6)

                HStack(spacing: BSmartSpacing.small) {
                    PackageStanceBar(package: package, foreground: foreground)
                    Text(package.latestAt.bSmartRelativeTimestamp)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
                .padding(.top, 12)
            }
            .padding(BSmartSpacing.large)
        }
        .frame(width: 344, height: 300, alignment: .topLeading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(foreground.opacity(0.16), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
    }

    private var identityBand: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                BSmartAssetMark(ticker: package.ticker, size: 34)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(package.ticker)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("%d views".bSmartLocalized(package.updates.count))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 98, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(package.leadingUpdates.enumerated()), id: \.element.id) { index, update in
                    TodayConsensusAccountChip(
                        update: update,
                        foreground: foreground,
                        accent: rankAccent
                    )
                    .accessibilityIdentifier("today.consensus-card.account.\(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
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

    var body: some View {
        VStack(spacing: 4) {
            BSmartAvatar(
                url: update.authorAvatarURL,
                name: update.authorName,
                size: 29,
                fallbackColor: update.direction.color
            )
            .overlay { Circle().stroke(accent, lineWidth: 1.5) }

            Text(packageRank(update))
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)
                .frame(minHeight: 14)
                .background(accent.opacity(0.1), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 3)
        .padding(.vertical, 6)
        .background(foreground.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(foreground.opacity(0.14), lineWidth: 0.6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("%@, %@".bSmartLocalized(update.authorName, packageRank(update)))
    }
}

private struct PackageStanceBar: View {
    let package: TodayViewpointPackage
    let foreground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("%d%% bullish".bSmartLocalized(bullishPercentage))
                Spacer()
                Text("%d neutral · %d bearish".bSmartLocalized(package.neutralCount, package.bearishCount))
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(foreground.opacity(0.62))

            GeometryReader { proxy in
                HStack(spacing: 1) {
                    segment(count: package.bullishCount, total: package.updates.count, color: BSmartColor.brand, width: proxy.size.width)
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

                    thesisSection

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
            Text("SMART CONSENSUS".bSmartLocalized)
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(BSmartColor.brand)

            Text(package.localizedHeadline)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(package.localizedSummary)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineSpacing(3)

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

    private var thesisSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Consensus breakdown",
                detail: nil
            )

            thesisBlock(
                label: "Shared thesis",
                text: package.localizedCommonThread,
                color: BSmartColor.brand
            )
            thesisBlock(
                label: "Where views differ",
                text: package.localizedDifference,
                color: BSmartColor.gold
            )
        }
        .padding(.horizontal, BSmartSpacing.large)
    }

    private func thesisBlock(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text(label.bSmartLocalized.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.7)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineSpacing(3)
        }
        .padding(BSmartSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 2)
        }
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

            VStack(alignment: .leading, spacing: 4) {
                Text(update.authorName)
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

private func localizedText(for update: SmartAccountUpdate) -> String {
    if BSmartLocalization.isSimplifiedChinese {
        return update.activityTitleZH?.packageNonBlank
            ?? update.translatedTextZH?.packageNonBlank
            ?? update.translatedText?.packageNonBlank
            ?? update.thesis
    }
    return update.activityTitleEN?.packageNonBlank
        ?? update.translatedTextEN?.packageNonBlank
        ?? update.activityTitle?.packageNonBlank
        ?? update.thesis
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

private func concisePackageText(_ text: String, limit: Int) -> String {
    let normalized = text
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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
    "Top \(max(1, Int(ceil(update.platformPercentile * 100))))%"
}

private func packageCurrency(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(value < 100 ? 2 : 0)))
}

private extension String {
    var packageNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
