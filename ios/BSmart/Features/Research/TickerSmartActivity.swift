import Charts
import SwiftUI

enum TickerSmartActivitySource: String, CaseIterable, Identifiable {
    case all
    case smartAccount
    case smartMoney

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "All sources".bSmartLocalized
        case .smartAccount: "Smart Account"
        case .smartMoney: "Smart Money"
        }
    }

    var symbol: String {
        switch self {
        case .all: "sparkles"
        case .smartAccount: "person.wave.2"
        case .smartMoney: "wallet.bifold"
        }
    }
}

enum TickerSmartActivityPayload: Hashable {
    case account(SmartAccountUpdate)
    case money(SmartMoneyMovement)
}

struct TickerSmartActivityItem: Identifiable, Hashable {
    let payload: TickerSmartActivityPayload

    var id: String {
        switch payload {
        case let .account(update): "account-\(update.id.uuidString)"
        case let .money(movement): "money-\(movement.id.uuidString)"
        }
    }

    var source: TickerSmartActivitySource {
        switch payload {
        case .account: .smartAccount
        case .money: .smartMoney
        }
    }

    var occurredAt: Date {
        switch payload {
        case let .account(update): update.publishedAt
        case let .money(movement): movement.observedAt
        }
    }

    var direction: SignalDirection {
        switch payload {
        case let .account(update): update.direction
        case let .money(movement): movement.direction
        }
    }

    var score: Double {
        switch payload {
        case let .account(update): update.score
        case let .money(movement): movement.accountScore
        }
    }

    var actorName: String {
        switch payload {
        case let .account(update): update.authorName
        case let .money(movement): movement.publicIdentity.displayName
        }
    }

    var title: String {
        switch payload {
        case let .account(update):
            let localizedTitle = BSmartLocalization.isSimplifiedChinese
                ? (update.activityTitleZH?.tickerActivityNonBlank ?? update.activityTitle?.tickerActivityNonBlank)
                : (update.activityTitleEN?.tickerActivityNonBlank ?? update.activityTitle?.tickerActivityNonBlank)
            if let localizedTitle { return localizedTitle }

            let direction = update.direction.label.bSmartLocalized
            if let targetPrice = update.targetPrice {
                return "%@ toward %@: %@".bSmartLocalized(
                    direction,
                    targetPrice.tickerActivityCurrency,
                    conciseTickerActivityText(update.thesis)
                )
            }
            return "%@: %@".bSmartLocalized(direction, conciseTickerActivityText(update.thesis))

        case let .money(movement):
            let side: String = switch movement.direction {
            case .bullish: "long position".bSmartLocalized
            case .bearish: "short position".bSmartLocalized
            case .neutral, .mixed: "position".bSmartLocalized
            }
            let amount = compactTickerActivityUSD(abs(movement.notionalChange))
            switch movement.action {
            case .opened: return "Opened %@, about %@".bSmartLocalized(side, amount)
            case .increased: return "Added to %@, about %@".bSmartLocalized(side, amount)
            case .reduced: return "Reduced %@, about %@".bSmartLocalized(side, amount)
            case .closed: return "Closed %@, about %@".bSmartLocalized(side, amount)
            case .flipped: return "Flipped to %@, about %@".bSmartLocalized(side, amount)
            }
        }
    }

    var detail: String {
        switch payload {
        case let .account(update):
            let translated = BSmartLocalization.isSimplifiedChinese
                ? (update.translatedTextZH?.tickerActivityNonBlank ?? update.translatedText?.tickerActivityNonBlank)
                : (update.translatedTextEN?.tickerActivityNonBlank ?? update.originalText?.tickerActivityNonBlank)
            return translated ?? update.thesis

        case let .money(movement):
            var parts = [movement.market]
            if let leverage = movement.leverage {
                parts.append("\(leverage.formatted(.number.precision(.fractionLength(1))))x")
            }
            if let price = movement.price {
                parts.append("At %@".bSmartLocalized(price.tickerActivityCurrency))
            }
            return parts.joined(separator: " · ")
        }
    }

    static func items(
        ticker: String,
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement]
    ) -> [TickerSmartActivityItem] {
        let normalizedTicker = ticker.uppercased()
        let accountItems = accountUpdates
            .filter { $0.ticker.uppercased() == normalizedTicker }
            .map { TickerSmartActivityItem(payload: .account($0)) }
        let moneyItems = moneyMovements
            .filter { $0.ticker.uppercased() == normalizedTicker }
            .map { TickerSmartActivityItem(payload: .money($0)) }

        return (accountItems + moneyItems).sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.score > rhs.score
        }
    }
}

struct TickerSmartActivitySnapshot: Hashable {
    let activities: [TickerSmartActivityItem]
    let priceModel: TickerPriceActivityModel

    init(
        ticker: TickerIntelligence,
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement]
    ) {
        let activities = TickerSmartActivityItem.items(
            ticker: ticker.ticker,
            accountUpdates: accountUpdates,
            moneyMovements: moneyMovements
        )
        self.activities = activities
        priceModel = TickerPriceActivityModel(
            currentPrice: ticker.currentPrice,
            dataAsOf: ticker.dataAsOf,
            accountUpdates: accountUpdates,
            moneyMovements: moneyMovements,
            activities: activities
        )
    }
}

enum TickerPriceRange: Int, CaseIterable, Identifiable {
    case oneMonth = 31
    case threeMonths = 93
    case sixMonths = 186
    case oneYear = 366

    var id: Self { self }

    var label: String {
        switch self {
        case .oneMonth: "1M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        }
    }
}

struct TickerPricePoint: Identifiable, Hashable {
    let date: Date
    let close: Double
    let high: Double
    let low: Double

    var id: Date { date }
}

struct TickerPriceActivityMarker: Identifiable, Hashable {
    let activity: TickerSmartActivityItem
    let plotDate: Date
    let price: Double

    var id: String { activity.id }
}

struct TickerPriceActivityModel: Hashable {
    let points: [TickerPricePoint]
    let markers: [TickerPriceActivityMarker]

    init(
        currentPrice: Double,
        dataAsOf: Date,
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement]
    ) {
        self.init(
            currentPrice: currentPrice,
            dataAsOf: dataAsOf,
            accountUpdates: accountUpdates,
            moneyMovements: moneyMovements,
            activities: TickerSmartActivityItem.items(
                ticker: accountUpdates.first?.ticker ?? moneyMovements.first?.ticker ?? "",
                accountUpdates: accountUpdates,
                moneyMovements: moneyMovements
            )
        )
    }

    init(
        currentPrice: Double,
        dataAsOf: Date,
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement],
        activities: [TickerSmartActivityItem]
    ) {
        let evidences = accountUpdates
            .compactMap(\.priceEvidence)
            .sorted { $0.latestDay < $1.latestDay }
        var pointByDay: [Date: TickerPricePoint] = [:]

        for evidence in evidences {
            for candle in evidence.candles {
                guard let day = tickerActivityDayFormatter.date(from: candle.day) else { continue }
                pointByDay[day] = TickerPricePoint(
                    date: day,
                    close: candle.close,
                    high: candle.high,
                    low: candle.low
                )
            }
        }

        let currentDay = Calendar.current.startOfDay(for: dataAsOf)
        if currentPrice > 0 {
            if let current = pointByDay[currentDay] {
                pointByDay[currentDay] = TickerPricePoint(
                    date: currentDay,
                    close: currentPrice,
                    high: max(current.high, currentPrice),
                    low: min(current.low, currentPrice)
                )
            } else {
                pointByDay[currentDay] = TickerPricePoint(
                    date: currentDay,
                    close: currentPrice,
                    high: currentPrice,
                    low: currentPrice
                )
            }
        }

        let resolvedPoints = pointByDay.values.sorted { $0.date < $1.date }
        points = resolvedPoints

        markers = activities.compactMap { activity in
            guard let resolved = Self.resolveMarker(activity, points: resolvedPoints, currentPrice: currentPrice) else {
                return nil
            }
            return TickerPriceActivityMarker(activity: activity, plotDate: resolved.date, price: resolved.price)
        }
    }

    func points(in range: TickerPriceRange) -> [TickerPricePoint] {
        guard let latest = points.last?.date,
              let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: latest)
        else { return points }
        let filtered = points.filter { $0.date >= cutoff }
        return filtered.count >= 2 ? filtered : points
    }

    func markers(
        in range: TickerPriceRange,
        source: TickerSmartActivitySource,
        maximum: Int = 14
    ) -> [TickerPriceActivityMarker] {
        let visiblePoints = points(in: range)
        guard let first = visiblePoints.first?.date, let last = visiblePoints.last?.date else { return [] }
        let candidates = markers.filter { marker in
            marker.plotDate >= first && marker.plotDate <= last
                && (source == .all || marker.activity.source == source)
        }

        let accounts = candidates
            .filter { $0.activity.source == .smartAccount }
            .sorted(by: Self.markerPriority)
        let money = candidates
            .filter { $0.activity.source == .smartMoney }
            .sorted(by: Self.markerPriority)

        let selected: [TickerPriceActivityMarker]
        switch source {
        case .smartAccount:
            selected = Array(accounts.prefix(maximum))
        case .smartMoney:
            selected = Array(money.prefix(maximum))
        case .all:
            let accountLimit = money.isEmpty ? maximum : max(1, Int((Double(maximum) * 0.7).rounded()))
            let moneyLimit = accounts.isEmpty ? maximum : max(1, maximum - accountLimit)
            selected = Array(accounts.prefix(accountLimit)) + Array(money.prefix(moneyLimit))
        }
        return selected.sorted { $0.plotDate < $1.plotDate }
    }

    private static func markerPriority(
        _ lhs: TickerPriceActivityMarker,
        _ rhs: TickerPriceActivityMarker
    ) -> Bool {
        switch (lhs.activity.payload, rhs.activity.payload) {
        case let (.account(left), .account(right)):
            if left.platformPercentile != right.platformPercentile {
                return left.platformPercentile < right.platformPercentile
            }
        default:
            break
        }
        if lhs.activity.score != rhs.activity.score { return lhs.activity.score > rhs.activity.score }
        return lhs.activity.occurredAt > rhs.activity.occurredAt
    }

    private static func resolveMarker(
        _ activity: TickerSmartActivityItem,
        points: [TickerPricePoint],
        currentPrice: Double
    ) -> (date: Date, price: Double)? {
        let requestedDate = Calendar.current.startOfDay(for: activity.occurredAt)
        let plotPoint = points.last(where: { $0.date <= requestedDate })
            ?? points.first(where: { $0.date >= requestedDate })

        switch activity.payload {
        case let .account(update):
            let evidenceDay = update.priceEvidence.flatMap { tickerActivityDayFormatter.date(from: $0.viewDay) }
            let evidencePoint = evidenceDay.flatMap { day in
                points.first(where: { $0.date == day })
                    ?? points.last(where: { $0.date <= day })
            }
            let resolvedPoint = evidencePoint ?? plotPoint
            guard let date = resolvedPoint?.date ?? evidenceDay else { return nil }
            return (date, update.priceEvidence?.viewPrice ?? resolvedPoint?.close ?? currentPrice)

        case let .money(movement):
            guard let date = plotPoint?.date else { return nil }
            return (date, movement.price ?? plotPoint?.close ?? currentPrice)
        }
    }
}

struct TickerPriceSmartActivityPanel: View {
    let ticker: TickerIntelligence
    let model: TickerPriceActivityModel

    @State private var range: TickerPriceRange = .threeMonths
    @State private var source: TickerSmartActivitySource = .all
    @State private var selectedDate: Date?
    @State private var selectedMarkerID: String?

    private var visiblePoints: [TickerPricePoint] { model.points(in: range) }

    private var visibleMarkers: [TickerPriceActivityMarker] {
        model.markers(in: range, source: source)
    }

    private var selectedMarker: TickerPriceActivityMarker? {
        visibleMarkers.first { $0.id == selectedMarkerID } ?? visibleMarkers.last
    }

    private var priceRange: ClosedRange<Double> {
        let values = visiblePoints.flatMap { [$0.low, $0.high] } + visibleMarkers.map(\.price)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let spread = max(high - low, max(high, 1) * 0.02)
        return (low - spread * 0.1)...(high + spread * 0.14)
    }

    private var periodReturn: Double? {
        guard let first = visiblePoints.first?.close, let last = visiblePoints.last?.close, first != 0 else { return nil }
        return (last / first) - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            header

            if visiblePoints.count > 1 {
                metrics
                chart
                legend
                if let selectedMarker {
                    Divider().overlay(BSmartColor.line)
                    selectedActivity(selectedMarker)
                }
            } else {
                ContentUnavailableView(
                    "Price history unavailable".bSmartLocalized,
                    systemImage: "chart.xyaxis.line",
                    description: Text("Smart Activity remains available below.".bSmartLocalized)
                )
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .bSmartSurface()
        .accessibilityIdentifier("ticker-intelligence.price-activity")
        .onAppear(perform: selectLatestMarker)
        .onChange(of: range) { _, _ in selectLatestMarker() }
        .onChange(of: source) { _, _ in selectLatestMarker() }
        .onChange(of: selectedDate) { _, date in
            guard let date,
                  let nearest = visibleMarkers.min(by: {
                      abs($0.plotDate.timeIntervalSince(date)) < abs($1.plotDate.timeIntervalSince(date))
                  })
            else { return }
            withAnimation(BSmartMotion.quick) { selectedMarkerID = nearest.id }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack {
                Label("Price & Smart Activity".bSmartLocalized, systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Menu {
                    Picker("Source".bSmartLocalized, selection: $source) {
                        ForEach(TickerSmartActivitySource.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                } label: {
                    Label(source.label, systemImage: source.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }
            }

            HStack(spacing: BSmartSpacing.xSmall) {
                ForEach(TickerPriceRange.allCases) { option in
                    Button {
                        range = option
                    } label: {
                        Text(option.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(range == option ? BSmartColor.pulseInk : BSmartColor.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(range == option ? BSmartColor.brand : BSmartColor.recessed)
                    }
                    .buttonStyle(.plain)
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                    .accessibilityAddTraits(range == option ? .isSelected : [])
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            chartMetric(
                "Latest".bSmartLocalized,
                value: (visiblePoints.last?.close ?? ticker.currentPrice).tickerActivityCurrency,
                color: BSmartColor.primaryText
            )
            Divider().frame(height: 30).overlay(BSmartColor.line)
            chartMetric(
                "Return".bSmartLocalized,
                value: periodReturn?.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())) ?? "—",
                color: (periodReturn ?? 0) >= 0 ? BSmartColor.brand : BSmartColor.bear
            )
            Divider().frame(height: 30).overlay(BSmartColor.line)
            chartMetric(
                "Activity".bSmartLocalized,
                value: visibleMarkers.count.formatted(),
                color: BSmartColor.primaryText
            )
        }
        .padding(.vertical, BSmartSpacing.small)
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
    }

    private func chartMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private var chart: some View {
        Chart {
            ForEach(visiblePoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", priceRange.lowerBound),
                    yEnd: .value("Close", point.close)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [BSmartColor.brand.opacity(0.22), BSmartColor.brand.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Close", point.close)
                )
                .foregroundStyle(BSmartColor.brand)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            ForEach(visibleMarkers) { marker in
                PointMark(
                    x: .value("Activity date", marker.plotDate),
                    y: .value("Activity price", marker.price)
                )
                .foregroundStyle(marker.activity.direction.color)
                .symbolSize(marker.id == selectedMarker?.id ? 380 : 280)
                .symbol {
                    TickerActivityBubble(
                        activity: marker.activity,
                        isSelected: marker.id == selectedMarker?.id
                    )
                }
            }

            if let selectedMarker {
                RuleMark(x: .value("Selected activity", selectedMarker.plotDate))
                    .foregroundStyle(selectedMarker.activity.direction.color.opacity(0.36))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: priceRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(BSmartColor.line.opacity(0.45))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(BSmartColor.line.opacity(0.5))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(price.tickerActivityCompactCurrency)
                            .font(.caption2.monospacedDigit())
                    }
                }
                .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .chartPlotStyle { plot in
            plot.background(BSmartColor.recessed.opacity(0.72))
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 248)
        .accessibilityLabel("%@ price chart with %d Smart Activity markers".bSmartLocalized(
            ticker.ticker,
            visibleMarkers.count
        ))
    }

    private var legend: some View {
        HStack(spacing: BSmartSpacing.medium) {
            Label("Smart Account", systemImage: "person.fill")
            Label("Smart Money", systemImage: "wallet.bifold.fill")
            Spacer()
            Text(range.label)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(BSmartColor.tertiaryText)
    }

    private func selectedActivity(_ marker: TickerPriceActivityMarker) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            TickerActivityAvatar(activity: marker.activity, size: 36)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: BSmartSpacing.small) {
                    Text(marker.activity.source.label)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(marker.activity.source == .smartAccount ? BSmartColor.brand : BSmartColor.sky)
                    Text(marker.activity.actorName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(marker.activity.occurredAt.bSmartRelativeTimestamp)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }

                Text(marker.activity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(3)

                HStack(spacing: BSmartSpacing.medium) {
                    Text("At %@".bSmartLocalized(marker.price.tickerActivityCurrency))
                    Text("Score %@".bSmartLocalized(
                        marker.activity.score.formatted(.number.precision(.fractionLength(0)))
                    ))
                    if case let .account(update) = marker.activity.payload,
                       let target = update.targetPrice {
                        Text("Target %@".bSmartLocalized(target.tickerActivityCurrency))
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .accessibilityIdentifier("ticker-intelligence.price-activity.selected")
    }

    private func selectLatestMarker() {
        selectedMarkerID = visibleMarkers.last?.id
        selectedDate = nil
    }
}

struct TickerSmartActivityFeed: View {
    let activities: [TickerSmartActivityItem]
    var title: String = "Smart Activity"
    var maximumItems: Int? = nil
    var showsFilter = true

    @State private var source: TickerSmartActivitySource = .all

    private var filteredActivities: [TickerSmartActivityItem] {
        let filtered = source == .all ? activities : activities.filter { $0.source == source }
        guard let maximumItems else { return filtered }
        return Array(filtered.prefix(maximumItems))
    }

    var body: some View {
        let displayedActivities = filteredActivities

        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack {
                Label(title.bSmartLocalized, systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                Spacer()
                Text("%d updates".bSmartLocalized(activities.count))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            if showsFilter {
                HStack(spacing: BSmartSpacing.xSmall) {
                    ForEach(TickerSmartActivitySource.allCases) { option in
                        Button {
                            source = option
                        } label: {
                            Label(option.label, systemImage: option.symbol)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(source == option ? BSmartColor.pulseInk : BSmartColor.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(source == option ? BSmartColor.brand : BSmartColor.recessed)
                        }
                        .buttonStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                        .accessibilityAddTraits(source == option ? .isSelected : [])
                    }
                }
            }

            if displayedActivities.isEmpty {
                ContentUnavailableView(
                    "No Smart Activity".bSmartLocalized,
                    systemImage: "bolt.horizontal.circle"
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(displayedActivities) { activity in
                        TickerSmartActivityRow(activity: activity)
                            .padding(.vertical, BSmartSpacing.small)
                        if activity.id != displayedActivities.last?.id {
                            Divider().overlay(BSmartColor.line)
                        }
                    }
                }
            }
        }
        .bSmartSurface()
        .accessibilityIdentifier("ticker-intelligence.smart-activity")
    }
}

private struct TickerSmartActivityRow: View {
    let activity: TickerSmartActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            TickerActivityAvatar(activity: activity, size: 38)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: BSmartSpacing.small) {
                    Label(activity.source.label, systemImage: activity.source.symbol)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(activity.source == .smartAccount ? BSmartColor.brand : BSmartColor.sky)
                    Text(activity.actorName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: BSmartSpacing.small)
                    Text(activity.occurredAt.bSmartRelativeTimestamp)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }

                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                metadata
            }
        }
        .accessibilityIdentifier("ticker-intelligence.activity.\(activity.id)")
    }

    @ViewBuilder
    private var metadata: some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartTag(text: activity.direction.label, color: activity.direction.color)
            Text("Score %@".bSmartLocalized(
                activity.score.formatted(.number.precision(.fractionLength(0)))
            ))
            switch activity.payload {
            case let .account(update):
                Text(update.platform)
                if !update.horizon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(update.horizon.bSmartLocalized)
                }
                if let target = update.targetPrice {
                    Text("Target %@".bSmartLocalized(target.tickerActivityCurrency))
                }
            case let .money(movement):
                Text(movement.action.label)
                Text(compactTickerActivityUSD(movement.notionalChange))
            }
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(BSmartColor.tertiaryText)
    }
}

private struct TickerActivityBubble: View {
    let activity: TickerSmartActivityItem
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(BSmartColor.elevated)
            TickerActivityAvatar(activity: activity, size: isSelected ? 28 : 24)
        }
        .frame(width: isSelected ? 30 : 26, height: isSelected ? 30 : 26)
        .overlay {
            Circle()
                .stroke(activity.direction.color, lineWidth: isSelected ? 3 : 2)
        }
        .shadow(color: BSmartColor.ink.opacity(0.8), radius: 0, x: 0, y: 0)
        .shadow(color: activity.direction.color.opacity(isSelected ? 0.45 : 0.2), radius: isSelected ? 6 : 2)
    }
}

private struct TickerActivityAvatar: View {
    let activity: TickerSmartActivityItem
    let size: CGFloat

    var body: some View {
        switch activity.payload {
        case let .account(update):
            BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: size)
        case let .money(movement):
            BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: size)
        }
    }
}

private func conciseTickerActivityText(_ text: String, limit: Int = 72) -> String {
    let normalized = text
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
}

private func compactTickerActivityUSD(_ value: Double) -> String {
    let sign = value < 0 ? "−" : ""
    switch abs(value) {
    case 1_000_000...:
        return String(format: "%@$%.1fM", sign, abs(value) / 1_000_000)
    case 1_000...:
        return String(format: "%@$%.1fK", sign, abs(value) / 1_000)
    default:
        return sign + abs(value).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

private extension Double {
    var tickerActivityCurrency: String {
        formatted(.currency(code: "USD").precision(.fractionLength(self < 100 ? 2 : 0)))
    }

    var tickerActivityCompactCurrency: String {
        switch abs(self) {
        case 1_000...: String(format: "$%.1fK", self / 1_000)
        default: tickerActivityCurrency
        }
    }
}

private extension String {
    var tickerActivityNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private let tickerActivityDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()
