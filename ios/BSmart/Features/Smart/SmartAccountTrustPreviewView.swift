import Foundation
import SwiftUI

struct SmartAccountTrustPreviewView: View {
    @EnvironmentObject private var model: AppModel

    let account: SmartAccountProfile

    @State private var showsRankExplanation = false
    @State private var expandedEvidenceID: UUID?

    private var updates: [SmartAccountUpdate] {
        model.accountEvidence(for: account)
    }

    private var representativeWorks: [SmartAccountUpdate] {
        model.representativeAccountEvidence(for: account, limit: 3)
    }

    private var latestUpdate: SmartAccountUpdate? {
        updates.max { $0.publishedAt < $1.publishedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                identityHeader
                profileActions

                if showsRankExplanation {
                    rankExplanation
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                keyMetrics
                recentSummary
                strategyProfile
                representativeEvidence
                disclosure
            }
            .padding(.horizontal, BSmartSpacing.large)
            .padding(.top, BSmartSpacing.small)
            .padding(.bottom, BSmartSpacing.xxxLarge)
        }
        .background(BSmartColor.surface)
        .navigationTitle("Smart Account")
        .navigationBarTitleDisplayMode(.inline)
        .bSmartDetailPage()
        .bSmartPage()
        .accessibilityIdentifier("smart.account.trust-preview")
        .task(id: account.id) {
            await model.loadSmartAccountEvidence(for: account)
        }
    }

    private var identityHeader: some View {
        HStack(spacing: BSmartSpacing.medium) {
            BSmartAvatar(url: account.avatarURL, name: account.name, size: 58)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(account.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    if account.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(BSmartColor.sky)
                            .accessibilityLabel("Verified".bSmartLocalized)
                    }
                }

                Text(identityLine)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: BSmartSpacing.small)
        }
    }

    private var profileActions: some View {
        HStack(spacing: BSmartSpacing.small) {
            BSmartDetailNavigationLink(id: "trust-profile-\(account.id)") {
                SmartAccountDetailView(account: account)
            } label: {
                Text("View full profile".bSmartLocalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BSmartColor.pulseInk)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(BSmartColor.brand)
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("smart.account.trust-preview.full-profile")

            Button {
                withAnimation(BSmartMotion.quick) {
                    showsRankExplanation.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(rankLabel)
                        .lineLimit(1)
                    Image(systemName: showsRankExplanation ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.pulse)
                .padding(.horizontal, BSmartSpacing.small)
                .frame(minHeight: 38)
                .background(BSmartColor.pulse.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                        .stroke(BSmartColor.pulse.opacity(0.55), lineWidth: 0.75)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("smart.account.trust-preview.rank")
        }
    }

    private var rankExplanation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("What this ranking means".bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
            Text(rankExplanationText)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BSmartSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.pulse.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                .stroke(BSmartColor.pulse.opacity(0.35), lineWidth: 0.6)
        }
    }

    private var keyMetrics: some View {
        BSmartMetricStrip(metrics: [
            BSmartStripMetric(
                id: "score",
                label: "Account Score",
                value: account.score.formatted(.number.precision(.fractionLength(0))),
                color: BSmartColor.brand
            ),
            BSmartStripMetric(
                id: "settled",
                label: "Settled calls",
                value: account.resolvedSettledCalls.formatted()
            ),
            BSmartStripMetric(
                id: "coverage",
                label: "Covered tickers",
                value: account.resolvedCoveredTickers.formatted()
            ),
        ])
    }

    private var recentSummary: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Label("Mr Collie summary".bSmartLocalized, systemImage: "sparkles")
                .font(.caption.weight(.black))
                .foregroundStyle(BSmartColor.brand)

            Text(recentSummaryText)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BSmartSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.recessed)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(BSmartColor.brand)
                .frame(width: 3)
        }
    }

    private var strategyProfile: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            BSmartSectionHeader(
                title: "Investment strategy profile",
                detail: "Derived from public views"
            )

            Text(strategySummary)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    strategyTag(account.horizon)
                    strategyTag(account.resolvedStyle)
                    strategyTag(account.specialty)
                    if representativeWorks.contains(where: { $0.targetPrice != nil }) {
                        strategyTag("Explicit targets")
                    }
                    if representativeWorks.contains(where: { $0.invalidation?.isEmpty == false }) {
                        strategyTag("Stated invalidation")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var representativeEvidence: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            BSmartSectionHeader(
                title: "Representative works",
                detail: "Up to 3 different tickers"
            )

            if representativeWorks.isEmpty {
                HStack(spacing: BSmartSpacing.small) {
                    if model.isLoadingAccountEvidence(account) {
                        ProgressView()
                            .tint(BSmartColor.brand)
                    }
                    Text("No settled representative work with price evidence is available yet.".bSmartLocalized)
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(representativeWorks.enumerated()), id: \.element.id) { index, update in
                        if index > 0 {
                            Divider().overlay(BSmartColor.line)
                        }
                        representativeRow(update)
                    }
                }
                .padding(.horizontal, BSmartSpacing.medium)
                .background(BSmartColor.recessed)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                        .stroke(BSmartColor.line, lineWidth: 0.6)
                }
            }
        }
    }

    private func representativeRow(_ update: SmartAccountUpdate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(BSmartMotion.quick) {
                    expandedEvidenceID = expandedEvidenceID == update.id ? nil : update.id
                }
            } label: {
                HStack(spacing: BSmartSpacing.medium) {
                    BSmartAssetMark(ticker: update.ticker, size: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(representativeTitle(update))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BSmartColor.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text("%@ · %@".bSmartLocalized(update.direction.label, update.horizon))
                            Text(settlementLabel(update))
                                .foregroundStyle(settlementColor(update))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BSmartColor.tertiaryText)
                    }

                    Spacer(minLength: 0)

                    if let evidence = update.priceEvidence {
                        SmartAccountEvidenceSparkline(update: update, evidence: evidence)
                            .frame(width: 88, height: 46)
                    }
                }
                .padding(.vertical, BSmartSpacing.medium)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("smart.account.trust-preview.evidence.\(update.ticker.lowercased())")

            if expandedEvidenceID == update.id {
                evidenceDetails(update)
                    .padding(.bottom, BSmartSpacing.medium)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func evidenceDetails(_ update: SmartAccountUpdate) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text(update.evidenceSpan?.nilIfBlank ?? update.thesis)
                .font(.caption)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let settlement = update.settlement {
                HStack(spacing: 0) {
                    evidenceMetric("Entry", settlement.entryPrice.map(currency) ?? "—")
                    Divider().overlay(BSmartColor.line)
                    evidenceMetric("Exit", settlement.exitPrice.map(currency) ?? "—")
                    Divider().overlay(BSmartColor.line)
                    evidenceMetric("Underlying return", signedPercent(settlement.tickerReturnPercent))
                }
                .frame(minHeight: 48)
            }
        }
        .padding(BSmartSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
    }

    private var disclosure: some View {
        Text("These are historical price outcomes after public views, not verified holdings, account PnL or a promise of future performance.".bSmartLocalized)
            .font(.caption2)
            .foregroundStyle(BSmartColor.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, BSmartSpacing.small)
            .overlay(alignment: .top) {
                Rectangle().fill(BSmartColor.line).frame(height: 0.5)
            }
    }

    private func strategyTag(_ value: String) -> some View {
        Text(value.bSmartLocalized)
            .font(.caption2.weight(.bold))
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.horizontal, BSmartSpacing.small)
            .frame(minHeight: 26)
            .background(BSmartColor.recessed)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.5)
            }
    }

    private func evidenceMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.bSmartLocalized)
                .font(.system(size: 9))
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private var identityLine: String {
        var parts = [account.platform, account.handle]
        if let followers = account.followersCount {
            parts.append("%@ followers".bSmartLocalized(compactCount(followers)))
        }
        return parts.joined(separator: " · ")
    }

    private var rankLabel: String {
        let rank = account.resolvedRank > 0 ? "#\(account.resolvedRank)" : "—"
        let percentile = max(1, Int(ceil(account.resolvedPlatformPercentile * 100)))
        return "%@ · Top %d%%".bSmartLocalized(rank, percentile)
    }

    private var rankExplanationText: String {
        guard account.resolvedRank > 0 else {
            return "Based on %d settled %@ views and adjusted for sample confidence. A formal overall rank is not available for this account yet."
                .bSmartLocalized(
                    account.resolvedSettledCalls,
                    account.platform
                )
        }

        return "Based on %d settled %@ views and adjusted for sample confidence. This account ranks #%d overall and in the top %d%% on its platform."
            .bSmartLocalized(
                account.resolvedSettledCalls,
                account.platform,
                account.resolvedRank,
                max(1, Int(ceil(account.resolvedPlatformPercentile * 100)))
            )
    }

    private var recentSummaryText: String {
        guard let update = latestUpdate else {
            return "This account has no recent qualified view in the current product window. Use the representative works below to understand its historical process."
                .bSmartLocalized
        }

        let target = update.targetPrice.map {
            "with a %@ target".bSmartLocalized(currency($0))
        } ?? "without a stated target".bSmartLocalized

        return "The latest qualified view covers %@ with a %@ stance over %@, %@. Across %d settled views, the account most often uses a %@ style."
            .bSmartLocalized(
                update.ticker,
                update.direction.label.bSmartLocalized.lowercased(),
                update.horizon.bSmartLocalized,
                target,
                account.resolvedSettledCalls,
                account.resolvedStyle.bSmartLocalized.lowercased()
            )
    }

    private var strategySummary: String {
        "This account typically publishes %@ views over %@ horizons, with recurring focus on %@. Its public calls are most useful when the trigger, target and invalidation can be checked after publication."
            .bSmartLocalized(
                account.resolvedStyle.bSmartLocalized.lowercased(),
                account.horizon.bSmartLocalized.lowercased(),
                account.specialty.bSmartLocalized
            )
    }

    private func representativeTitle(_ update: SmartAccountUpdate) -> String {
        if let targetPrice = update.targetPrice {
            return "%@ view targeting %@".bSmartLocalized(update.ticker, currency(targetPrice))
        }
        return "%@ · %@ view".bSmartLocalized(update.ticker, update.direction.label)
    }

    private func settlementLabel(_ update: SmartAccountUpdate) -> String {
        guard let settlement = update.settlement else { return "Pending settlement".bSmartLocalized }
        if settlement.actualHit == true { return "Historical hit".bSmartLocalized }
        if settlement.actualHit == false { return "Historical miss".bSmartLocalized }
        return settlement.status.bSmartLocalized
    }

    private func settlementColor(_ update: SmartAccountUpdate) -> Color {
        switch update.settlement?.actualHit {
        case true: BSmartColor.brand
        case false: BSmartColor.bear
        case nil: BSmartColor.tertiaryText
        }
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(value < 100 ? 2 : 0)))
    }

    private func signedPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value / 100).formatted(
            .percent.precision(.fractionLength(1)).sign(strategy: .always())
        )
    }

    private func compactCount(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: String(format: "%.1fK", Double(value) / 1_000)
        default: value.formatted()
        }
    }
}

private struct SmartAccountEvidenceSparkline: View {
    let update: SmartAccountUpdate
    let evidence: SmartAccountPriceEvidence

    private var candles: [PriceCandle] {
        Array(evidence.candles.suffix(42))
    }

    var body: some View {
        Canvas { context, size in
            guard candles.count > 1 else { return }
            let closes = candles.map(\.close)
            guard let minimum = closes.min(), let maximum = closes.max() else { return }
            let span = max(maximum - minimum, max(maximum * 0.01, 1))

            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: size.height * 0.34))
            grid.addLine(to: CGPoint(x: size.width, y: size.height * 0.34))
            grid.move(to: CGPoint(x: 0, y: size.height * 0.72))
            grid.addLine(to: CGPoint(x: size.width, y: size.height * 0.72))
            context.stroke(grid, with: .color(BSmartColor.line), lineWidth: 0.6)

            func point(index: Int, price: Double) -> CGPoint {
                CGPoint(
                    x: CGFloat(index) / CGFloat(candles.count - 1) * size.width,
                    y: size.height - CGFloat((price - minimum) / span) * size.height
                )
            }

            var line = Path()
            for (index, candle) in candles.enumerated() {
                let position = point(index: index, price: candle.close)
                if index == 0 { line.move(to: position) } else { line.addLine(to: position) }
            }
            context.stroke(line, with: .color(BSmartColor.brand), lineWidth: 1.8)

            let markerIndex = candles.firstIndex(where: { $0.day >= evidence.viewDay }) ?? 0
            let marker = point(index: markerIndex, price: candles[markerIndex].close)
            context.fill(
                Path(ellipseIn: CGRect(x: marker.x - 3, y: marker.y - 3, width: 6, height: 6)),
                with: .color(update.direction.color)
            )
        }
        .accessibilityLabel("%@ price evidence".bSmartLocalized(update.ticker))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
