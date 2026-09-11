import Charts
import SwiftUI

struct TodayHomeSectionHeading: View {
    let title: String
    let symbol: String
    let accent: Color
    let identifier: String
    @ScaledMetric(relativeTo: .headline) private var titleSize = 20.0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(title.bSmartLocalized)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(BSmartColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct TodayEditorialSectionTitle: View {
    let title: String
    var showsDisclosure = false
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 15.0

    var body: some View {
        HStack(spacing: BSmartSpacing.small) {
            Text(title.bSmartLocalized)
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(BSmartColor.primaryText)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
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

struct TodayEvidenceTimeline: View {
    let ticker: String
    let evidence: SmartAccountPriceEvidence
    let accountUpdates: [SmartAccountUpdate]
    var moneyMovements: [SmartMoneyMovement] = []

    @State private var period = 30
    @State private var chartStyle: TodayPriceChartStyle = .candles
    @State private var selectedMarker: TodayPriceEventMarker?
    @State private var focusedMarkerID: String?
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

            chart.frame(height: 306)

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
                Button("7D") { selectPeriod(7) }
                Button("1M") { selectPeriod(30) }
                Button("3M") { selectPeriod(90) }
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
                        selectChartStyle(style)
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
        BSmartPriceChart(
            series: BSmartPriceChartSeries(BSmartChartCandle.daily(candles)),
            showsCandles: chartStyle == .candles,
            identifier: "today.evidence.chart"
        ) { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let plot = geometry[anchor]
                    ZStack(alignment: .topLeading) {
                        ForEach(markers) { marker in
                            if let date = BSmartChartCandle.day(marker.day),
                               let x = proxy.position(forX: date), let y = proxy.position(forY: marker.price),
                               (0...plot.width).contains(x), (0...plot.height).contains(y) {
                                Button { openMarker(marker) } label: {
                                    markerBubble(marker)
                                        .bSmartMatchedTransitionSource(id: marker.id, in: transition)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("today.detail-price-marker.\(marker.id)")
                                .position(x: plot.minX + x,
                                          y: plot.minY + min(max(y - 28, 28), plot.height - 28))
                            }
                        }
                    }
                }
            }
        }
        .id("\(ticker)-\(period)")
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
        .animation(BSmartMotion.spring, value: focusedMarkerID)
    }

    private func selectPeriod(_ value: Int) {
        withAnimation(BSmartMotion.spring) { period = value }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func selectChartStyle(_ style: TodayPriceChartStyle) {
        withAnimation(BSmartMotion.spring) { chartStyle = style }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func openMarker(_ marker: TodayPriceEventMarker) {
        withAnimation(BSmartMotion.spring) { focusedMarkerID = marker.id }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            selectedMarker = marker
            focusedMarkerID = nil
        }
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
        candle.close >= candle.open ? BSmartColor.bull : BSmartColor.bear
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
                        text: target.formatted(.bSmartDollars.precision(.fractionLength(0))),
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
        .bSmartTradeDock(symbol: ticker)
    }

    private var ticker: String {
        switch marker.source {
        case let .account(update): update.ticker
        case let .money(movement): movement.ticker
        }
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
            .bSmartSubjectDestination(update)
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
            .bSmartSubjectDestination(movement)
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
                    Text(marker.price.formatted(.bSmartDollars.precision(.fractionLength(2))))
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
                    Text(marker.price.formatted(.bSmartDollars.precision(.fractionLength(2))))
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
        number = absolute.formatted(.bSmartDollars.precision(.fractionLength(0)))
    }
    return sign + number
}
