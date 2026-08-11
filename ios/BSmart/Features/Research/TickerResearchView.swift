import SwiftUI

private enum TickerIntelligenceSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case account = "Smart Account"
    case money = "Smart Money"

    var id: Self { self }
}

struct TickerIntelligenceView: View {
    @EnvironmentObject private var model: AppModel
    let ticker: TickerIntelligence
    @State private var editingPosition: PortfolioPosition?
    @State private var isAddingTicker = false
    @State private var selection: TickerIntelligenceSection = .overview

    private var accountUpdates: [SmartAccountUpdate] {
        model.accountUpdates(for: ticker.ticker)
    }

    private var moneyMovements: [SmartMoneyMovement] {
        model.moneyMovements(for: ticker.ticker)
    }

    private var relatedSignals: [PortfolioSignal] {
        model.signals(for: ticker.ticker)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                quoteHeader
                sectionPicker

                switch selection {
                case .overview:
                    relationshipSummary
                    evidencePulseSummary
                    signalHistory
                case .account:
                    smartAccountSection
                case .money:
                    smartMoneySection
                }
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .accessibilityIdentifier("ticker-intelligence.\(ticker.ticker)")
        .navigationTitle(ticker.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let position = model.position(for: ticker.ticker) {
                    Button {
                        editingPosition = position
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit tracked ticker")
                    .accessibilityIdentifier("ticker-intelligence.edit")
                } else {
                    Button {
                        isAddingTicker = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Add to portfolio or watchlist")
                    .accessibilityIdentifier("ticker-intelligence.track")
                }
            }
        }
        .sheet(item: $editingPosition) { position in
            AddPositionView(position: position)
                .environmentObject(model)
        }
        .sheet(isPresented: $isAddingTicker) {
            AddPositionView(
                prefilledTicker: ticker.ticker,
                prefilledCompanyName: ticker.companyName,
                initialKind: .watchlist
            )
            .environmentObject(model)
        }
        .bSmartPage()
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(TickerIntelligenceSection.allCases) { section in
                Button {
                    withAnimation(BSmartMotion.quick) {
                        selection = section
                    }
                } label: {
                    Text(section.rawValue.bSmartLocalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(selection == section ? BSmartColor.pulse.opacity(0.09) : Color.clear)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(selection == section ? BSmartColor.pulse : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .background(BSmartColor.recessed)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.line, lineWidth: 0.6)
        }
    }

    private var quoteHeader: some View {
        HStack(alignment: .center, spacing: BSmartSpacing.medium) {
            BSmartAssetMark(ticker: ticker.ticker, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(ticker.companyName)
                    .font(.headline)
                Text(
                    "Data as of %@".bSmartLocalized(
                        ticker.dataAsOf.bSmartDataTimestamp
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ticker.currentPrice.formatted(.currency(code: "USD")))
                    .font(.headline)
                    .monospacedDigit()
                Text(ticker.dayChangePercent.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ticker.dayChangePercent >= 0 ? BSmartColor.brand : BSmartColor.bear)
                    .monospacedDigit()
            }
        }
    }

    private var relationshipSummary: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.small) {
                Label("Current relationship", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundStyle(BSmartColor.primaryText)
                Spacer()
                BSmartTag(text: ticker.relationship.label, color: ticker.direction.color)
                BSmartTag(text: ticker.direction.label, color: ticker.direction.color)
            }

            Text(ticker.conclusion.bSmartLocalized)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if let latestSignal = relatedSignals.first(where: { $0.id == ticker.latestSignalId }) {
                NavigationLink(value: latestSignal) {
                    Label("Open latest signal", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.brand)
                }
            }
        }
        .bSmartPanel(border: BSmartColor.pulse.opacity(0.34))
    }

    private var evidencePulseSummary: some View {
        HStack(alignment: .top, spacing: BSmartSpacing.small) {
            BSmartEvidenceStateCell(
                title: "Smart Account",
                symbol: "person.wave.2",
                value: ticker.smartAccount.headline,
                detail: "%d qualified authors".bSmartLocalized(ticker.smartAccount.qualifiedAuthorCount),
                color: ticker.smartAccount.direction.color
            )

            BSmartEvidenceStateCell(
                title: "Smart Money",
                symbol: "wallet.bifold",
                value: ticker.smartMoney.coverage == .available
                    ? ticker.smartMoney.headline
                    : "No capital verification",
                detail: ticker.smartMoney.coverage == .available
                    ? "%d qualified public accounts".bSmartLocalized(ticker.smartMoney.qualifiedAccountCount)
                    : "Coverage is absent, not neutral",
                color: ticker.smartMoney.coverage == .available
                    ? ticker.smartMoney.direction.color
                    : BSmartColor.gold
            )
        }
    }

    private var smartAccountSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            sourceHeader(
                title: "Smart Account",
                symbol: "person.wave.2",
                direction: ticker.smartAccount.direction,
                count: ticker.smartAccount.qualifiedAuthorCount,
                countLabel: "qualified author"
            )

            Text(ticker.smartAccount.headline.bSmartLocalized)
                .font(.headline)
            Text(ticker.smartAccount.detail.bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(accountUpdates.prefix(3).enumerated()), id: \.element.id) { index, update in
                if index > 0 {
                    Divider().overlay(BSmartColor.line)
                }
                accountUpdateRow(update)
            }
        }
        .bSmartSurface()
    }

    private var smartMoneySection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.small) {
                Label("Smart Money", systemImage: "wallet.bifold")
                    .font(.headline)
                Spacer()
                if ticker.smartMoney.coverage == .available {
                    BSmartTag(text: ticker.smartMoney.direction.label, color: ticker.smartMoney.direction.color)
                }
            }

            HStack {
                Text(qualifiedCount(ticker.smartMoney.qualifiedAccountCount, label: "scored capital account"))
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                Spacer()
                BSmartTag(text: ticker.smartMoney.coverage.label, color: ticker.smartMoney.coverage.color)
            }

            Text(ticker.smartMoney.headline.bSmartLocalized)
                .font(.headline)
            Text(ticker.smartMoney.detail.bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(moneyMovements.prefix(3).enumerated()), id: \.element.id) { index, movement in
                if index > 0 {
                    Divider().overlay(BSmartColor.line)
                }
                moneyMovementRow(movement)
            }
        }
        .bSmartSurface()
    }

    @ViewBuilder
    private var signalHistory: some View {
        if !relatedSignals.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: "Signal history", detail: "Latest first")

                ForEach(Array(relatedSignals.prefix(5).enumerated()), id: \.element.id) { index, signal in
                    if index > 0 {
                        Divider().overlay(BSmartColor.line)
                    }
                    NavigationLink(value: signal) {
                        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                            Image(systemName: signal.priority.symbol)
                                .foregroundStyle(signal.priority.color)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                                Text(signal.title.bSmartLocalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BSmartColor.primaryText)
                                    .multilineTextAlignment(.leading)
                                Text(signal.occurredAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(BSmartColor.tertiaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .bSmartSurface()
        }
    }

    private func sourceHeader(
        title: String,
        symbol: String,
        direction: SignalDirection,
        count: Int,
        countLabel: String
    ) -> some View {
        HStack(spacing: BSmartSpacing.small) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Spacer()
            Text(qualifiedCount(count, label: countLabel))
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            BSmartTag(text: direction.label, color: direction.color)
        }
    }

    private func accountUpdateRow(_ update: SmartAccountUpdate) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack {
                BSmartAvatar(url: update.authorAvatarURL, name: update.authorName, size: 28)
                Text(update.authorName)
                    .font(.subheadline.weight(.semibold))
                if update.authorVerified == true {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.sky)
                }
                BSmartTag(text: update.lifecycle.label, color: update.direction.color)
                Spacer()
                Text(
                    "Score %@".bSmartLocalized(
                        update.score.formatted(.number.precision(.fractionLength(0)))
                    )
                )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
                    .monospacedDigit()
            }

            Text(update.originalText ?? update.thesis)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BSmartSpacing.medium) {
                Text(update.platform)
                if let followers = update.authorFollowersCount {
                    Text("%@ followers".bSmartLocalized(followers.formatted()))
                }
                Text(update.horizon.bSmartLocalized)
                if let targetPrice = update.targetPrice {
                    Text(
                        "Target %@".bSmartLocalized(
                            targetPrice.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                        )
                    )
                }
                Spacer()
                Text(update.publishedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(BSmartColor.tertiaryText)
        }
    }

    private func moneyMovementRow(_ movement: SmartMoneyMovement) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartSmartMoneyAvatar(identity: movement.publicIdentity, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(movement.publicIdentity.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text("Anonymous capital account".bSmartLocalized)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    BSmartTag(text: movement.action.label, color: movement.direction.color)
                    Text(compactSignedCurrency(movement.notionalChange))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(movement.direction.color)
                        .monospacedDigit()
                }
            }

            HStack(spacing: BSmartSpacing.medium) {
                Text(
                    "Score %@".bSmartLocalized(
                        movement.accountScore.formatted(.number.precision(.fractionLength(0)))
                    )
                )
                if let leverage = movement.leverage {
                    Text("\(leverage.formatted(.number.precision(.fractionLength(1))))x")
                }
                Spacer()
                Text(movement.observedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(BSmartColor.tertiaryText)
        }
    }

    private func compactSignedCurrency(_ value: Double) -> String {
        let prefix = value >= 0 ? "+" : "-"
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000...:
            return String(format: "%@$%.2fM", prefix, magnitude / 1_000_000)
        case 1_000...:
            return String(format: "%@$%.0fK", prefix, magnitude / 1_000)
        default:
            return prefix + magnitude.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        }
    }

    private func qualifiedCount(_ count: Int, label: String) -> String {
        let localizedLabel = "\(label)\(count == 1 ? "" : "s")".bSmartLocalized
        return "\(count) \(localizedLabel)"
    }
}
