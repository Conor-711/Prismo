import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var didTrackOpen = false
    @State private var isAuditExpanded = false
    let signal: PortfolioSignal

    private var position: PortfolioPosition? { model.position(for: signal.ticker) }
    private var accountEvidence: [PortfolioSignalEvidence] { signal.evidence(for: .smartAccount) }
    private var moneyEvidence: [PortfolioSignalEvidence] { signal.evidence(for: .smartMoney) }
    private var userState: SignalUserState { model.signalUserState(for: signal.id) }
    private var personalization: PortfolioSignalPersonalization { model.personalization(for: signal) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.large) {
                changeHeader
                positionContext
                evidencePulseSummary
                evidenceRelationshipSection
                auditSection
                feedbackSection
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .navigationTitle(signal.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    model.toggleSignalSaved(signal.id)
                } label: {
                    Image(systemName: userState.isSaved ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(
                    (userState.isSaved ? "Remove saved signal" : "Save signal").bSmartLocalized
                )

                Menu {
                    Button {
                        model.markSignalRead(signal.id, isRead: !userState.isRead)
                    } label: {
                        Label(
                            userState.isRead ? "Mark unread" : "Mark read",
                            systemImage: userState.isRead ? "circle" : "checkmark.circle"
                        )
                    }

                    Button(role: .destructive) {
                        model.ignoreSignal(signal.id)
                        dismiss()
                    } label: {
                        Label("Ignore signal", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More signal actions".bSmartLocalized)
            }
        }
        .task {
            model.markSignalRead(signal.id)
            guard !didTrackOpen else { return }
            didTrackOpen = true
            model.trackSignalOpened(signal)
        }
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("event-detail.screen")
    }

    private var changeHeader: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(spacing: BSmartSpacing.medium) {
                BSmartAssetMark(ticker: signal.ticker, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(signal.ticker) · \(signal.companyName)")
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(signal.occurredAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
                Spacer()
                BSmartTag(text: personalization.attention.label, color: personalization.attention.color)
            }

            if position == nil {
                Button(action: addToWatchlist) {
                    Label("Watch %@".bSmartLocalized(signal.ticker), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("event.watch.\(signal.ticker)")
            }

            HStack(spacing: BSmartSpacing.small) {
                BSmartTag(text: signal.kind.label, color: BSmartColor.sky)
                BSmartTag(text: signal.direction.label, color: signal.direction.color)
                Spacer()
                Label(signal.resolvedDataStatus.label, systemImage: signal.resolvedDataStatus.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(signal.resolvedDataStatus.color)
            }

            Text(signal.title.bSmartLocalized)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text(signal.summary.bSmartLocalized)
                .font(.body)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                Label("bSmart conclusion", systemImage: "scope")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.pulse)
                    .textCase(.uppercase)
                Text(signal.conclusion.bSmartLocalized)
                    .font(.headline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .bSmartPanel(
                padding: BSmartSpacing.medium,
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
    }

    private var evidencePulseSummary: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            BSmartSectionTitle(
                title: "Evidence now",
                detail: signal.kind.label
            )

            HStack(alignment: .top, spacing: BSmartSpacing.small) {
                BSmartEvidenceStateCell(
                    title: "Smart Account",
                    symbol: SignalEvidenceSource.smartAccount.symbol,
                    value: accountEvidence.isEmpty
                        ? "No qualified view"
                        : "%d qualified views".bSmartLocalized(accountEvidence.count),
                    detail: accountEvidence.first?.actorName ?? "Waiting for a scored public view",
                    color: accountEvidence.isEmpty ? BSmartColor.tertiaryText : BSmartColor.sky
                )

                BSmartEvidenceStateCell(
                    title: "Smart Money",
                    symbol: SignalEvidenceSource.smartMoney.symbol,
                    value: signal.smartMoneyCoverage == .unavailable
                        ? "No capital verification"
                        : "%d capital moves".bSmartLocalized(moneyEvidence.count),
                    detail: signal.smartMoneyCoverage == .unavailable
                        ? "Coverage is absent, not neutral"
                        : (moneyEvidence.first?.actorName ?? "Public account activity"),
                    color: signal.smartMoneyCoverage == .unavailable ? BSmartColor.gold : BSmartColor.brand
                )
            }
        }
    }

    private var positionContext: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Label(contextLabel, systemImage: contextSymbol)
                    .font(.headline.weight(.bold))
                Spacer()
                Text(positionDetail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.secondaryText)
            }

            HStack(spacing: 0) {
                if position?.resolvedKind == .position {
                    contextMetric(label: "Weight", value: positionWeightLabel)
                    contextMetric(label: "Avg cost", value: averageCostLabel)
                    contextMetric(label: "Current", value: currentPriceLabel)
                } else {
                    contextMetric(label: "Status", value: position == nil ? "Not tracked" : "Watching")
                    contextMetric(label: "Current", value: currentPriceLabel)
                    contextMetric(label: "Signal", value: personalization.attention.label)
                }
            }

            Text(personalization.localizedImpactText(for: signal))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(BSmartColor.brand)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                    Text("Watch next")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                        .textCase(.uppercase)
                    Text(signal.nextStep.bSmartLocalized)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(BSmartSpacing.medium)
            .background(BSmartColor.recessed)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
        }
        .bSmartPanel()
    }

    private var evidenceRelationshipSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack {
                Label("Evidence relationship", systemImage: relationshipSymbol)
                    .font(.headline.weight(.bold))
                Spacer()
                BSmartTag(text: relationshipLabel, color: relationshipColor)
            }

            Text(relationshipExplanation)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            evidenceSourceBlock(
                title: "Smart Account",
                symbol: SignalEvidenceSource.smartAccount.symbol,
                evidence: accountEvidence,
                emptyTitle: "No qualifying Smart Account update",
                emptyDetail: "No independent creator view met the score, recency, and evidence thresholds for this signal.",
                color: BSmartColor.sky
            )

            Divider().overlay(BSmartColor.line)

            evidenceSourceBlock(
                title: "Smart Money",
                symbol: SignalEvidenceSource.smartMoney.symbol,
                evidence: moneyEvidence,
                emptyTitle: moneyEmptyTitle,
                emptyDetail: moneyEmptyDetail,
                color: signal.smartMoneyCoverage == .unavailable ? BSmartColor.gold : BSmartColor.brand
            )
        }
        .bSmartPanel(border: relationshipColor.opacity(0.34))
    }

    @ViewBuilder
    private func evidenceSourceBlock(
        title: String,
        symbol: String,
        evidence: [PortfolioSignalEvidence],
        emptyTitle: String,
        emptyDetail: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                Text("%d updates".bSmartLocalized(evidence.count))
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            if evidence.isEmpty {
                unavailableSource(
                    title: emptyTitle.bSmartLocalized,
                    detail: emptyDetail.bSmartLocalized,
                    symbol: symbol,
                    color: color
                )
            } else {
                evidenceRows(evidence)
            }
        }
    }

    private func evidenceRows(_ evidence: [PortfolioSignalEvidence]) -> some View {
        ForEach(Array(evidence.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                Divider().overlay(BSmartColor.line)
            }
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                HStack(alignment: .center, spacing: BSmartSpacing.small) {
                    evidenceAvatar(for: item, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.actorName)
                            .font(.subheadline.weight(.semibold))
                        if let update = model.accountUpdate(id: item.referenceId),
                           let followers = update.authorFollowersCount {
                            Text("%@ followers · %@".bSmartLocalized(followers.formatted(), update.platform))
                                .font(.caption2)
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                    }
                    Spacer()
                    if let metric = item.metric {
                        Text(metric)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BSmartColor.brand)
                            .monospacedDigit()
                    }
                }
                Text(item.title.bSmartLocalized)
                    .font(.body.weight(.semibold))
                Text(item.detail.bSmartLocalized)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.observedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            .padding(.vertical, index == 0 ? 0 : BSmartSpacing.xSmall)
        }
    }

    private func unavailableSource(
        title: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            DisclosureGroup(isExpanded: $isAuditExpanded) {
                VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                    HStack(spacing: BSmartSpacing.small) {
                        Image(systemName: signal.resolvedDataStatus.symbol)
                        Text(signal.resolvedDataStatus.label)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("As of %@".bSmartLocalized(
                            signal.dataAsOf.bSmartDataTimestamp
                        ))
                            .foregroundStyle(BSmartColor.tertiaryText)
                    }
                    .font(.caption)
                    .foregroundStyle(signal.resolvedDataStatus.color)

                    VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                        Label("Why this priority", systemImage: personalization.attention.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(personalization.attention.color)
                        Text(personalization.localizedAttentionReason(for: signal))
                            .font(.subheadline)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !signal.resolvedLimitations.isEmpty {
                        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                            Text("Data & limitations")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BSmartColor.secondaryText)
                                .textCase(.uppercase)
                            ForEach(signal.resolvedLimitations, id: \.self) { limitation in
                                HStack(alignment: .top, spacing: BSmartSpacing.small) {
                                    Circle()
                                        .fill(BSmartColor.tertiaryText)
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 7)
                                    Text(limitation.bSmartLocalized)
                                        .font(.subheadline)
                                        .foregroundStyle(BSmartColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    originalEvidenceContent
                }
                .padding(.top, BSmartSpacing.medium)
            } label: {
                HStack {
                    Label("Data & evidence audit", systemImage: "checkmark.shield")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("%d source items".bSmartLocalized(signal.evidence.count))
                        .font(.caption2)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }
        }
        .bSmartPanel()
    }

    private var originalEvidenceContent: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Original evidence",
                detail: "%d items".bSmartLocalized(signal.evidence.count)
            )

            ForEach(Array(signal.evidence.enumerated()), id: \.element.id) { index, evidence in
                if index > 0 {
                    Divider().overlay(BSmartColor.line)
                }

                if let url = sourceURL(for: evidence) {
                    Button {
                        model.trackEvidenceOpened(evidence, in: signal)
                        openURL(url)
                    } label: {
                        originalEvidenceRow(evidence, isAvailable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    originalEvidenceRow(evidence, isAvailable: false)
                }
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Signal feedback", detail: "Improves your feed")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: BSmartSpacing.small),
                    GridItem(.flexible(), spacing: BSmartSpacing.small),
                ],
                spacing: BSmartSpacing.small
            ) {
                ForEach(SignalFeedback.allCases, id: \.self) { feedback in
                    let isSelected = userState.feedback == feedback
                    Button {
                        model.setSignalFeedback(isSelected ? nil : feedback, for: signal.id)
                    } label: {
                        Label(feedback.label, systemImage: feedback.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? BSmartColor.brand : BSmartColor.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(isSelected ? BSmartColor.brand.opacity(0.12) : BSmartColor.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                    .stroke(isSelected ? BSmartColor.brand : BSmartColor.line, lineWidth: 0.75)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .bSmartPanel()
    }

    private func originalEvidenceRow(
        _ evidence: PortfolioSignalEvidence,
        isAvailable: Bool
    ) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            evidenceAvatar(for: evidence, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.actorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                Text(
                    (isAvailable ? "Open source evidence" : "Source link unavailable in this dataset")
                        .bSmartLocalized
                )
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
            Spacer()
            if isAvailable {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.brand)
            }
        }
        .padding(.vertical, BSmartSpacing.xSmall)
    }

    private func sourceURL(for evidence: PortfolioSignalEvidence) -> URL? {
        if let url = evidence.sourceURL { return url }
        switch evidence.source {
        case .smartAccount:
            return model.accountUpdate(id: evidence.referenceId)?.evidenceURL
        case .smartMoney:
            return model.moneyMovement(id: evidence.referenceId)?.evidenceURL
        }
    }

    private func avatarURL(for evidence: PortfolioSignalEvidence) -> URL? {
        guard evidence.source == .smartAccount else { return nil }
        return model.accountUpdate(id: evidence.referenceId)?.authorAvatarURL
    }

    @ViewBuilder
    private func evidenceAvatar(for evidence: PortfolioSignalEvidence, size: CGFloat) -> some View {
        if evidence.source == .smartMoney {
            let identity = model.moneyMovement(id: evidence.referenceId)?.publicIdentity
                ?? SmartMoneyPublicIdentity.resolve(
                    identityKey: evidence.actorName,
                    displayName: evidence.actorName,
                    avatarVariant: evidence.avatarVariant
                )
            BSmartSmartMoneyAvatar(identity: identity, size: size)
        } else {
            BSmartAvatar(url: avatarURL(for: evidence), name: evidence.actorName, size: size)
        }
    }

    private func contextMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contextLabel: String {
        switch position?.resolvedKind {
        case .position: "Your position".bSmartLocalized
        case .watchlist: "Your watchlist".bSmartLocalized
        case nil: "Not tracked".bSmartLocalized
        }
    }

    private var contextSymbol: String {
        switch position?.resolvedKind {
        case .position: "briefcase.fill"
        case .watchlist: "eye.fill"
        case nil: "plus.circle"
        }
    }

    private var positionDetail: String {
        switch position?.resolvedKind {
        case .position: positionWeightLabel
        case .watchlist: "Monitoring".bSmartLocalized
        case nil: "Outside your portfolio".bSmartLocalized
        }
    }

    private var positionWeightLabel: String {
        model.positionWeight(for: signal.ticker)
            .formatted(.percent.precision(.fractionLength(0)))
    }

    private var averageCostLabel: String {
        guard let position, position.averageCost > 0 else { return "Not entered" }
        return position.averageCost.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private var currentPriceLabel: String {
        let price = position?.currentPrice ?? model.intelligence(for: signal.ticker)?.currentPrice
        guard let price else { return "Unavailable".bSmartLocalized }
        return price.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private var relationshipLabel: String {
        switch signal.kind {
        case .confirmation: "Views and capital agree".bSmartLocalized
        case .divergence: "Views and capital diverge".bSmartLocalized
        case .accountLeads: "Account view moved first".bSmartLocalized
        case .moneyLeads: "Capital moved first".bSmartLocalized
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus:
            "Smart Account changed".bSmartLocalized
        case .smartMoneyMovement: "Smart Money changed".bSmartLocalized
        }
    }

    private var relationshipSymbol: String {
        switch signal.kind {
        case .confirmation: "checkmark.seal.fill"
        case .divergence: "arrow.left.arrow.right"
        case .accountLeads: "person.wave.2"
        case .moneyLeads: "wallet.bifold"
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus:
            "person.crop.circle.badge.clock"
        case .smartMoneyMovement: "arrow.up.arrow.down"
        }
    }

    private var relationshipColor: Color {
        switch signal.kind {
        case .confirmation: BSmartColor.brand
        case .divergence: BSmartColor.bear
        case .accountLeads, .smartAccountNewView, .smartAccountShift, .smartAccountConsensus:
            BSmartColor.sky
        case .moneyLeads, .smartMoneyMovement: BSmartColor.gold
        }
    }

    private var relationshipExplanation: String {
        let key = switch signal.kind {
        case .confirmation:
            "Qualified views and public capital point in the same direction."
        case .divergence:
            "Qualified views and public capital point in different directions."
        case .accountLeads:
            "A qualified investor view changed before a matching public-capital move appeared."
        case .moneyLeads:
            "Public capital moved before a matching qualified investor view appeared."
        case .smartAccountNewView, .smartAccountShift, .smartAccountConsensus:
            "Qualified investor views changed; no independent capital conclusion is implied."
        case .smartMoneyMovement:
            "Observable public capital changed; no independent investor-view conclusion is implied."
        }
        return key.bSmartLocalized
    }

    private var moneyEmptyTitle: String {
        signal.smartMoneyCoverage == .unavailable
            ? "No capital verification"
            : "No qualifying capital action"
    }

    private var moneyEmptyDetail: String {
        signal.smartMoneyCoverage == .unavailable
            ? signal.smartMoneyCoverage.detail
            : "Capital coverage exists, but no independent account movement belongs to this signal."
    }

    private func addToWatchlist() {
        _ = model.savePortfolioEntry(
            id: nil,
            ticker: signal.ticker,
            companyName: signal.companyName,
            kind: .watchlist,
            shares: nil,
            averageCost: nil,
            portfolioWeight: nil
        )
    }
}

#if DEBUG
private struct EventDetailPreviewHost: View {
    @StateObject private var model = AppModel()
    let ticker: String

    var body: some View {
        NavigationStack {
            if let signal = model.signals.first(where: { $0.ticker == ticker }) {
                EventDetailView(signal: signal)
            } else {
                BSmartLoadingView()
            }
        }
        .environmentObject(model)
        .task { await model.load() }
    }
}

#Preview("Divergence") {
    EventDetailPreviewHost(ticker: "HOOD")
        .preferredColorScheme(.dark)
}

#Preview("Confirmation") {
    EventDetailPreviewHost(ticker: "NVDA")
        .preferredColorScheme(.dark)
}

#Preview("Account only") {
    EventDetailPreviewHost(ticker: "MSTR")
        .preferredColorScheme(.dark)
}

#Preview("Money leads delayed") {
    EventDetailPreviewHost(ticker: "PLTR")
        .preferredColorScheme(.dark)
}
#endif
