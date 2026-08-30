import Charts
import SwiftUI

struct TodayEditorialSectionTitle: View {
    let title: String
    var showsDisclosure = false

    var body: some View {
        HStack(spacing: BSmartSpacing.small) {
            Text(title.bSmartLocalized)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(BSmartColor.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}

struct TodayCarouselProgress: View {
    let count: Int
    let selectedIndex: Int

    private var visibleIndices: [Int] {
        guard count > 10 else { return Array(0..<count) }
        let start = min(max(selectedIndex - 2, 0), max(count - 5, 0))
        return Array(start..<min(start + 5, count))
    }

    var body: some View {
        if count > 1 {
            HStack(spacing: 7) {
                ForEach(visibleIndices, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? BSmartColor.primaryText : BSmartColor.line)
                        .frame(width: index == selectedIndex ? 7 : 5, height: index == selectedIndex ? 7 : 5)
                        .animation(BSmartMotion.quick, value: selectedIndex)
                }

                if count > 10 {
                    Text("%d / %d".bSmartLocalized(selectedIndex + 1, count))
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(BSmartColor.tertiaryText)
                        .padding(.leading, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card %d of %d".bSmartLocalized(selectedIndex + 1, count))
        }
    }
}

enum TodayInterludeItem: Identifiable {
    case accountProfile(SmartAccountProfile)
    case accountView(SmartAccountUpdate, SmartAccountProfile)
    case moneyProfile(SmartMoneySignal)
    case moneyPosition(SmartMoneySignal, SmartMoneyMovement?)

    var id: String {
        switch self {
        case let .accountProfile(profile): "account-profile-\(profile.id)"
        case let .accountView(update, _): "account-view-\(update.id.uuidString)"
        case let .moneyProfile(signal): "money-profile-\(signal.id)"
        case let .moneyPosition(signal, movement):
            "money-position-\(signal.id)-\(movement?.id.uuidString ?? "latest")"
        }
    }
}

struct TodayInterludeDeck: View {
    let items: [TodayInterludeItem]

    @State private var visibleItemID: String?

    private var selectedIndex: Int {
        guard let visibleItemID,
              let index = items.firstIndex(where: { $0.id == visibleItemID })
        else { return 0 }
        return index
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        BSmartDetailNavigationLink(id: "today-interlude-\(item.id)") {
                            destination(for: item)
                        } label: {
                            TodayInterludeCard(item: item)
                                .frame(height: 172)
                        }
                        .id(item.id)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.interlude.\(item.id)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleItemID)
            .frame(height: 172)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))

            VStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? BSmartColor.brand : BSmartColor.line)
                        .frame(width: index == selectedIndex ? 6 : 4, height: index == selectedIndex ? 6 : 4)
                }
            }
            .padding(.trailing, 7)
            .allowsHitTesting(false)
        }
        .onAppear {
            if visibleItemID == nil { visibleItemID = items.first?.id }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if visibleItemID.map({ ids.contains($0) }) != true {
                visibleItemID = ids.first
            }
        }
        .sensoryFeedback(.selection, trigger: visibleItemID)
        .accessibilityIdentifier("today.interlude-deck")
    }

    @ViewBuilder
    private func destination(for item: TodayInterludeItem) -> some View {
        switch item {
        case let .accountProfile(profile):
            SmartAccountTrustPreviewView(account: profile)
        case let .accountView(update, _):
            SmartAccountEvidenceDetailView(update: update)
        case let .moneyProfile(signal), let .moneyPosition(signal, _):
            SmartMoneyDetailView(signal: signal)
        }
    }
}

private struct TodayInterludeCard: View {
    let item: TodayInterludeItem

    private var accent: Color {
        switch item {
        case .accountProfile, .accountView: BSmartColor.brand
        case .moneyProfile, .moneyPosition: BSmartColor.sky
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: 6) {
                Image(systemName: typeSymbol)
                    .font(.caption2.weight(.black))
                Text(typeLabel.bSmartLocalized.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.7)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.black))
            }
            .foregroundStyle(accent)

            content
        }
        .padding(BSmartSpacing.large)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var typeLabel: String {
        switch item {
        case .accountProfile: "Smart Account profile"
        case .accountView: "Representative view"
        case .moneyProfile: "Smart Money profile"
        case .moneyPosition: "Position update"
        }
    }

    private var typeSymbol: String {
        switch item {
        case .accountProfile: "person.text.rectangle"
        case .accountView: "quote.bubble"
        case .moneyProfile: "wallet.pass"
        case .moneyPosition: "arrow.up.arrow.down.circle"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .accountProfile(profile): accountProfile(profile)
        case let .accountView(update, profile): accountView(update, profile)
        case let .moneyProfile(signal): moneyProfile(signal)
        case let .moneyPosition(signal, movement): moneyPosition(signal, movement)
        }
    }

    private func accountProfile(_ profile: SmartAccountProfile) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            BSmartAvatar(url: profile.avatarURL, name: profile.name, size: 54)
                .overlay { Circle().stroke(BSmartColor.brand, lineWidth: 1.5) }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                    BSmartTag(text: profileRank(profile), color: BSmartColor.brand)
                }

                Text([profile.specialty, profile.horizon, profile.resolvedStyle]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    metric("Followers", todayCompactCount(profile.followersCount ?? 0))
                    metric("Settled calls", profile.resolvedSettledCalls.formatted())
                    metric("Covered tickers", profile.resolvedCoveredTickers.formatted())
                }
            }
        }
    }

    private func accountView(_ update: SmartAccountUpdate, _ profile: SmartAccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartAvatar(
                    url: profile.avatarURL ?? update.authorAvatarURL,
                    name: profile.name,
                    size: 34,
                    fallbackColor: update.direction.color
                )
                Text(profile.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                BSmartTag(text: updateRank(update), color: BSmartColor.brand)
                Spacer()
                BSmartAssetMark(ticker: update.ticker, size: 24)
                Text(update.ticker.uppercased())
                    .font(.caption.weight(.black).monospaced())
            }

            Text(accountViewText(update))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(2)

            Text("%@ · %@ · %@".bSmartLocalized(
                update.direction.label,
                update.horizon.bSmartLocalized,
                update.publishedAt.bSmartRelativeTimestamp
            ))
            .font(.caption2.weight(.bold))
            .foregroundStyle(update.direction.color)
        }
    }

    private func moneyProfile(_ signal: SmartMoneySignal) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            BSmartSmartMoneyAvatar(identity: signal.publicIdentity, size: 54)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(signal.publicIdentity.displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                    BSmartTag(text: moneyRank(signal), color: BSmartColor.sky)
                }

                Text([signal.resolvedStyle, signal.resolvedTier, signal.resolvedSource]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    metric("Account value", todayCompactCurrency(signal.accountValue ?? 0))
                    metric("Net P&L", todaySignedCurrency(signal.netPnl ?? 0))
                    metric("Win rate", todayPercent(signal.winRate))
                }
            }
        }
    }

    private func moneyPosition(_ signal: SmartMoneySignal, _ movement: SmartMoneyMovement?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartSmartMoneyAvatar(identity: signal.publicIdentity, size: 34)
                Text(signal.publicIdentity.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                BSmartTag(text: moneyRank(signal), color: BSmartColor.sky)
                Spacer()
                BSmartAssetMark(ticker: movement?.ticker ?? signal.ticker, size: 24)
                Text((movement?.ticker ?? signal.ticker).uppercased())
                    .font(.caption.weight(.black).monospaced())
            }

            Text(positionHeadline(signal, movement))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(2)

            HStack(spacing: 7) {
                BSmartTag(
                    text: movement?.action.label ?? signal.direction,
                    color: movement?.direction.color ?? BSmartColor.sky
                )
                Text((movement?.observedAt ?? signal.changedAt).bSmartRelativeTimestamp)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.weight(.black).monospacedDigit())
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.bSmartLocalized)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileRank(_ profile: SmartAccountProfile) -> String {
        let raw = profile.resolvedPlatformPercentile
        let percentile = raw > 1 ? raw : raw * 100
        return "Top %d%%".bSmartLocalized(max(1, Int(ceil(percentile))))
    }

    private func updateRank(_ update: SmartAccountUpdate) -> String {
        let raw = update.platformPercentile
        let percentile = raw > 1 ? raw : raw * 100
        return "Top %d%%".bSmartLocalized(max(1, Int(ceil(percentile))))
    }

    private func moneyRank(_ signal: SmartMoneySignal) -> String {
        if let rank = signal.rank, rank > 0 { return "#\(rank)" }
        return "Score %@".bSmartLocalized(signal.score.formatted(.number.precision(.fractionLength(0))))
    }

    private func accountViewText(_ update: SmartAccountUpdate) -> String {
        if BSmartLocalization.isSimplifiedChinese,
           let translated = update.translatedTextZH,
           !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translated
        }
        return update.thesis.isEmpty ? (update.originalText ?? update.ticker) : update.thesis
    }

    private func positionHeadline(_ signal: SmartMoneySignal, _ movement: SmartMoneyMovement?) -> String {
        guard let movement else {
            return "%@ %@ · %@".bSmartLocalized(
                signal.direction,
                signal.ticker.uppercased(),
                todayCompactCurrency(signal.notionalValue)
            )
        }
        return "%@ %@ · %@".bSmartLocalized(
            movement.action.label,
            movement.ticker.uppercased(),
            todaySignedCurrency(movement.notionalChange)
        )
    }
}

private func todayCompactCurrency(_ value: Double) -> String {
    switch abs(value) {
    case 1_000_000...: return String(format: "$%.1fM", value / 1_000_000)
    case 1_000...: return String(format: "$%.0fK", value / 1_000)
    default: return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

private func todaySignedCurrency(_ value: Double) -> String {
    (value >= 0 ? "+" : "-") + todayCompactCurrency(abs(value))
}

private func todayCompactCount(_ value: Int) -> String {
    switch value {
    case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
    default: return value.formatted()
    }
}

private func todayPercent(_ value: Double?) -> String {
    guard let value else { return "--" }
    let normalized = value > 1 ? value / 100 : value
    return normalized.formatted(.percent.precision(.fractionLength(0)))
}

private enum TodayPriceChartStyle: String, CaseIterable, Identifiable {
    case candles
    case line

    var id: Self { self }

    var label: String {
        switch self {
        case .candles: "Candles".bSmartLocalized
        case .line: "Line".bSmartLocalized
        }
    }

    var symbol: String {
        switch self {
        case .candles: "chart.bar.xaxis"
        case .line: "chart.xyaxis.line"
        }
    }
}

private struct TodayPriceEventMarker: Identifiable, Hashable {
    enum Source: Hashable {
        case account(SmartAccountUpdate)
        case money(SmartMoneyMovement)
    }

    let source: Source
    let day: String
    let price: Double
    let rankLabel: String
    let priority: Double

    var id: String {
        switch source {
        case let .account(update): "account:\(update.id.uuidString)"
        case let .money(movement): "money:\(movement.id.uuidString)"
        }
    }

    var direction: SignalDirection {
        switch source {
        case let .account(update): update.direction
        case let .money(movement): movement.direction
        }
    }
}

private struct TodayPriceMarkerPolicy {
    let maximumCount: Int
    let avatarSize: CGFloat
    let minimumSeparation: CGFloat
}

struct TodayPortfolioNowModule: View {
    let positions: [PortfolioPosition]
    let selectedTicker: String?
    let accountUpdates: [SmartAccountUpdate]
    let moneyMovements: [SmartMoneyMovement]
    let onSelect: (PortfolioPosition) -> Void

    @State private var period = 30
    @State private var chartStyle: TodayPriceChartStyle = .line
    @State private var selectedMarker: TodayPriceEventMarker?
    @Namespace private var priceEvidenceTransition

    private let chartFill = BSmartColor.chartSurface
    private let chartGrid = BSmartColor.chartGrid

    private var position: PortfolioPosition? {
        guard let selectedTicker else { return positions.first }
        return positions.first { $0.ticker.caseInsensitiveCompare(selectedTicker) == .orderedSame }
            ?? positions.first
    }

    private var ticker: String {
        position?.ticker.uppercased() ?? selectedTicker?.uppercased() ?? "—"
    }

    private var evidence: SmartAccountPriceEvidence? {
        accountUpdates
            .compactMap(\.priceEvidence)
            .max { $0.candles.count < $1.candles.count }
    }

    private var candles: [PriceCandle] {
        Array((evidence?.candles ?? []).suffix(period))
    }

    private var displayedPrice: Double {
        if let currentPrice = position?.currentPrice, currentPrice > 0 {
            return currentPrice
        }
        return evidence?.candles.last?.close ?? 0
    }

    private var dayChangePercent: Double? {
        let source = evidence?.candles ?? []
        guard source.count >= 2 else { return nil }
        let previousClose = source[source.count - 2].close
        guard previousClose != 0 else { return nil }
        return (displayedPrice - previousClose) / previousClose
    }

    private var priceRange: ClosedRange<Double> {
        let values = candles.flatMap { [$0.low, $0.high] }
        guard let low = values.min(), let high = values.max(), low < high else { return 0...1 }
        let padding = (high - low) * 0.16
        return (low - padding)...(high + padding)
    }

    private var markerPolicy: TodayPriceMarkerPolicy {
        switch period {
        case 7:
            TodayPriceMarkerPolicy(maximumCount: 3, avatarSize: 40, minimumSeparation: 58)
        case 90:
            TodayPriceMarkerPolicy(maximumCount: 7, avatarSize: 28, minimumSeparation: 42)
        default:
            TodayPriceMarkerPolicy(maximumCount: 5, avatarSize: 34, minimumSeparation: 49)
        }
    }

    private var markers: [TodayPriceEventMarker] {
        let visibleDays = Set(candles.map(\.day))
        let accountCandidates = accountUpdates
            .compactMap { update -> TodayPriceEventMarker? in
                guard let priceEvidence = update.priceEvidence,
                      visibleDays.contains(priceEvidence.viewDay)
                else { return nil }
                let percentile = resolvedPercentile(update.platformPercentile)
                let normalizedScore = min(max(update.score / 100, 0), 1)
                return TodayPriceEventMarker(
                    source: .account(update),
                    day: priceEvidence.viewDay,
                    price: priceEvidence.viewPrice,
                    rankLabel: "Top \(max(1, Int(ceil(percentile * 100))))%",
                    priority: ((1 - percentile) * 0.82) + (normalizedScore * 0.18)
                )
            }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return markerDate(lhs) > markerDate(rhs)
            }

        let uniqueAccounts = uniqueAccountMarkers(accountCandidates)
        let rankedMoney = uniqueMoneyMovements(moneyMovements)
        let maximumNotional = rankedMoney.map { abs($0.notionalChange) }.max() ?? 1
        let moneyCandidates = rankedMoney.enumerated().compactMap { index, movement -> TodayPriceEventMarker? in
                guard let candle = nearestCandle(to: movement.observedAt),
                      visibleDays.contains(candle.day)
                else { return nil }
                let rankQuality = rankedMoney.count > 1
                    ? 1 - (Double(index) / Double(rankedMoney.count - 1))
                    : 1
                let notionalQuality = min(abs(movement.notionalChange) / max(maximumNotional, 1), 1)
                return TodayPriceEventMarker(
                    source: .money(movement),
                    day: candle.day,
                    price: movement.price ?? candle.close,
                    rankLabel: "#\(index + 1)",
                    priority: (rankQuality * 0.72) + (notionalQuality * 0.28)
                )
            }

        var balancedCandidates: [TodayPriceEventMarker] = []
        let sourceCount = max(uniqueAccounts.count, moneyCandidates.count)
        for index in 0..<sourceCount {
            if uniqueAccounts.indices.contains(index) { balancedCandidates.append(uniqueAccounts[index]) }
            if moneyCandidates.indices.contains(index) { balancedCandidates.append(moneyCandidates[index]) }
        }

        return spatiallySeparatedMarkers(
            balancedCandidates,
            limit: markerPolicy.maximumCount,
            minimumSeparation: markerPolicy.minimumSeparation
        )
    }

    private var xAxisDates: [Date] {
        let dates = candles.compactMap { todayPriceDayFormatter.date(from: $0.day) }
        guard let first = dates.first else { return [] }

        if period == 90 {
            let calendar = Calendar.current
            return dates.reduce(into: [Date]()) { result, date in
                guard let previous = result.last else {
                    result.append(date)
                    return
                }
                if calendar.component(.month, from: previous) != calendar.component(.month, from: date)
                    || calendar.component(.year, from: previous) != calendar.component(.year, from: date) {
                    result.append(date)
                }
            }
        }

        let desiredCount = min(4, dates.count)
        guard desiredCount > 1 else { return [first] }
        let firstIndex = dates.count > 8 ? 1 : 0
        let lastIndex = dates.count > 8 ? dates.count - 2 : dates.count - 1
        return (0..<desiredCount).reduce(into: [Date]()) { result, offset in
            let span = max(lastIndex - firstIndex, 0)
            let index = firstIndex + Int((Double(offset) * Double(span) / Double(desiredCount - 1)).rounded())
            let date = dates[index]
            if result.last != date { result.append(date) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            chartSection

            Rectangle()
                .fill(BSmartColor.line)
                .frame(height: 0.5)

            positionRail
        }
        .animation(BSmartMotion.quick, value: period)
        .animation(BSmartMotion.quick, value: chartStyle)
        .navigationDestination(item: $selectedMarker) { marker in
            TodayPriceEventDetail(marker: marker)
                .bSmartZoomNavigationTransition(
                    sourceID: marker.id,
                    in: priceEvidenceTransition
                )
        }
    }

    private var positionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: BSmartSpacing.small) {
                ForEach(positions) { item in
                    let isSelected = item.ticker.caseInsensitiveCompare(ticker) == .orderedSame
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 8) {
                            BSmartAssetMark(ticker: item.ticker, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.ticker.uppercased())
                                        .font(.caption.weight(.black))
                                    if item.resolvedKind == .watchlist {
                                        Image(systemName: "eye.fill")
                                            .font(.system(size: 8, weight: .black))
                                            .foregroundStyle(BSmartColor.gold)
                                            .accessibilityLabel("Watchlist".bSmartLocalized)
                                    }
                                }
                                Text(item.resolvedKind == .watchlist
                                    ? "Watchlist".bSmartLocalized
                                    : resolvedPrice(for: item).formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(item.resolvedKind == .watchlist
                                        ? BSmartColor.gold
                                        : (isSelected ? BSmartColor.brand : BSmartColor.tertiaryText))
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 48)
                        .background(isSelected ? BSmartColor.brand.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                .stroke(isSelected ? BSmartColor.brand : BSmartColor.line, lineWidth: isSelected ? 1 : 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.portfolio-snapshot.\(item.ticker.lowercased())")
                }
            }
            .padding(.vertical, BSmartSpacing.medium)
        }
    }

    private func resolvedPrice(for item: PortfolioPosition) -> Double {
        if item.currentPrice > 0 { return item.currentPrice }
        if item.ticker.caseInsensitiveCompare(ticker) == .orderedSame { return displayedPrice }
        return 0
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .center, spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: ticker, size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ticker)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(BSmartColor.primaryText)
                    if let companyName = position?.companyName, !companyName.isEmpty {
                        Text(companyName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BSmartColor.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(displayedPrice.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(BSmartColor.primaryText)

                    if let dayChangePercent {
                        Text("24H \(dayChangePercent.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(dayChangePercent >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    }
                }
            }
            .accessibilityIdentifier("today.portfolio-now")

            VStack(spacing: 0) {
                HStack(spacing: BSmartSpacing.medium) {
                    controls
                    Spacer(minLength: 0)
                    HStack(spacing: BSmartSpacing.medium) {
                        Label("Account", systemImage: "circle.fill")
                            .foregroundStyle(BSmartColor.brand)
                        Label("Money", systemImage: "circle.fill")
                            .foregroundStyle(BSmartColor.sky)
                    }
                    .font(.system(size: 8, weight: .bold))
                    .labelStyle(.titleAndIcon)
                }
                .padding(.horizontal, BSmartSpacing.large)
                .frame(height: 48)

                Rectangle()
                    .fill(BSmartColor.chartGrid)
                    .frame(height: 0.5)

                if candles.isEmpty {
                    ContentUnavailableView("No price evidence", systemImage: "chart.xyaxis.line")
                        .foregroundStyle(BSmartColor.chartPrimaryText)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    priceChart
                        .padding(.horizontal, BSmartSpacing.small)
                }

                HStack(spacing: BSmartSpacing.large) {
                    Label("Smart Account", systemImage: "person.crop.circle.fill")
                    Text(markers.filter { marker in
                        if case .account = marker.source { return true }
                        return false
                    }.count.formatted())
                        .monospacedDigit()
                    Label("Smart Money", systemImage: "wallet.pass.fill")
                    Text(markers.filter { marker in
                        if case .money = marker.source { return true }
                        return false
                    }.count.formatted())
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(BSmartColor.chartSecondaryText)
                .padding(.horizontal, BSmartSpacing.large)
                .frame(height: 42)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(BSmartColor.chartGrid)
                        .frame(height: 0.5)
                }
            }
            .background(chartFill)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(BSmartColor.brand.opacity(0.18))
                    .frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(BSmartColor.brand.opacity(0.18))
                    .frame(height: 0.5)
            }
            .padding(.horizontal, -BSmartSpacing.large)
        }
        .padding(.vertical, BSmartSpacing.small)
    }

    private var controls: some View {
        HStack(spacing: 5) {
            Menu {
                Button("7D") { period = 7 }
                Button("1M") { period = 30 }
                Button("3M") { period = 90 }
            } label: {
                Text(period == 7 ? "7D" : period == 90 ? "3M" : "1M")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BSmartColor.chartPrimaryText)
                    .frame(width: 36, height: 30)
                    .background(BSmartColor.chartControl)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .accessibilityIdentifier("today.detail-chart-period")
            .accessibilityIdentifier("today.chart-period")

            HStack(spacing: 2) {
                ForEach(TodayPriceChartStyle.allCases) { style in
                    Button {
                        chartStyle = style
                    } label: {
                        Image(systemName: style.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(chartStyle == style
                                ? BSmartColor.chartSelectedControlForeground
                                : BSmartColor.chartSecondaryText)
                            .frame(width: 30, height: 28)
                            .background(chartStyle == style ? BSmartColor.brand : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.label)
                    .accessibilityIdentifier("today.detail-chart-style.\(style.rawValue)")
                    .accessibilityAddTraits(chartStyle == style ? .isSelected : [])
                    .accessibilityIdentifier("today.chart-style.\(style.rawValue)")
                    .accessibilityAddTraits(chartStyle == style ? .isSelected : [])
                }
            }
            .padding(2)
            .background(BSmartColor.chartControl)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var priceChart: some View {
        ZStack {
            Chart {
                if chartStyle == .candles {
                    ForEach(candles) { candle in
                        RuleMark(
                            x: .value("Session", candleDate(candle)),
                            yStart: .value("Low", candle.low),
                            yEnd: .value("High", candle.high)
                        )
                        .foregroundStyle(candleColor(candle).opacity(0.74))
                        .lineStyle(StrokeStyle(lineWidth: 0.8))

                        RectangleMark(
                            x: .value("Session", candleDate(candle)),
                            yStart: .value("Open", candle.open),
                            yEnd: .value("Close", candle.close),
                            width: .fixed(3)
                        )
                        .foregroundStyle(candleColor(candle))
                    }
                } else {
                    ForEach(candles) { candle in
                        LineMark(
                            x: .value("Session", candleDate(candle)),
                            y: .value("Close", candle.close)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(BSmartColor.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartYScale(domain: priceRange)
            .chartXScale(range: .plotDimension(startPadding: 22, endPadding: 28))
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(BSmartColor.chartWatermark)
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BSmartColor.chartGrid)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(date))
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(BSmartColor.chartSecondaryText)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(chartGrid)
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(price.formatted(.number.precision(.fractionLength(0))))
                                .font(.system(size: 8, weight: .medium).monospacedDigit())
                                .foregroundStyle(BSmartColor.chartTertiaryText)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.background(BSmartColor.chartPlot)
            }

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(markers) { marker in
                        Button {
                            selectedMarker = marker
                        } label: {
                            markerBubble(marker)
                                .bSmartMatchedTransitionSource(
                                    id: marker.id,
                                    in: priceEvidenceTransition
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(markerAccessibilityLabel(marker))
                        .accessibilityIdentifier("today.price-marker.\(marker.id)")
                        .position(markerPosition(marker, in: geometry.size))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.price-chart")
    }

    private func markerPosition(_ marker: TodayPriceEventMarker, in size: CGSize) -> CGPoint {
        let leftInset: CGFloat = 6
        let rightInset: CGFloat = 34
        let topInset: CGFloat = 18
        let bottomInset: CGFloat = 32
        let plotWidth = max(1, size.width - leftInset - rightInset)
        let plotHeight = max(1, size.height - topInset - bottomInset)

        let dayFraction = markerTimeFraction(marker)
        let range = max(0.0001, priceRange.upperBound - priceRange.lowerBound)
        let priceFraction = CGFloat((marker.price - priceRange.lowerBound) / range)
        let clampedPriceFraction = min(max(priceFraction, 0), 1)

        let x = leftInset + (plotWidth * dayFraction)
        let baseY = topInset + (plotHeight * (1 - clampedPriceFraction))
        let bubbleHalfHeight = (markerPolicy.avatarSize + 20) / 2
        let y = min(
            max(baseY + markerVerticalOffset(marker), bubbleHalfHeight),
            size.height - bottomInset - bubbleHalfHeight
        )
        return CGPoint(x: x, y: y)
    }

    private func xAxisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate(period == 90 ? "MMM" : "Md")
        return formatter.string(from: date)
    }

    private func candleDate(_ candle: PriceCandle) -> Date {
        todayPriceDayFormatter.date(from: candle.day) ?? .distantPast
    }

    private func markerTimeFraction(_ marker: TodayPriceEventMarker) -> CGFloat {
        guard let first = candles.first.map(candleDate),
              let last = candles.last.map(candleDate),
              let markerDate = todayPriceDayFormatter.date(from: marker.day),
              last > first
        else { return 0.5 }
        let fraction = markerDate.timeIntervalSince(first) / last.timeIntervalSince(first)
        return CGFloat(min(max(fraction, 0), 1))
    }

    @ViewBuilder
    private func markerAvatar(_ marker: TodayPriceEventMarker, size: CGFloat) -> some View {
        switch marker.source {
        case let .account(update):
            BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: size)
        case let .money(movement):
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: size)
        }
    }

    private func markerBubble(_ marker: TodayPriceEventMarker) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                markerAvatar(marker, size: markerPolicy.avatarSize)
                    .overlay { Circle().stroke(marker.direction.color, lineWidth: 2) }

                Image(systemName: markerSourceSymbol(marker))
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(chartFill)
                    .frame(width: 13, height: 13)
                    .background(marker.direction.color, in: Circle())
                    .overlay { Circle().stroke(chartFill, lineWidth: 1.5) }
                    .offset(x: 2, y: 2)
            }

            Text(marker.rankLabel)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BSmartColor.chartPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
                .frame(height: 13)
                .background(chartFill.opacity(0.96), in: Capsule())
                .overlay { Capsule().stroke(marker.direction.color.opacity(0.9), lineWidth: 0.75) }
        }
        .shadow(color: BSmartColor.chartMarkerShadow, radius: 5, y: 3)
        .frame(
            width: max(44, markerPolicy.avatarSize + 12),
            height: markerPolicy.avatarSize + 17
        )
        .contentShape(Rectangle())
    }

    private func markerSourceSymbol(_ marker: TodayPriceEventMarker) -> String {
        switch marker.source {
        case .account: "person.fill"
        case .money: "wallet.pass.fill"
        }
    }

    private func markerVerticalOffset(_ marker: TodayPriceEventMarker) -> CGFloat {
        let distance = (markerPolicy.avatarSize * 0.62) + 8
        return marker.direction == .bearish ? distance : -distance
    }

    private func markerAccessibilityLabel(_ marker: TodayPriceEventMarker) -> String {
        switch marker.source {
        case let .account(update):
            return "\(update.authorName), \(marker.rankLabel), \(ticker), \(update.direction.label)"
        case let .money(movement):
            return "\(movement.publicIdentity.displayName), \(marker.rankLabel), \(ticker), Smart Money"
        }
    }

    private func resolvedPercentile(_ value: Double) -> Double {
        let normalized = value > 1 ? value / 100 : value
        return min(max(normalized, 0), 1)
    }

    private func markerDate(_ marker: TodayPriceEventMarker) -> Date {
        switch marker.source {
        case let .account(update): update.publishedAt
        case let .money(movement): movement.observedAt
        }
    }

    private func uniqueAccountMarkers(_ candidates: [TodayPriceEventMarker]) -> [TodayPriceEventMarker] {
        var seen = Set<String>()
        return candidates.filter { marker in
            guard case let .account(update) = marker.source else { return false }
            return seen.insert(update.authorId.lowercased()).inserted
        }
    }

    private func uniqueMoneyMovements(_ source: [SmartMoneyMovement]) -> [SmartMoneyMovement] {
        let ranked = source.sorted { lhs, rhs in
            if lhs.accountScore != rhs.accountScore { return lhs.accountScore > rhs.accountScore }
            if abs(lhs.notionalChange) != abs(rhs.notionalChange) {
                return abs(lhs.notionalChange) > abs(rhs.notionalChange)
            }
            return lhs.observedAt > rhs.observedAt
        }
        var seen = Set<String>()
        return ranked.filter { seen.insert($0.accountId.lowercased()).inserted }
    }

    private func spatiallySeparatedMarkers(
        _ candidates: [TodayPriceEventMarker],
        limit: Int,
        minimumSeparation: CGFloat
    ) -> [TodayPriceEventMarker] {
        var selected: [TodayPriceEventMarker] = []
        for candidate in candidates {
            let point = normalizedMarkerPoint(candidate)
            let hasCollision = selected.contains { existing in
                let other = normalizedMarkerPoint(existing)
                return hypot(point.x - other.x, point.y - other.y) < minimumSeparation
            }
            guard !hasCollision else { continue }
            selected.append(candidate)
            if selected.count == limit { break }
        }
        return selected
    }

    private func normalizedMarkerPoint(_ marker: TodayPriceEventMarker) -> CGPoint {
        let chartWidth: CGFloat = 320
        let chartHeight: CGFloat = 250
        let x = markerTimeFraction(marker) * chartWidth
        let range = max(0.0001, priceRange.upperBound - priceRange.lowerBound)
        let fraction = min(max((marker.price - priceRange.lowerBound) / range, 0), 1)
        return CGPoint(x: x, y: CGFloat(1 - fraction) * chartHeight)
    }

    private func nearestCandle(to date: Date) -> PriceCandle? {
        candles.min { lhs, rhs in
            abs((todayPriceDayFormatter.date(from: lhs.day) ?? .distantPast).timeIntervalSince(date))
                < abs((todayPriceDayFormatter.date(from: rhs.day) ?? .distantPast).timeIntervalSince(date))
        }
    }

    private func candleColor(_ candle: PriceCandle) -> Color {
        candle.close >= candle.open ? BSmartColor.brand : BSmartColor.bear
    }
}

struct TodayEvidenceTimeline: View {
    let ticker: String
    let evidence: SmartAccountPriceEvidence
    let accountUpdates: [SmartAccountUpdate]
    var moneyMovements: [SmartMoneyMovement] = []

    @State private var period = 30
    @State private var chartStyle: TodayPriceChartStyle = .candles
    @State private var selectedMarker: TodayPriceEventMarker?
    @Namespace private var transition

    private let fill = BSmartColor.chartSurface
    private let grid = BSmartColor.chartGrid

    private var candles: [PriceCandle] {
        Array(evidence.candles.suffix(period))
    }

    private var priceRange: ClosedRange<Double> {
        let values = candles.flatMap { [$0.low, $0.high] }
        guard let low = values.min(), let high = values.max(), low < high else { return 0...1 }
        let padding = (high - low) * 0.16
        return (low - padding)...(high + padding)
    }

    private var markerPolicy: TodayPriceMarkerPolicy {
        switch period {
        case 7: TodayPriceMarkerPolicy(maximumCount: 3, avatarSize: 40, minimumSeparation: 58)
        case 90: TodayPriceMarkerPolicy(maximumCount: 7, avatarSize: 28, minimumSeparation: 42)
        default: TodayPriceMarkerPolicy(maximumCount: 5, avatarSize: 34, minimumSeparation: 49)
        }
    }

    private var markers: [TodayPriceEventMarker] {
        let visibleDays = Set(candles.map(\.day))
        let accountCandidates = accountUpdates.compactMap { update -> TodayPriceEventMarker? in
            guard let marker = accountMarker(update), visibleDays.contains(marker.day) else { return nil }
            let percentile = resolvedPercentile(update.platformPercentile)
            let score = min(max(update.score / 100, 0), 1)
            return TodayPriceEventMarker(
                source: .account(update),
                day: marker.day,
                price: marker.price,
                rankLabel: "Top \(max(1, Int(ceil(percentile * 100))))%",
                priority: ((1 - percentile) * 0.82) + (score * 0.18)
            )
        }
        .sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return markerDate(lhs) > markerDate(rhs)
        }

        let uniqueAccounts = uniqueAccountMarkers(accountCandidates)
        let rankedMoney = uniqueMoneyMovements(moneyMovements)
        let maximumNotional = rankedMoney.map { abs($0.notionalChange) }.max() ?? 1
        let moneyCandidates = rankedMoney.enumerated().compactMap { index, movement -> TodayPriceEventMarker? in
            guard let candle = nearestCandle(to: movement.observedAt), visibleDays.contains(candle.day) else { return nil }
            let rankQuality = rankedMoney.count > 1
                ? 1 - (Double(index) / Double(rankedMoney.count - 1))
                : 1
            let notionalQuality = min(abs(movement.notionalChange) / max(maximumNotional, 1), 1)
            return TodayPriceEventMarker(
                source: .money(movement),
                day: candle.day,
                price: movement.price ?? candle.close,
                rankLabel: "#\(index + 1)",
                priority: (rankQuality * 0.72) + (notionalQuality * 0.28)
            )
        }

        var balanced: [TodayPriceEventMarker] = []
        for index in 0..<max(uniqueAccounts.count, moneyCandidates.count) {
            if uniqueAccounts.indices.contains(index) { balanced.append(uniqueAccounts[index]) }
            if moneyCandidates.indices.contains(index) { balanced.append(moneyCandidates[index]) }
        }
        return spatiallySeparatedMarkers(
            balanced,
            limit: markerPolicy.maximumCount,
            minimumSeparation: markerPolicy.minimumSeparation
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack {
                Text(ticker.uppercased())
                    .font(.subheadline.weight(.black))
                Spacer()
                controls
            }

            ZStack {
                chart
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(markers) { marker in
                            Button {
                                selectedMarker = marker
                            } label: {
                                markerBubble(marker)
                                    .bSmartMatchedTransitionSource(id: marker.id, in: transition)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.detail-price-marker.\(marker.id)")
                            .position(markerPosition(marker, in: geometry.size))
                        }
                    }
                }
            }
            .frame(height: 260)

            HStack(spacing: BSmartSpacing.large) {
                Label("Smart Account", systemImage: "person.crop.circle.fill")
                if !moneyMovements.isEmpty {
                    Label("Smart Money", systemImage: "wallet.pass.fill")
                }
                Spacer()
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(BSmartColor.chartSecondaryText)
        }
        .padding(BSmartSpacing.medium)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
        .animation(BSmartMotion.quick, value: period)
        .animation(BSmartMotion.quick, value: chartStyle)
        .navigationDestination(item: $selectedMarker) { marker in
            TodayPriceEventDetail(marker: marker)
                .bSmartZoomNavigationTransition(sourceID: marker.id, in: transition)
        }
    }

    private var controls: some View {
        HStack(spacing: 5) {
            Menu {
                Button("7D") { period = 7 }
                Button("1M") { period = 30 }
                Button("3M") { period = 90 }
            } label: {
                Text(period == 7 ? "7D" : period == 90 ? "3M" : "1M")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BSmartColor.chartPrimaryText)
                    .frame(width: 36, height: 30)
                    .background(BSmartColor.chartControl)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 2) {
                ForEach(TodayPriceChartStyle.allCases) { style in
                    Button {
                        chartStyle = style
                    } label: {
                        Image(systemName: style.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(chartStyle == style
                                ? BSmartColor.chartSelectedControlForeground
                                : BSmartColor.chartSecondaryText)
                            .frame(width: 30, height: 28)
                            .background(chartStyle == style ? BSmartColor.brand : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.label)
                }
            }
            .padding(2)
            .background(BSmartColor.chartControl)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private var chart: some View {
        Chart {
            if chartStyle == .candles {
                ForEach(candles) { candle in
                    RuleMark(
                        x: .value("Session", candle.day),
                        yStart: .value("Low", candle.low),
                        yEnd: .value("High", candle.high)
                    )
                    .foregroundStyle(candleColor(candle).opacity(0.74))
                    .lineStyle(StrokeStyle(lineWidth: 0.8))

                    RectangleMark(
                        x: .value("Session", candle.day),
                        yStart: .value("Open", candle.open),
                        yEnd: .value("Close", candle.close),
                        width: .fixed(3)
                    )
                    .foregroundStyle(candleColor(candle))
                }
            } else {
                ForEach(candles) { candle in
                    LineMark(
                        x: .value("Session", candle.day),
                        y: .value("Close", candle.close)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(BSmartColor.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartYScale(domain: priceRange)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(grid)
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(price.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(size: 8, weight: .medium).monospacedDigit())
                            .foregroundStyle(BSmartColor.chartTertiaryText)
                    }
                }
            }
        }
        .chartPlotStyle { plot in plot.background(BSmartColor.chartPlot) }
    }

    private func accountMarker(_ update: SmartAccountUpdate) -> (day: String, price: Double)? {
        let requestedDay = update.priceEvidence?.viewDay
            ?? todayPriceDayFormatter.string(from: update.publishedAt)
        let day = candles.contains(where: { $0.day == requestedDay })
            ? requestedDay
            : candles.last(where: { $0.day <= requestedDay })?.day
        guard let resolvedDay = day,
              let candle = candles.first(where: { $0.day == resolvedDay })
        else { return nil }
        return (resolvedDay, update.priceEvidence?.viewPrice ?? candle.close)
    }

    private func markerPosition(_ marker: TodayPriceEventMarker, in size: CGSize) -> CGPoint {
        let leftInset: CGFloat = 6
        let rightInset: CGFloat = 34
        let verticalInset: CGFloat = 18
        let plotWidth = max(1, size.width - leftInset - rightInset)
        let plotHeight = max(1, size.height - (verticalInset * 2))
        let dayIndex = candles.firstIndex { $0.day == marker.day } ?? 0
        let dayFraction = candles.count > 1 ? CGFloat(dayIndex) / CGFloat(candles.count - 1) : 0.5
        let range = max(0.0001, priceRange.upperBound - priceRange.lowerBound)
        let priceFraction = CGFloat((marker.price - priceRange.lowerBound) / range)
        let x = leftInset + (plotWidth * dayFraction)
        let baseY = verticalInset + (plotHeight * (1 - min(max(priceFraction, 0), 1)))
        let offset = marker.direction == .bearish
            ? (markerPolicy.avatarSize * 0.62) + 8
            : -((markerPolicy.avatarSize * 0.62) + 8)
        let halfHeight = (markerPolicy.avatarSize + 20) / 2
        return CGPoint(
            x: x,
            y: min(max(baseY + offset, halfHeight), size.height - halfHeight)
        )
    }

    private func markerBubble(_ marker: TodayPriceEventMarker) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                markerAvatar(marker)
                    .overlay { Circle().stroke(marker.direction.color, lineWidth: 2) }
                Image(systemName: markerSourceSymbol(marker))
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(fill)
                    .frame(width: 13, height: 13)
                    .background(marker.direction.color, in: Circle())
                    .overlay { Circle().stroke(fill, lineWidth: 1.5) }
                    .offset(x: 2, y: 2)
            }
            Text(marker.rankLabel)
                .font(.system(size: 7, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(BSmartColor.chartPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 5)
                .frame(height: 13)
                .background(fill.opacity(0.96), in: Capsule())
                .overlay { Capsule().stroke(marker.direction.color.opacity(0.9), lineWidth: 0.75) }
        }
        .shadow(color: BSmartColor.chartMarkerShadow, radius: 5, y: 3)
        .frame(width: max(44, markerPolicy.avatarSize + 12), height: markerPolicy.avatarSize + 17)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func markerAvatar(_ marker: TodayPriceEventMarker) -> some View {
        switch marker.source {
        case let .account(update):
            BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: markerPolicy.avatarSize)
        case let .money(movement):
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: markerPolicy.avatarSize)
        }
    }

    private func markerSourceSymbol(_ marker: TodayPriceEventMarker) -> String {
        switch marker.source {
        case .account: "person.fill"
        case .money: "wallet.pass.fill"
        }
    }

    private func resolvedPercentile(_ value: Double) -> Double {
        let normalized = value > 1 ? value / 100 : value
        return min(max(normalized, 0), 1)
    }

    private func markerDate(_ marker: TodayPriceEventMarker) -> Date {
        switch marker.source {
        case let .account(update): update.publishedAt
        case let .money(movement): movement.observedAt
        }
    }

    private func uniqueAccountMarkers(_ source: [TodayPriceEventMarker]) -> [TodayPriceEventMarker] {
        var seen = Set<String>()
        return source.filter { marker in
            guard case let .account(update) = marker.source else { return false }
            return seen.insert(update.authorId.lowercased()).inserted
        }
    }

    private func uniqueMoneyMovements(_ source: [SmartMoneyMovement]) -> [SmartMoneyMovement] {
        let ranked = source.sorted { lhs, rhs in
            if lhs.accountScore != rhs.accountScore { return lhs.accountScore > rhs.accountScore }
            if abs(lhs.notionalChange) != abs(rhs.notionalChange) { return abs(lhs.notionalChange) > abs(rhs.notionalChange) }
            return lhs.observedAt > rhs.observedAt
        }
        var seen = Set<String>()
        return ranked.filter { seen.insert($0.accountId.lowercased()).inserted }
    }

    private func spatiallySeparatedMarkers(
        _ candidates: [TodayPriceEventMarker],
        limit: Int,
        minimumSeparation: CGFloat
    ) -> [TodayPriceEventMarker] {
        var selected: [TodayPriceEventMarker] = []
        for candidate in candidates {
            let point = normalizedMarkerPoint(candidate)
            let collides = selected.contains { existing in
                let other = normalizedMarkerPoint(existing)
                return hypot(point.x - other.x, point.y - other.y) < minimumSeparation
            }
            guard !collides else { continue }
            selected.append(candidate)
            if selected.count == limit { break }
        }
        return selected
    }

    private func normalizedMarkerPoint(_ marker: TodayPriceEventMarker) -> CGPoint {
        let dayIndex = candles.firstIndex { $0.day == marker.day } ?? 0
        let x = candles.count > 1 ? CGFloat(dayIndex) / CGFloat(candles.count - 1) * 320 : 160
        let range = max(0.0001, priceRange.upperBound - priceRange.lowerBound)
        let fraction = min(max((marker.price - priceRange.lowerBound) / range, 0), 1)
        return CGPoint(x: x, y: CGFloat(1 - fraction) * 250)
    }

    private func nearestCandle(to date: Date) -> PriceCandle? {
        candles.min { lhs, rhs in
            abs((todayPriceDayFormatter.date(from: lhs.day) ?? .distantPast).timeIntervalSince(date))
                < abs((todayPriceDayFormatter.date(from: rhs.day) ?? .distantPast).timeIntervalSince(date))
        }
    }

    private func candleColor(_ candle: PriceCandle) -> Color {
        candle.close >= candle.open ? BSmartColor.brand : BSmartColor.bear
    }
}

struct TodayInlineAccountOpinion: View {
    let update: SmartAccountUpdate
    @State private var showsOriginal = false

    private var translatedText: String? {
        if BSmartLocalization.isSimplifiedChinese {
            return nonBlank(update.translatedTextZH) ?? nonBlank(update.translatedText)
        }
        return nonBlank(update.translatedTextEN)
    }

    private var originalText: String {
        nonBlank(update.originalText) ?? update.thesis
    }

    private var displayedText: String {
        showsOriginal ? originalText : (translatedText ?? originalText)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartTag(text: update.direction.label, color: update.direction.color)
                if !update.horizon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    BSmartTag(text: update.horizon, color: BSmartColor.sky)
                }
                if let target = update.targetPrice {
                    BSmartTag(
                        text: target.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                        color: BSmartColor.gold
                    )
                }
                Spacer()
                if translatedText != nil {
                    Button(showsOriginal ? "View translation".bSmartLocalized : "View original".bSmartLocalized) {
                        withAnimation(BSmartMotion.quick) { showsOriginal.toggle() }
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
                    .buttonStyle(.plain)
                }
            }

            Text(displayedText)
                .font(.body)
                .foregroundStyle(BSmartColor.primaryText.opacity(0.9))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack {
                Text(update.publishedAt.bSmartDataTimestamp)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                Spacer()
                if let url = update.sourceURL ?? update.evidenceURL {
                    Link(destination: url) {
                        Label("Open source".bSmartLocalized, systemImage: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                    }
                }
            }
        }
        .padding(BSmartSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.recessed)
        .overlay(alignment: .leading) {
            Rectangle().fill(update.direction.color).frame(width: 2)
        }
        .accessibilityIdentifier("today.inline-account-opinion.\(update.id.uuidString)")
    }
}

private struct TodayPriceEventDetail: View {
    let marker: TodayPriceEventMarker

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                actorHeader
                Divider().overlay(BSmartColor.line)
                detail
            }
            .padding(BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Price evidence".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
    }

    @ViewBuilder
    private var actorHeader: some View {
        switch marker.source {
        case let .account(update):
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(update.authorName).font(.headline)
                    Text("Smart Account · %@ · %@".bSmartLocalized(update.platform, update.ticker))
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
        case let .money(movement):
            HStack(spacing: BSmartSpacing.medium) {
                BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(movement.publicIdentity.displayName).font(.headline)
                    Text("Smart Money · %@ · %@".bSmartLocalized(movement.market, movement.ticker))
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch marker.source {
        case let .account(update):
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack {
                    BSmartTag(text: update.direction.label, color: update.direction.color)
                    BSmartTag(text: update.horizon, color: BSmartColor.electric)
                    Spacer()
                    Text(marker.price.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .font(.subheadline.weight(.black).monospacedDigit())
                }
                Text(update.activityTitleZH ?? update.activityTitle ?? update.thesis)
                    .font(.title3.weight(.bold))
                Text(BSmartLocalization.isSimplifiedChinese
                    ? (update.translatedTextZH ?? update.translatedText ?? update.thesis)
                    : (update.translatedTextEN ?? update.translatedText ?? update.thesis))
                    .font(.body)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineSpacing(4)
                if let url = update.sourceURL ?? update.evidenceURL {
                    Link(destination: url) {
                        Label("Open source".bSmartLocalized, systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                    }
                }
            }
        case let .money(movement):
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                HStack {
                    BSmartTag(text: movement.action.label, color: movement.direction.color)
                    BSmartTag(text: movement.direction.label, color: movement.direction.color)
                    Spacer()
                    Text(marker.price.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .font(.subheadline.weight(.black).monospacedDigit())
                }
                Text("%@ changed %@ exposure by %@".bSmartLocalized(
                    movement.publicIdentity.displayName,
                    movement.ticker,
                    signedCompactCurrency(movement.notionalChange)
                ))
                .font(.title3.weight(.bold))
                Text("Observed public capital action on %@. This shows position behavior, not the account's stated reason.".bSmartLocalized(movement.market))
                    .font(.body)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineSpacing(4)
                if let url = movement.evidenceURL {
                    Link(destination: url) {
                        Label("Open evidence".bSmartLocalized, systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                    }
                }
            }
        }
    }
}

private let todayPriceDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

struct TodayAssetEditorialHero: View {
    let package: TodayViewpointPackage
    let position: PortfolioPosition?
    let moneyMovements: [SmartMoneyMovement]

    @State private var period = 30

    private var candles: [PriceCandle] {
        Array((package.chartEvidence?.candles ?? []).suffix(period))
    }

    private var priceRange: ClosedRange<Double> {
        let values = candles.flatMap { [$0.low, $0.high] }
        guard let low = values.min(), let high = values.max(), low < high else { return 0...1 }
        let padding = (high - low) * 0.12
        return (low - padding)...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack {
                Text("YOUR TICKER · TODAY".bSmartLocalized)
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.7)
                Spacer()
                Menu {
                    Button("7D") { period = 7 }
                    Button("1M") { period = 30 }
                    Button("3M") { period = 90 }
                } label: {
                    HStack(spacing: 4) {
                        Text(period == 7 ? "7D" : period == 90 ? "3M" : "1M")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .black))
                    }
                    .font(.caption2.weight(.black))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .overlay { RoundedRectangle(cornerRadius: 5).stroke(BSmartColor.pulseInk.opacity(0.24)) }
                }
            }

            Text("Where do %@ views land on price?".bSmartLocalized(package.ticker))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Text(package.ticker)
                    .font(.subheadline.weight(.black))
                if let position, position.currentPrice > 0 {
                    Text(position.currentPrice.formatted(.currency(code: "USD").precision(.fractionLength(2))))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .opacity(0.6)
                }
            }

            if candles.isEmpty {
                ContentUnavailableView("No price evidence", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Chart {
                    ForEach(candles) { candle in
                        RuleMark(
                            x: .value("Session", candle.day),
                            yStart: .value("Low", candle.low),
                            yEnd: .value("High", candle.high)
                        )
                        .foregroundStyle(candleInk(candle).opacity(0.72))
                        .lineStyle(StrokeStyle(lineWidth: 0.8))

                        RectangleMark(
                            x: .value("Session", candle.day),
                            yStart: .value("Open", candle.open),
                            yEnd: .value("Close", candle.close),
                            width: .fixed(3)
                        )
                        .foregroundStyle(candleInk(candle))
                    }

                    ForEach(package.updates.prefix(5)) { update in
                        if let marker = marker(for: update) {
                            RuleMark(x: .value("View", marker.day))
                                .foregroundStyle(update.direction == .bearish
                                    ? Color(red: 169 / 255, green: 39 / 255, blue: 59 / 255).opacity(0.5)
                                    : BSmartColor.pulseInk.opacity(0.34))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                            PointMark(
                                x: .value("View", marker.day),
                                y: .value("Price", marker.price)
                            )
                            .foregroundStyle(BSmartColor.pulseInk)
                            .symbolSize(82)
                            .annotation(position: .overlay) {
                                Text("A")
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(BSmartColor.pulseFill)
                            }
                        }
                    }
                }
                .chartYScale(domain: priceRange)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.background(BSmartColor.pulseInk.opacity(0.035))
                }
                .frame(height: 205)
            }

            HStack(spacing: 0) {
                heroMetric("Smart Account", "%d views".bSmartLocalized(package.updates.count))
                heroMetric("Smart Money", "%d actions".bSmartLocalized(moneyMovements.count))

                BSmartDetailNavigationLink(id: "editorial-hero-\(package.id)") {
                    TodayViewpointPackageDetailView(package: package, style: 0)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.black))
                        .frame(width: 32, height: 32)
                        .overlay { Circle().stroke(BSmartColor.pulseInk.opacity(0.28)) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.editorial-hero.open")
            }
            .padding(.top, BSmartSpacing.small)
            .overlay(alignment: .top) {
                Rectangle().fill(BSmartColor.pulseInk.opacity(0.16)).frame(height: 0.5)
            }
        }
        .foregroundStyle(BSmartColor.pulseInk)
        .padding(BSmartSpacing.large)
        .background(BSmartColor.pulseFill)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .animation(BSmartMotion.quick, value: period)
        .accessibilityIdentifier("today.asset-editorial-hero")
    }

    private func heroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.56)
            Text(value)
                .font(.caption.weight(.black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marker(for update: SmartAccountUpdate) -> (day: String, price: Double)? {
        guard let evidence = update.priceEvidence else { return nil }
        let visibleDays = Set(candles.map(\.day))
        guard visibleDays.contains(evidence.viewDay) else { return nil }
        return (evidence.viewDay, evidence.viewPrice)
    }

    private func candleInk(_ candle: PriceCandle) -> Color {
        candle.close >= candle.open
            ? BSmartColor.pulseInk
            : Color(red: 169 / 255, green: 39 / 255, blue: 59 / 255)
    }
}

struct TodayPortfolioSnapshotStrip: View {
    let positions: [PortfolioPosition]
    let accountUpdates: [SmartAccountUpdate]
    let moneyMovements: [SmartMoneyMovement]
    let selectedTicker: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: BSmartSpacing.small) {
                ForEach(positions) { position in
                    Button {
                        onSelect(position.ticker.uppercased())
                    } label: {
                        snapshot(position)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.portfolio-snapshot.\(position.ticker.lowercased())")
                }
            }
            .padding(.trailing, BSmartSpacing.large)
        }
    }

    private func snapshot(_ position: PortfolioPosition) -> some View {
        let ticker = position.ticker.uppercased()
        let tickerUpdates = accountUpdates.filter { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
        let tickerMoney = moneyMovements.filter { $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame }
        let closes = Array(tickerUpdates.compactMap(\.priceEvidence).first?.candles.suffix(20) ?? [])

        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                BSmartAssetMark(ticker: ticker, size: 28)
                Spacer()
                Text("%d updates".bSmartLocalized(tickerUpdates.count + tickerMoney.count))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Text(ticker)
                .font(.subheadline.weight(.black))
            Text(position.currentPrice > 0
                ? position.currentPrice.formatted(.currency(code: "USD").precision(.fractionLength(2)))
                : "Monitoring".bSmartLocalized)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(BSmartColor.brand)

            if closes.count > 1 {
                Chart(closes) { candle in
                    LineMark(
                        x: .value("Session", candle.day),
                        y: .value("Close", candle.close)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(BSmartColor.brand)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 28)
            } else {
                Spacer(minLength: 28)
            }

            Text("Views %d · Capital %d".bSmartLocalized(tickerUpdates.count, tickerMoney.count))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
        }
        .padding(BSmartSpacing.medium)
        .frame(width: 142, height: 132, alignment: .topLeading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(selectedTicker == ticker ? BSmartColor.brand : BSmartColor.line, lineWidth: selectedTicker == ticker ? 1 : 0.6)
        }
    }
}

struct TodaySmartMoneyFeature: View {
    let ticker: String
    let movements: [SmartMoneyMovement]
    let onOpen: () -> Void

    private var recent: [SmartMoneyMovement] {
        Array(movements.sorted { $0.observedAt > $1.observedAt }.prefix(3))
    }

    private var totalChange: Double {
        recent.reduce(0) { $0 + $1.notionalChange }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                HStack {
                    Text("SMART MONEY · %@".bSmartLocalized(ticker))
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.7)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.black))
                        .frame(width: 30, height: 30)
                        .overlay { Circle().stroke(Color(red: 7 / 255, green: 20 / 255, blue: 33 / 255).opacity(0.24)) }
                }

                Text(moneyHeadline)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: BSmartSpacing.small) {
                    ForEach(recent) { movement in
                        HStack(spacing: BSmartSpacing.small) {
                            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 28)
                            Text(movement.publicIdentity.displayName)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                            GeometryReader { proxy in
                                Rectangle()
                                    .fill(Color(red: 7 / 255, green: 20 / 255, blue: 33 / 255))
                                    .frame(width: proxy.size.width * moneyBarRatio(movement))
                            }
                            .frame(height: 8)
                            .background(Color.black.opacity(0.1))
                            Text(signedCompactCurrency(movement.notionalChange))
                                .font(.caption2.weight(.black).monospacedDigit())
                                .frame(width: 58, alignment: .trailing)
                        }
                    }
                }

                HStack(spacing: 0) {
                    moneyMetric("Net notional", signedCompactCurrency(totalChange))
                    moneyMetric("Active accounts", Set(recent.map(\.accountId)).count.formatted())
                    moneyMetric("Max leverage", maximumLeverage)
                }
                .padding(.top, BSmartSpacing.small)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.black.opacity(0.14)).frame(height: 0.5)
                }
            }
            .foregroundStyle(Color(red: 7 / 255, green: 20 / 255, blue: 33 / 255))
            .padding(BSmartSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSmartColor.sky)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.smart-money-feature")
    }

    private var moneyHeadline: String {
        guard let latest = recent.first else { return "No recent capital action".bSmartLocalized }
        let action = latest.action.label.bSmartLocalized
        return "%@ %@ %@; net change %@".bSmartLocalized(
            latest.publicIdentity.displayName,
            action,
            ticker,
            signedCompactCurrency(totalChange)
        )
    }

    private var maximumLeverage: String {
        guard let value = recent.compactMap(\.leverage).max() else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0))))×"
    }

    private func moneyMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.system(size: 8, weight: .semibold))
                .opacity(0.56)
            Text(value)
                .font(.caption.weight(.black).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moneyBarRatio(_ movement: SmartMoneyMovement) -> CGFloat {
        let maximum = recent.map { abs($0.notionalChange) }.max() ?? 1
        return max(0.08, min(1, abs(movement.notionalChange) / max(1, maximum)))
    }
}

private func signedCompactCurrency(_ value: Double) -> String {
    let sign = value > 0 ? "+" : value < 0 ? "−" : ""
    let absolute = abs(value)
    let number: String
    switch absolute {
    case 1_000_000...:
        number = "$\((absolute / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
    case 1_000...:
        number = "$\((absolute / 1_000).formatted(.number.precision(.fractionLength(1))))K"
    default:
        number = absolute.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    return sign + number
}
