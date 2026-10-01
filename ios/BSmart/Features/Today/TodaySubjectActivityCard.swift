import SwiftUI

struct TodaySubjectActivityCard: View {
    let activity: TodaySubjectActivity
    var showsTopDivider = true
    @State private var showsAllEvents = false

    private var visibleEvents: [TodaySubjectEvent] {
        showsAllEvents ? activity.events : Array(activity.events.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTopDivider {
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                    .padding(.bottom, 14)
            }

            TodaySubjectActivityHeader(activity: activity)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { entry in
                    TodaySubjectEventEntry(event: entry.element, subjectKind: activity.subject.kind)
                    if entry.offset == 1 && activity.events.count > 2 {
                        TodayActivityOverflowButton(name: activity.name,
                                                    remainingCount: activity.events.count - 2,
                                                    isExpanded: showsAllEvents) {
                            showsAllEvents.toggle()
                        }
                        .padding(.vertical, 4)
                    }
                }
                TodayFeedPriceChange(event: activity.latest)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject-activity.actor.\(activity.id)-\(activity.latest.id)")
    }
}

private struct TodaySubjectActivityHeader: View {
    let activity: TodaySubjectActivity

    private var research: TodaySubjectResearch? { activity.researchMetric }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            BSmartDetailNavigationLink(id: "subject-profile-\(activity.id)") {
                TodaySubjectProfileView(subjectID: activity.id, initialActivity: activity)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    BSmartAvatar(url: activity.subject.avatarURL, name: activity.name, size: 44,
                                 bundledAssetName: activity.subject.bundledAvatarAssetName,
                                 isOrganization: activity.subject.kind == .institution,
                                 cornerRadius: 10)
                        .padding(.top, 2)
                        .overlay(alignment: .bottomTrailing) {
                            SmartPlatformMark(platform: activity.subject.kind.platform, size: 17)
                                .padding(2)
                                .background(BSmartColor.ink, in: RoundedRectangle(cornerRadius: 4))
                                .offset(x: 5, y: 5)
                        }
                        .frame(width: 51, height: 52, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(activity.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BSmartColor.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("Top %d%%".bSmartLocalized(activity.previewRank))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(BSmartColor.brand.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.bSmartPlain)
            .accessibilityIdentifier("subject-activity.profile.\(activity.id)")
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                metricColumn("Win rate", width: 68) {
                    if let research, research.directionalWins + research.directionalLosses > 0 {
                        TodayWinLossBadges(wins: research.directionalWins,
                                           losses: research.directionalLosses,
                                           identifierPrefix: "subject-activity", actorID: activity.id,
                                           describesTrades: false)
                    } else {
                        Text("—").foregroundStyle(BSmartColor.secondaryText)
                    }
                }
                metricColumn("Follow return", width: 68) {
                    Text(research?.meanOpenReturn.map {
                        $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
                    } ?? "—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle((research?.meanOpenReturn ?? 0) >= 0 ? BSmartColor.bull : BSmartColor.bear)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            .padding(.leading, 9)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Performance".bSmartLocalized)
        }
    }

    private func metricColumn<Content: View>(_ title: String, width: CGFloat,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 5) {
            Text(title.bSmartLocalized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BSmartColor.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            content().frame(height: 24)
        }
        .frame(width: width)
    }

}

private struct TodaySubjectEventEntry: View {
    let event: TodaySubjectEvent
    let subjectKind: TodaySubjectKind
    var isTimeline = false

    var body: some View {
        BSmartDetailNavigationLink(id: "subject-event-\(event.id)") {
            TodaySubjectEventDetailView(event: event)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(TodaySubjectEventCopy.headline(for: event, subjectKind: subjectKind))
                    .foregroundStyle(BSmartColor.primaryText.opacity(0.9))
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(4)
                    .lineLimit(isTimeline ? 5 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(TodaySubjectEventCopy.context(for: event))
                    .font(.system(size: 11))
                    .foregroundStyle(BSmartColor.tertiaryText)
                    .lineLimit(1)
            }
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.top, isTimeline ? 14 : 8)
            .padding(.bottom, isTimeline ? 14 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityIdentifier("subject-activity.event.\(event.id)")
    }

}

enum TodaySubjectEventCopy {
    static func headline(for event: TodaySubjectEvent, subjectKind: TodaySubjectKind) -> String {
        let asset = event.displayAsset.trimmingCharacters(in: .whitespacesAndNewlines)
        switch event.type {
        case .trade:
            let action = (event.isBuy ? "Buy" : "Sell").bSmartLocalized
            let headline = "%@ %@".bSmartLocalized(action, asset)
            guard let amount = event.amountRange?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !amount.isEmpty else { return headline }
            return "%@ · %@".bSmartLocalized(headline,
                subjectKind == .politician ? compactAmountRange(amount) : amount)
        case .opinion:
            let direction = event.directionTitle.bSmartLocalized
            let summary = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "%@ %@: %@".bSmartLocalized(direction, asset, summary)
        case .holding:
            let option = switch event.summary?.uppercased() {
            case "PUT OPTION": "Put option".bSmartLocalized
            case "CALL OPTION": "Call option".bSmartLocalized
            default: ""
            }
            let position = option.isEmpty ? asset : "%@ %@".bSmartLocalized(asset, option)
            let headline = switch event.action {
            case "new": "New holding: %@".bSmartLocalized(position)
            case "increased": "Holding increased: %@".bSmartLocalized(position)
            case "reduced": "Holding reduced: %@".bSmartLocalized(position)
            case "no_longer_reported": "No longer reported: %@".bSmartLocalized(position)
            default: "Holding: %@".bSmartLocalized(position)
            }
            return headline
        }
    }

    static func compactAmountRange(_ text: String) -> String {
        let pattern = #"^\s*\$?([\d,]+)\s*[-–]\s*\$?([\d,]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let lowRange = Range(match.range(at: 1), in: text),
              let highRange = Range(match.range(at: 2), in: text),
              let low = Double(text[lowRange].replacingOccurrences(of: ",", with: "")),
              let high = Double(text[highRange].replacingOccurrences(of: ",", with: "")),
              low.isFinite, high.isFinite, low >= 0, high >= low else { return text }
        return "$\(compactAmount(low))-$\(compactAmount(high))"
    }

    private static func compactAmount(_ value: Double) -> String {
        let scale: Double = value >= 1_000_000 ? 1_000_000 : value >= 1_000 ? 1_000 : 1
        let suffix = scale == 1_000_000 ? "M" : scale == 1_000 ? "K" : ""
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = scale == 1 ? 0 : 1
        formatter.roundingMode = .down
        return (formatter.string(from: NSNumber(value: value / scale)) ?? String(Int(value / scale))) + suffix
    }

    static func context(for event: TodaySubjectEvent) -> String {
        let occurred = date(event.occurredAt)
        let displayed = date(event.displayedAt)
        switch event.type {
        case .trade:
            return "Traded %@ · published %@".bSmartLocalized(occurred, displayed)
        case .holding:
            return "As of %@ · published %@".bSmartLocalized(occurred, displayed)
        case .opinion:
            return event.displayedAt.bSmartRelativeTimestamp
        }
    }

    private static func date(_ value: Date) -> String {
        var style = Date.FormatStyle.dateTime.month().day().locale(BSmartLocalization.formattingLocale)
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return value.formatted(style)
    }
}

struct TodaySubjectProfileView: View {
    @EnvironmentObject private var model: AppModel
    let subjectID: String
    let initialActivity: TodaySubjectActivity
    @State private var collapsed = false
    @State private var selectedType: EventFilter = .all
    @State private var visibleCount = 12
    @State private var historicalActivity: TodaySubjectActivity?

    private var activity: TodaySubjectActivity {
        historicalActivity ?? TodaySubjectActivity.history(for: subjectID, in: model.subjectActivitySnapshot) ?? initialActivity
    }

    private var filteredEvents: [TodaySubjectEvent] {
        activity.events.filter { selectedType.matches($0) }
    }

    private var coveredTickers: [String] {
        var seen = Set<String>()
        return activity.events.compactMap { $0.ticker ?? $0.underlyingTicker }
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        InvestorDetailScaffold(title: activity.name, collapsed: $collapsed) { width in
            InvestorPortraitHeader(name: activity.name, role: activity.subject.kind.title,
                                   imageURL: activity.subject.avatarURL,
                                   bundledAssetName: activity.subject.bundledAvatarAssetName,
                                   isOrganization: activity.subject.kind == .institution,
                                   portraitIdentifier: "subject.profile.portrait",
                                   width: width) { next in
                if next != collapsed { collapsed = next }
            }
        } sections: {
            VStack(alignment: .leading, spacing: 28) {
                identity
                performance
                if !coveredTickers.isEmpty { assets }
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                history
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                about
            }
        } dock: {
            followDock
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject.profile.detail.\(subjectID)")
        .task(id: subjectID) {
            historicalActivity = await model.subjectHistory(id: subjectID)
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            SmartPlatformMark(platform: activity.subject.kind.platform, size: 26)
            Text(activity.subject.kind.title.bSmartLocalized)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Text("Top %d%%".bSmartLocalized(activity.previewRank))
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.brand)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(BSmartColor.brand.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject.profile.identity")
    }

    private var performance: some View {
        let research = activity.researchMetric
        return VStack(alignment: .leading, spacing: 14) {
            Text("Performance".bSmartLocalized).font(.title3.weight(.bold))
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Win rate".bSmartLocalized)
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                    if let research, research.directionalWins + research.directionalLosses > 0 {
                        TodayWinLossBadges(wins: research.directionalWins,
                                           losses: research.directionalLosses,
                                           identifierPrefix: "subject-profile", actorID: activity.id,
                                           prominent: true, describesTrades: false)
                    } else {
                        Text("—").font(.title3.weight(.bold))
                            .foregroundStyle(BSmartColor.primaryText)
                    }
                }
                metric("Follow return", value: research?.meanOpenReturn.map {
                    $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
                } ?? "—", color: (research?.meanOpenReturn ?? 0) >= 0 ? BSmartColor.bull : BSmartColor.bear)
            }
            if let research {
                Text("Research estimate · not actual trading return".bSmartLocalized)
                    .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                Text("\(research.pricedPositions) / \(research.candidatePositions) "
                     + "priced open positions".bSmartLocalized + " · " + research.latestMarketDate)
                    .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject.profile.performance")
    }

    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color)
        }
    }

    private var assets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Covered assets".bSmartLocalized).font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(coveredTickers.prefix(12), id: \.self) { ticker in
                        BSmartDetailNavigationLink(id: "subject-profile-asset-\(ticker)") {
                            TickerDestinationView(symbol: ticker)
                        } label: {
                            HStack(spacing: 6) {
                                BSmartAssetMark(ticker: ticker, size: 23)
                                Text(ticker).font(.subheadline.weight(.semibold))
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.bSmartPlain)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject.profile.assets")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity".bSmartLocalized).font(.title3.weight(.bold))
                    .accessibilityIdentifier("subject.profile.activity")
                Spacer()
                Text(activity.events.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BSmartColor.secondaryText)
            }
            HStack(spacing: 16) {
                ForEach(EventFilter.allCases) { option in
                    Button {
                        selectedType = option
                        visibleCount = 12
                    } label: {
                        Text(option.title.bSmartLocalized)
                            .font(.subheadline.weight(selectedType == option ? .semibold : .regular))
                            .foregroundStyle(selectedType == option ? BSmartColor.primaryText : BSmartColor.secondaryText)
                            .frame(minHeight: 40)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(selectedType == option ? BSmartColor.brand : .clear)
                                    .frame(height: 2)
                            }
                    }
                    .buttonStyle(.bSmartPlain)
                    .accessibilityIdentifier("subject.profile.filter.\(option.rawValue)")
                }
            }
            if filteredEvents.isEmpty {
                Text("No matching updates".bSmartLocalized)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(filteredEvents.prefix(visibleCount))) { event in
                    Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                    VStack(alignment: .leading, spacing: 0) {
                        TodaySubjectEventEntry(event: event, subjectKind: activity.subject.kind, isTimeline: true)
                        TodayFeedPriceChange(event: event)
                            .padding(.bottom, 16)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("subject.profile.event-card.\(event.id)")
                }
                if filteredEvents.count > visibleCount {
                    Button { visibleCount += 12 } label: {
                        Label("Show more".bSmartLocalized, systemImage: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BSmartColor.brand)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bSmartPlain)
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About".bSmartLocalized).font(.title3.weight(.bold))
            Text((activity.subject.kind == .politician
                  ? "Public trade disclosures show transaction and publication dates."
                  : "SEC 13F filings show reported holdings by quarter, not execution prices or trade timestamps.").bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if subjectID == "celebrity:bill-ackman",
               let licenseURL = URL(string: "https://creativecommons.org/licenses/by/2.0/") {
                Link("Photo: Senate Democrats (CC BY 2.0, cropped)".bSmartLocalized,
                     destination: licenseURL)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
    }

    private var followDock: some View {
        Button { model.toggleSubjectFollow(subjectID) } label: {
            let following = model.isFollowingSubject(subjectID)
            Label((following ? "Tracking" : "Track").bSmartLocalized,
                  systemImage: following ? "checkmark" : "plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(following ? BSmartColor.primaryText : BSmartColor.onAccent)
                .background(following ? BSmartColor.elevated : BSmartColor.brand,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityIdentifier("subject.profile.follow")
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
        .background(BSmartColor.ink)
        .overlay(alignment: .top) { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }
    }

    private enum EventFilter: String, CaseIterable, Identifiable {
        case all, opinion, trade, holding
        var id: Self { self }
        var title: String {
            switch self {
            case .all: "All"
            case .opinion: "Opinions"
            case .trade: "Trades"
            case .holding: "Holdings"
            }
        }
        func matches(_ event: TodaySubjectEvent) -> Bool {
            self == .all || rawValue == event.type.rawValue
        }
    }
}

struct TodaySubjectEventDetailView: View {
    let event: TodaySubjectEvent

    @ViewBuilder
    var body: some View {
        if let ticker = event.syncTicker {
            detailContent.bSmartTradeDock(symbol: ticker,
                                         opinionSource: event.syncSource)
        } else {
            detailContent
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    if let ticker = event.ticker ?? event.underlyingTicker {
                        BSmartAssetMark(ticker: ticker, size: 46)
                    } else {
                        Image(systemName: "building.2")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(BSmartColor.sky)
                            .frame(width: 46, height: 46)
                            .background(BSmartColor.surface)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.displayAsset)
                            .font(.title2.weight(.bold))
                        if event.underlyingTicker != nil, let assetName = event.assetName {
                            Text(assetName)
                                .font(.caption)
                                .foregroundStyle(BSmartColor.secondaryText)
                        }
                        Text((event.type == .holding ? event.holdingTitle
                            : event.type == .trade ? (event.isBuy ? "Buy" : "Sell")
                            : event.directionTitle).bSmartLocalized)
                            .foregroundStyle(event.type == .holding || event.direction == "neutral"
                                ? BSmartColor.sky : event.isBuy || event.direction == "bullish"
                                ? BSmartColor.bull : event.direction == "neutral"
                                    ? BSmartColor.sky : BSmartColor.bear)
                        SubjectOptionInterpretationView(event: event)
                    }
                }
                if event.isSample { detailRow("Sample", value: "Sample data".bSmartLocalized) }
                if let summary = event.summary, !summary.isEmpty {
                    detailRow("Opinion", value: summary)
                }
                detailRow(event.type == .holding ? "Report period" : "Action date",
                          value: event.occurredAt.formatted(date: .abbreviated, time: .omitted))
                detailRow(event.type == .holding ? "Filed on" : "Published date",
                          value: event.displayedAt.formatted(date: .abbreviated, time: .omitted))
                if let amount = event.amountRange, !amount.isEmpty {
                    detailRow("Amount range", value: TodaySubjectEventCopy.compactAmountRange(amount))
                }
                if let description = event.assetDescription, !description.isEmpty {
                    detailRow("Asset", value: description)
                }
                if let sourceNote = event.sourceNote, !sourceNote.isEmpty {
                    detailRow("Source", value: sourceNote)
                }
                if let sourceURL = event.sourceURL {
                    Link(destination: sourceURL) {
                        HStack {
                            Text("Open source".bSmartLocalized)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .foregroundStyle(BSmartColor.brand)
                        .frame(minHeight: 48)
                    }
                }
                if let ticker = event.ticker {
                    BSmartDetailNavigationLink(id: "subject-event-asset-\(event.id)") {
                        TickerDestinationView(symbol: ticker)
                    } label: {
                        HStack {
                            Text("View asset".bSmartLocalized)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .foregroundStyle(BSmartColor.brand)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.bSmartPlain)
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle(event.displayAsset)
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("subject-activity.detail.\(event.id)")
    }

    private func detailRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.bSmartLocalized)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(BSmartColor.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
