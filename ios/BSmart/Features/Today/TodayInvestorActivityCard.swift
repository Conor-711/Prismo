import SwiftUI

struct TodayInvestorActivityCard: View {
    let investor: TodayInvestorActivity
    var showsTopDivider = true
    @State private var showsAllEvents = false

    private var visibleActivities: [TodayActivity] {
        showsAllEvents ? investor.activities : Array(investor.activities.prefix(2))
    }

    private var hasNativeTrade: Bool {
        investor.activities.contains { activity in
            if case let .account(account) = activity { return account.latest.nativeTrade != nil }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTopDivider {
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                    .padding(.bottom, 14)
            }
            TodayInvestorActivityHeader(investor: investor)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleActivities.enumerated()), id: \.element.id) { entry in
                    TodayInvestorActivityEntry(activity: entry.element)
                    if case let .account(account) = entry.element,
                       let trade = account.latest.nativeTrade {
                        if let base = trade.base {
                            NativeBaseOpinionQuote(base: base)
                                .padding(.bottom, 8)
                        }
                        NativeTradePositionPanel(ticker: account.latest.ticker, updateID: account.latest.id,
                                                 trade: trade)
                            .padding(.bottom, 8)
                    }
                    if entry.offset == 1 && investor.activities.count > 2 {
                        TodayActivityOverflowButton(name: investor.name,
                                                    remainingCount: investor.activities.count - 2,
                                                    isExpanded: showsAllEvents) {
                            showsAllEvents.toggle()
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !hasNativeTrade { TodayFeedPriceChange(activity: investor.latest) }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-updates.investor.\(investor.id)-\(investor.latest.id)")
    }
}

struct TodayWinLossBadges: View {
    let wins: Int
    let losses: Int
    let identifierPrefix: String
    let actorID: String
    var prominent = false
    var describesTrades = true

    var body: some View {
        HStack(spacing: prominent ? 6 : 3) {
            resultCount(wins, color: BSmartColor.bull)
                .accessibilityLabel((describesTrades ? "Winning trades: %d" : "Winning observations: %d")
                    .bSmartLocalized(wins))
                .accessibilityIdentifier("\(identifierPrefix).wins.\(actorID)")
            resultCount(losses, color: BSmartColor.bear)
                .accessibilityLabel((describesTrades ? "Losing trades: %d" : "Losing observations: %d")
                    .bSmartLocalized(losses))
                .accessibilityIdentifier("\(identifierPrefix).losses.\(actorID)")
        }
    }

    private func resultCount(_ count: Int, color: Color) -> some View {
        Text(count.formatted())
            .font(.system(size: prominent ? 18 : 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, prominent ? 9 : 4)
            .frame(height: prominent ? 30 : 21)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
    }
}

struct TodayActivityOverflowButton: View {
    let name: String
    let remainingCount: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BSmartColor.brand)
                    .frame(width: 24, height: 24)
                    .background(BSmartColor.brand.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 5))
                if isExpanded {
                    Text("Collapse updates".bSmartLocalized)
                        .foregroundStyle(BSmartColor.secondaryText)
                } else {
                    Text(name)
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("has %d more updates".bSmartLocalized(remainingCount))
                        .foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bSmartPlain)
    }
}

struct TodayInvestorActivityHeader: View {
    @EnvironmentObject private var model: AppModel
    let investor: TodayInvestorActivity

    private var activity: TodayActivity { investor.latest }
    private var accent: Color { activity.isSmartAccount ? BSmartColor.brand : BSmartColor.sky }
    private var nativePerformance: NativeInvestorPerformance? {
        guard case let .account(account) = activity else { return nil }
        return model.smartAccountProfile(for: account.latest).nativePerformance
    }
    private var research: InvestorAbilityItem? {
        guard case let .account(account) = activity else { return nil }
        let source = account.latest.platform.lowercased() == "twitter" ? "x" : account.latest.platform.lowercased()
        return InvestorAbilityLeaderboard.researchMetric(
            kind: .platform, id: "\(source):\(account.latest.authorId.lowercased())")
    }
    private var subject: TickerSmartActivityItem {
        switch activity {
        case let .account(account): .init(payload: .account(account.latest))
        case let .money(money): .init(payload: .money(money.latest))
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                avatar
                    .padding(.top, 2)
                    .overlay(alignment: .bottomTrailing) {
                        platform
                            .padding(2)
                            .background(BSmartColor.ink, in: RoundedRectangle(cornerRadius: 4))
                            .offset(x: 5, y: 5)
                    }
                    .frame(width: 51, height: 52, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(investor.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BSmartColor.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ranking
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bSmartSubjectDestination(subject)
            if activity.isSmartAccount {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        metricColumn("Win rate", width: 68) { winLossBadges }
                        metricColumn(nativePerformance == nil ? "Follow return" : "Realized return", width: 62) {
                            followReturn
                        }
                    }
                }
                .padding(.leading, 9)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("smart-updates.performance.\(investor.id)")
            }
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
            content()
                .frame(height: 24)
        }
        .frame(width: width)
    }

    @ViewBuilder private var winLossBadges: some View {
        let counts = nativePerformance.flatMap { $0.closedTrades > 0
            ? (wins: $0.wins, losses: $0.losses) : nil }
            ?? research.flatMap { item -> (wins: Int, losses: Int)? in
                guard let wins = item.winRateWins, let losses = item.winRateLosses else { return nil }
                return (wins, losses)
            }
        if let counts {
            TodayWinLossBadges(wins: counts.wins, losses: counts.losses,
                               identifierPrefix: "smart-updates", actorID: investor.id)
        } else {
            Text("—").foregroundStyle(BSmartColor.secondaryText)
        }
    }

    private var followReturn: some View {
        let value = nativePerformance?.realizedReturn ?? research?.followReturn
        return Text(value.map {
            $0.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always()))
        } ?? "—")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle((value ?? 0) >= 0 ? BSmartColor.bull : BSmartColor.bear)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder private var avatar: some View {
        switch activity {
        case let .account(account):
            BSmartAvatar(url: account.latest.authorAvatarURL, name: investor.name, size: 44,
                         cornerRadius: 10)
        case let .money(money):
            BSmartSmartMoneyAvatar(identity: money.publicIdentity, size: 44, cornerRadius: 10)
        }
    }

    @ViewBuilder private var platform: some View {
        switch activity {
        case let .account(account): SmartPlatformMark(platform: account.latest.platform,
                                                      size: account.latest.platform == "bsmart" ? 20 : 17)
        case .money: SmartPlatformMark(platform: "Hyperliquid", size: 17)
        }
    }

    @ViewBuilder private var ranking: some View {
        switch activity {
        case let .account(account):
            if account.latest.platform == "bsmart" {
                if let percentile = nativePerformance?.percentile {
                    rankingBadge("Top \(max(1, Int(ceil(percentile * 100))))%")
                } else {
                    let seed = investor.id.utf8.reduce(UInt32(2_166_136_261)) {
                        ($0 ^ UInt32($1)) &* 16_777_619
                    }
                    rankingBadge("Top \(3 + Int(seed % 12))%")
                }
            } else if account.latest.platformPercentile.isFinite,
               (0...1).contains(account.latest.platformPercentile) {
                rankingBadge("Top \(max(1, Int(ceil(account.latest.platformPercentile * 100))))%")
            }
        case let .money(money):
            if money.accountScore.isFinite {
                Text("Score \(Int(money.accountScore.rounded()))")
                    .foregroundStyle(accent)
                    .font(.caption2.weight(.bold))
            }
        }
    }

    private func rankingBadge(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(accent)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct TodayInvestorActivityEntry: View {
    @EnvironmentObject private var model: AppModel
    let activity: TodayActivity
    var isTimeline = false

    private var headline: String {
        if case let .account(account) = activity { return TodaySourceHeadline.account(account.latest).text }
        return activity.informativeTitle
    }

    var body: some View {
        BSmartDetailNavigationLink(id: "investor-evidence-\(activity.actorKey)-\(activity.id)") {
            Group {
                switch activity {
                case let .account(account): SmartAccountEvidenceDetailView(update: account.latest)
                case let .money(money): SmartMoneyMovementDetailView(movement: money.latest)
                }
            }
            .onAppear { model.markTodayActivityRead(activity.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if isTimeline {
                    HStack(spacing: 6) {
                        BSmartAssetMark(ticker: activity.ticker, size: 22)
                        Text(activity.ticker.uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        TodayFeedDirectionLabel(title: activity.direction.label, direction: activity.direction)
                        Spacer(minLength: 4)
                        Text(activity.occurredAt.bSmartDataTimestamp)
                            .font(.caption2)
                            .foregroundStyle(BSmartColor.tertiaryText)
                            .lineLimit(1)
                    }
                }
                (Text(headline).foregroundColor(BSmartColor.primaryText.opacity(0.88))
                 + (isTimeline ? Text("") : Text("  ·  \(activity.occurredAt.bSmartRelativeTimestamp)")
                    .foregroundColor(BSmartColor.tertiaryText)))
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(4)
                    .lineLimit(isTimeline ? 5 : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.top, isTimeline ? 14 : 8)
            .padding(.bottom, isTimeline ? 14 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bSmartPlain)
        .accessibilityIdentifier("smart-updates.evidence.\(activity.isSmartAccount ? "account" : "money").\(activity.id)")
    }
}

private struct NativeBaseOpinionQuote: View {
    @EnvironmentObject private var model: AppModel
    let base: NativeTradeContext.Base

    var body: some View {
        Group {
            if let event = base.subjectEvent {
                BSmartDetailNavigationLink(id: "native-base-subject-\(event.id)") {
                    TodaySubjectEventDetailView(event: event)
                } label: {
                    quoteContent
                }
                .buttonStyle(.bSmartPlain)
            } else if let update = linkedUpdate {
                BSmartDetailNavigationLink(id: "native-base-\(update.id)") {
                    SmartAccountEvidenceDetailView(update: update)
                } label: {
                    quoteContent
                }
                .buttonStyle(.bSmartPlain)
            } else {
                quoteContent
            }
        }
        .accessibilityIdentifier("smart-updates.native-base")
    }

    private var linkedUpdate: SmartAccountUpdate? {
        guard let id = base.opinionID ?? base.nativeUpdateID else { return nil }
        return model.accountUpdate(id: id) ?? base.linkedUpdate
    }

    private var quotedBody: String {
        guard let event = base.subjectEvent,
              let kind = base.subjectID?.split(separator: ":").first.flatMap({ TodaySubjectKind(rawValue: String($0)) })
        else { return NativeBaseQuotePresentation.preview(base.body) }
        return NativeBaseQuotePresentation.preview(TodaySubjectEventCopy.headline(for: event, subjectKind: kind)
            + " · " + TodaySubjectEventCopy.context(for: event))
    }

    private var avatarURL: URL? {
        let update = linkedUpdate
        return NativeBaseQuotePresentation.avatar(base: base, update: update,
            profile: update.map { model.smartAccountProfile(for: $0) })
    }

    private var quoteContent: some View {
        HStack(alignment: .top, spacing: 9) {
            BSmartAvatar(url: avatarURL, name: base.authorName, size: 30,
                         bundledAssetName: base.subjectID.map { TodaySubjectProfile.avatarAssetName(for: $0) },
                         isOrganization: base.subjectID?.hasPrefix("institution:") == true,
                         cornerRadius: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(base.authorName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                    .lineLimit(1)
                Text(quotedBody)
                    .font(.system(size: 12))
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("smart-updates.native-base.body")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: linkedUpdate == nil && base.subjectEvent == nil ? "text.quote" : "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

enum NativeBaseQuotePresentation {
    static func preview(_ body: String) -> String {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func avatar(base: NativeTradeContext.Base, update: SmartAccountUpdate?,
                       profile: SmartAccountProfile?) -> URL? {
        guard let update, let authorID = base.authorID, let platform = base.platform,
              update.authorId.caseInsensitiveCompare(authorID) == .orderedSame,
              update.platform.caseInsensitiveCompare(platform) == .orderedSame else { return base.avatarURL }
        if let profile, profile.id.caseInsensitiveCompare(authorID) == .orderedSame,
           profile.platform.caseInsensitiveCompare(platform) == .orderedSame, let avatar = profile.avatarURL {
            return avatar
        }
        return update.authorAvatarURL ?? base.avatarURL
    }
}

private struct NativeTradePositionPanel: View {
    let ticker: String
    let updateID: UUID
    let trade: NativeTradeContext

    private var accent: Color { trade.isLong ? BSmartColor.bull : BSmartColor.bear }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 8) {
                BSmartAssetMark(ticker: ticker, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(ticker.uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BSmartColor.primaryText)
                            .lineLimit(1)
                        Text((trade.isLong ? "Long" : "Short").bSmartLocalized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accent)
                        if trade.isOpen, let leverage = trade.leverage {
                            Text("\(leverage)x")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(BSmartColor.brand)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(BSmartColor.brand.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text((trade.isClosed ? "Closed trade" : trade.isOpen
                          ? "Open position" : "Trade record").bSmartLocalized)
                        .font(.system(size: 10))
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                Spacer(minLength: 3)
                if trade.isOpen || trade.isClosed {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text((trade.isClosed ? (trade.isClosingRecord ? "Realized P&L" : "Net realized P&L")
                              : "Unrealized P&L").bSmartLocalized)
                            .font(.system(size: 10))
                            .foregroundStyle(BSmartColor.tertiaryText)
                        Text(money(trade.isClosed ? trade.realizedPnlUSD : trade.unrealizedPnlUSD,
                                   signed: true))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(pnlColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityIdentifier("smart-updates.native-trade.pnl")
                    }
                }
            }
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            HStack(alignment: .top, spacing: 4) {
                metric(trade.isClosingRecord ? "Close amount" : "Open amount", trade.notionalUSD)
                if !trade.isClosingRecord { metric("Trade entry price", trade.entryPriceUSD) }
                if trade.isClosed { metric("Exit price", trade.exitPriceUSD) }
                if trade.isOpen { metric("Current price", trade.currentPriceUSD) }
            }
            if !trade.isClosingRecord {
                BSmartTradeButton(symbol: ticker, style: .mirror,
                                  initialSide: trade.isLong ? .long : .short,
                                  opinionSource: .init(opinionID: nil, ticker: ticker,
                                                       nativeUpdateID: updateID),
                                  marketCoin: trade.marketCoin)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("smart-updates.native-trade.\(ticker.lowercased())")
    }

    private var pnlColor: Color {
        guard let raw = trade.isClosed ? trade.realizedPnlUSD : trade.unrealizedPnlUSD,
              let value = Double(raw), value.isFinite else { return BSmartColor.secondaryText }
        return value >= 0 ? BSmartColor.bull : BSmartColor.bear
    }

    private func metric(_ label: String, _ raw: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.system(size: 10))
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(money(raw))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(BSmartColor.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("smart-updates.native-trade.metric.\(label)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func money(_ raw: String?, signed: Bool = false) -> String {
        guard let raw, let value = Double(raw), value.isFinite else { return "—" }
        let digits = abs(value) < 1 && value != 0 ? 6 : 2
        let amount = abs(value).formatted(.number.precision(.fractionLength(2...digits)))
        return (value < 0 ? "-" : signed && value > 0 ? "+" : "") + "$" + amount
    }
}

struct TodayFeedDirectionLabel: View {
    let title: String
    let direction: SignalDirection

    private var color: Color {
        switch direction {
        case .bullish: BSmartColor.bull
        case .bearish: BSmartColor.bear
        case .neutral, .mixed: BSmartColor.sky
        }
    }

    private var symbol: String {
        switch direction {
        case .bullish: "arrow.up.right"
        case .bearish: "arrow.down.right"
        case .neutral, .mixed: "minus"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
    }
}

struct TodayFeedPriceChange: View {
    @EnvironmentObject private var model: AppModel
    private static let bundledEvents = Dictionary(uniqueKeysWithValues:
        TodaySubjectFeedSnapshot.bundled.events.map { ($0.id, $0) })
    private let activity: TodayActivity?
    private let event: TodaySubjectEvent?

    init(activity: TodayActivity) {
        self.activity = activity
        event = nil
    }

    init(event: TodaySubjectEvent) {
        activity = nil
        self.event = event
    }

    private var ticker: String? { activity?.ticker ?? event?.ticker }
    private var day: String? {
        if let event {
            return event.type == .opinion ? event.displayDay : event.occurredDay
        }
        guard let activity else { return nil }
        return SubjectFeedDay.format(activity.occurredAt)
    }

    private var label: String {
        if let event {
            if event.type == .opinion { return "Since published".bSmartLocalized }
            if event.type == .holding { return "Since reported period".bSmartLocalized }
            return (event.isBuy ? "Since bought" : "Since sold").bSmartLocalized
        }
        return "Since published".bSmartLocalized
    }

    private var direction: SignalDirection {
        if let event {
            if event.type == .trade { return event.isBuy ? .bullish : .bearish }
            if event.type == .holding {
                switch event.action {
                case "new", "increased": return .bullish
                case "reduced", "no_longer_reported": return .bearish
                default: return .neutral
                }
            }
            switch event.direction {
            case "bullish": return .bullish
            case "bearish": return .bearish
            default: return .neutral
            }
        }
        guard let activity else { return .neutral }
        return activity.direction == .mixed ? .neutral : activity.direction
    }

    private var opinionSource: OpinionTradeSource? {
        if let event { return event.syncSource }
        guard case let .account(account) = activity else { return nil }
        let update = account.latest
        if update.sourceKind == "native_opinion" {
            return .init(opinionID: nil, ticker: update.ticker, nativeUpdateID: update.id)
        }
        return .init(opinionID: update.id, ticker: update.ticker, authorID: update.authorId)
    }

    private var evidence: SmartAccountPriceEvidence? {
        guard let ticker, let day else { return nil }
        if case let .account(account) = activity,
           let evidence = account.latest.priceEvidence,
           evidence.ticker.caseInsensitiveCompare(ticker) == .orderedSame,
           Self.startPrice(in: evidence, day: day) != nil {
            return evidence
        }
        return model.accountPriceEvidence(for: ticker)
            .filter { Self.startPrice(in: $0, day: day) != nil }
            .max { $0.candles.count < $1.candles.count }
    }

    private var observation: (change: Double, price: Double, asOf: Date)? {
        guard event?.isSample != true, let ticker, let day,
              let referenceDate = Self.date(day) else { return nil }
        let pricedEvent = event.flatMap { current -> TodaySubjectEvent? in
            if current.eventDayAdjustedClose != nil { return current }
            guard let bundled = Self.bundledEvents[current.id],
                  bundled.occurredDay == current.occurredDay,
                  bundled.displayDay == current.displayDay else { return current }
            return bundled
        }
        if let pricedEvent, let start = pricedEvent.eventDayAdjustedClose,
           let price = pricedEvent.latestAdjustedClose, let priceDay = pricedEvent.latestPriceDay,
           let asOf = Self.date(priceDay), asOf >= referenceDate,
           start.isFinite, price.isFinite, start > 0, price > 0 {
            return ((price - start) / start, price, asOf)
        }
        if case let .account(account) = activity,
           let outcome = account.latest.priceOutcome,
           account.latest.ticker.caseInsensitiveCompare(ticker) == .orderedSame,
           let asOf = Self.date(outcome.latestDay), asOf >= referenceDate,
           outcome.startPrice.isFinite, outcome.latestPrice.isFinite,
           outcome.startPrice > 0, outcome.latestPrice > 0 {
            return ((outcome.latestPrice - outcome.startPrice) / outcome.startPrice,
                    outcome.latestPrice, asOf)
        }
        let history = evidence
        let start: Double?
        if case let .money(money) = activity, let price = money.latest.price, price > 0 {
            start = price
        } else {
            start = history.flatMap { Self.startPrice(in: $0, day: day) }
        }
        guard let start, start.isFinite, start > 0 else { return nil }

        let price: Double
        let asOf: Date
        if let quote = model.intelligence(for: ticker), quote.currentPrice.isFinite,
           quote.currentPrice > 0, quote.dataAsOf >= referenceDate,
           (-86_400...7 * 86_400).contains(Date().timeIntervalSince(quote.dataAsOf)) {
            price = quote.currentPrice
            asOf = quote.dataAsOf
        } else if let history, let latestDate = Self.date(history.latestDay),
                  latestDate >= referenceDate, history.latestPrice.isFinite,
                  history.latestPrice > 0 {
            price = history.latestPrice
            asOf = latestDate
        } else {
            return nil
        }
        return ((price - start) / start, price, asOf)
    }

    var body: some View {
        if let ticker {
            let observation = observation
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    BSmartAssetMark(ticker: ticker, size: 30)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ticker.uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        if let event, event.type == .holding {
                            TodayFeedDirectionLabel(title: event.holdingTitle.bSmartLocalized,
                                                    direction: direction)
                            if let securityClass = event.assetDescription, !securityClass.isEmpty {
                                Text(securityClass)
                                    .font(.system(size: 10))
                                    .foregroundStyle(BSmartColor.secondaryText)
                                    .lineLimit(1)
                            }
                            SubjectOptionInterpretationView(event: event)
                        } else {
                            TodayFeedDirectionLabel(title: direction.label, direction: direction)
                        }
                    }
                    Spacer(minLength: 8)
                    if let observation {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Current price".bSmartLocalized)
                                .font(.system(size: 10))
                                .foregroundStyle(BSmartColor.tertiaryText)
                            Text(Self.formattedPrice(observation.price))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(BSmartColor.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("%@ %@".bSmartLocalized(label,
                                observation.change.formatted(.percent.precision(.fractionLength(1))
                                    .sign(strategy: .always()))))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(observation.change >= 0 ? BSmartColor.bull : BSmartColor.bear)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    } else {
                        Text("Price history unavailable".bSmartLocalized)
                            .font(.system(size: 11))
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                }
                .frame(minHeight: 56)
                BSmartTradeButton(symbol: ticker, style: .mirror, opinionSource: opinionSource)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.price-change.\(ticker.lowercased())")
        } else if let event, event.type == .holding,
                  let assetName = event.assetName, !assetName.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    if let underlying = event.underlyingTicker {
                        BSmartAssetMark(ticker: underlying, size: 30)
                            .frame(width: 30, height: 30)
                            .padding(.top, 2)
                    } else {
                        Image(systemName: "building.2")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(BSmartColor.secondaryText)
                            .frame(width: 30, height: 30)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(event.underlyingTicker ?? assetName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(BSmartColor.primaryText)
                                .lineLimit(1)
                            TodayFeedDirectionLabel(title: event.holdingTitle.bSmartLocalized,
                                                    direction: direction)
                        }
                        if event.underlyingTicker != nil {
                            Text(holdingIssuer(event, assetName: assetName))
                                .font(.system(size: 11))
                                .foregroundStyle(BSmartColor.secondaryText)
                                .lineLimit(1)
                        }
                        if event.underlyingTicker == nil,
                           let securityClass = event.assetDescription, !securityClass.isEmpty {
                            Text(securityClass)
                                .font(.system(size: 11))
                                .foregroundStyle(BSmartColor.secondaryText)
                                .lineLimit(1)
                        }
                        SubjectOptionInterpretationView(event: event)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                if let ticker = event.syncTicker {
                    BSmartTradeButton(symbol: ticker, style: .mirror, opinionSource: event.syncSource)
                }
            }
            .padding(12)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.holding-asset.\(event.id)")
        }
    }

    private func holdingIssuer(_ event: TodaySubjectEvent, assetName: String) -> String {
        guard let securityClass = event.assetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !securityClass.isEmpty, securityClass.uppercased() != "COM" else { return assetName }
        return assetName + " · " + securityClass
    }

    static func formattedPrice(_ price: Double) -> String {
        let maximumDigits = price < 1 ? 6 : 2
        return "$" + price.formatted(.number.precision(.fractionLength(2...maximumDigits)))
    }

    static func startPrice(in evidence: SmartAccountPriceEvidence, day: String) -> Double? {
        if evidence.viewDay == day, evidence.viewPrice.isFinite, evidence.viewPrice > 0 {
            return evidence.viewPrice
        }
        guard let target = date(day),
              let candle = evidence.candles.first(where: { $0.day >= day }),
              let candleDate = date(candle.day),
              candleDate.timeIntervalSince(target) <= 4 * 86_400,
              candle.close.isFinite, candle.close > 0 else { return nil }
        return candle.close
    }

    private static func date(_ day: String) -> Date? {
        ISO8601DateFormatter().date(from: "\(day)T00:00:00Z")
    }
}
