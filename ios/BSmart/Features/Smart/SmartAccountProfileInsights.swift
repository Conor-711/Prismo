import SwiftUI

struct SmartAccountCurrentTickerView: Identifiable, Hashable {
    var id: String { update.ticker.uppercased() }
    let update: SmartAccountUpdate
}

struct SmartAccountProfileInsights {
    let account: SmartAccountProfile
    let updates: [SmartAccountUpdate]

    init(
        account: SmartAccountProfile,
        evidenceUpdates: [SmartAccountUpdate],
        recentUpdates: [SmartAccountUpdate]
    ) {
        self.account = account

        var updatesByID = Dictionary(uniqueKeysWithValues: recentUpdates.map { ($0.id, $0) })
        for update in evidenceUpdates {
            updatesByID[update.id] = update
        }
        updates = updatesByID.values.sorted { $0.publishedAt > $1.publishedAt }
    }

    var latestViews: [SmartAccountUpdate] {
        guard let anchor = updates.first?.publishedAt,
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: anchor)
        else { return [] }
        return updates.filter { $0.publishedAt >= cutoff }
    }

    var currentTickerViews: [SmartAccountCurrentTickerView] {
        guard let anchor = latestViews.first?.publishedAt,
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: anchor)
        else { return [] }

        var seenTickers = Set<String>()
        var current: [SmartAccountCurrentTickerView] = []
        for update in latestViews where update.publishedAt >= cutoff {
            let ticker = update.ticker.uppercased()
            guard seenTickers.insert(ticker).inserted else { continue }
            guard update.lifecycle != .closed, update.lifecycle != .invalidated else { continue }
            current.append(SmartAccountCurrentTickerView(update: update))
        }
        return current
    }

    var bullishTickerViews: [SmartAccountCurrentTickerView] {
        currentTickerViews.filter { $0.update.direction == .bullish }
    }

    var bearishTickerViews: [SmartAccountCurrentTickerView] {
        currentTickerViews.filter { $0.update.direction == .bearish }
    }

    var otherTickerViews: [SmartAccountCurrentTickerView] {
        currentTickerViews.filter { $0.update.direction == .neutral || $0.update.direction == .mixed }
    }

    var latestViewDate: Date? { updates.first?.publishedAt }
}

struct SmartAccountInvestorProfileSection: View {
    let account: SmartAccountProfile

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Investor profile",
                detail: "Demonstrated characteristics from ranked public calls"
            )

            HStack(spacing: 0) {
                capability(
                    icon: "square.grid.2x2.fill",
                    label: "Best field",
                    value: account.specialty,
                    color: BSmartColor.brand
                )
                Divider().overlay(BSmartColor.line)
                capability(
                    icon: "clock.fill",
                    label: "Best horizon",
                    value: account.horizon,
                    color: BSmartColor.sky
                )
                Divider().overlay(BSmartColor.line)
                capability(
                    icon: "scope",
                    label: "Investment style",
                    value: account.resolvedStyle,
                    color: BSmartColor.gold
                )
            }

            Divider().overlay(BSmartColor.line)

            HStack(spacing: BSmartSpacing.medium) {
                profileMetric(label: "Covered tickers", value: account.resolvedCoveredTickers.formatted())
                profileMetric(label: "Settled calls", value: account.resolvedSettledCalls.formatted())
                profileMetric(label: "Active days", value: account.resolvedActiveDays.formatted())
            }

            if !account.resolvedTopTickers.isEmpty {
                VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                    Text("Strongest ticker coverage".bSmartLocalized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BSmartColor.tertiaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BSmartSpacing.small) {
                            ForEach(account.resolvedTopTickers, id: \.self) { ticker in
                                HStack(spacing: 6) {
                                    BSmartAssetMark(ticker: ticker, size: 24)
                                    Text(ticker)
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(BSmartColor.primaryText)
                                }
                                .padding(.horizontal, BSmartSpacing.small)
                                .frame(minHeight: 34)
                                .background(BSmartColor.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
        .bSmartSurface()
        .accessibilityIdentifier("smart.account.investor-profile")
    }

    private func capability(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(color)
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
            Text(value.bSmartLocalized)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private func profileMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.black))
                .foregroundStyle(BSmartColor.primaryText)
                .monospacedDigit()
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SmartAccountCurrentViewsSection: View {
    let insights: SmartAccountProfileInsights

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Current ticker views",
                detail: "Latest active view per ticker · 30D"
            )

            if insights.currentTickerViews.isEmpty {
                Label("No active ticker view in the latest 30-day window.", systemImage: "clock.badge.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
            } else {
                HStack(spacing: 0) {
                    directionMetric(
                        label: "Bullish",
                        count: insights.bullishTickerViews.count,
                        color: BSmartColor.brand
                    )
                    Divider().overlay(BSmartColor.line)
                    directionMetric(
                        label: "Bearish",
                        count: insights.bearishTickerViews.count,
                        color: BSmartColor.bear
                    )
                    Divider().overlay(BSmartColor.line)
                    directionMetric(
                        label: "Neutral / mixed",
                        count: insights.otherTickerViews.count,
                        color: BSmartColor.secondaryText
                    )
                }

                Divider().overlay(BSmartColor.line)

                tickerStrip(
                    title: "Bullish tickers",
                    views: insights.bullishTickerViews,
                    color: BSmartColor.brand
                )
                tickerStrip(
                    title: "Bearish tickers",
                    views: insights.bearishTickerViews,
                    color: BSmartColor.bear
                )
                if !insights.otherTickerViews.isEmpty {
                    tickerStrip(
                        title: "Neutral / mixed",
                        views: insights.otherTickerViews,
                        color: BSmartColor.secondaryText
                    )
                }
            }
        }
        .bSmartSurface()
        .accessibilityIdentifier("smart.account.current-views")
    }

    private func directionMetric(label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count.formatted())
                .font(.title3.weight(.black))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label.bSmartLocalized)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.small)
    }

    @ViewBuilder
    private func tickerStrip(
        title: String,
        views: [SmartAccountCurrentTickerView],
        color: Color
    ) -> some View {
        if !views.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                Text(title.bSmartLocalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BSmartSpacing.small) {
                        ForEach(views) { view in
                            HStack(spacing: 6) {
                                BSmartAssetMark(ticker: view.update.ticker, size: 24)
                                Text(view.update.ticker)
                                    .font(.caption.weight(.black))
                                if let target = view.update.targetPrice {
                                    Text(target.smartAccountProfileCurrency)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(BSmartColor.secondaryText)
                                        .monospacedDigit()
                                }
                            }
                            .foregroundStyle(BSmartColor.primaryText)
                            .padding(.horizontal, BSmartSpacing.small)
                            .frame(minHeight: 34)
                            .background(color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous)
                                    .stroke(color.opacity(0.45), lineWidth: 0.75)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SmartAccountLatestViewsSection: View {
    let updates: [SmartAccountUpdate]
    var limit: Int? = nil
    var onViewAll: (() -> Void)? = nil

    private var displayedUpdates: [SmartAccountUpdate] {
        guard let limit else { return updates }
        return Array(updates.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(
                title: "Latest views",
                detail: "Most recent published calls, not historical representatives"
            )

            if displayedUpdates.isEmpty {
                Text("No recent published view is available for this account.")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
            } else {
                ForEach(Array(displayedUpdates.enumerated()), id: \.element.id) { index, update in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    BSmartDetailNavigationLink(id: "latest-account-view-\(update.id)") {
                        SmartAccountEvidenceDetailView(update: update)
                    } label: {
                        latestViewRow(update)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        index == 0 ? "smart.account.latest-view.first" : "smart.account.latest-view.\(index)"
                    )
                }
            }

            if let onViewAll, updates.count > displayedUpdates.count {
                Button(action: onViewAll) {
                    HStack {
                        Text("View all %@ views".bSmartLocalized(updates.count.formatted()))
                            .font(.caption.weight(.bold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.black))
                    }
                    .foregroundStyle(BSmartColor.brand)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("smart.account.latest-views.all")
            }
        }
        .bSmartSurface()
    }

    private func latestViewRow(_ update: SmartAccountUpdate) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            HStack(spacing: BSmartSpacing.small) {
                BSmartAssetMark(ticker: update.ticker, size: 30)
                Text(update.ticker)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(BSmartColor.primaryText)
                BSmartTag(text: update.direction.label, color: update.direction.color)
                BSmartTag(text: update.lifecycle.label, color: update.direction.color)
                Spacer(minLength: BSmartSpacing.xSmall)
                Text(update.publishedAt.bSmartRelativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(BSmartColor.tertiaryText)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }

            Text(update.smartAccountProfileDisplayTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BSmartColor.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BSmartSpacing.medium) {
                Label(update.smartAccountProfileDisplayHorizon, systemImage: "clock")
                if let target = update.targetPrice {
                    Label(
                        "Target %@".bSmartLocalized(target.smartAccountProfileCurrency),
                        systemImage: "scope"
                    )
                }
                Text(update.platform)
                Spacer(minLength: 0)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(BSmartColor.secondaryText)
        }
        .contentShape(Rectangle())
    }
}

private extension SmartAccountUpdate {
    var smartAccountProfileDisplayTitle: String {
        let localized: [String?]
        if BSmartLocalization.isSimplifiedChinese {
            localized = [activityTitleZH, activityTitle, translatedTextZH, translatedText]
        } else {
            localized = [activityTitleEN, activityTitle, translatedTextEN, translatedText]
        }
        return localized.compactMap(\.smartAccountProfileNonBlank).first
            ?? originalText.smartAccountProfileNonBlank
            ?? thesis
    }

    var smartAccountProfileDisplayHorizon: String {
        horizon.lowercased() == "unknown" ? "Horizon unavailable".bSmartLocalized : horizon.bSmartLocalized
    }
}

private extension Optional where Wrapped == String {
    var smartAccountProfileNonBlank: String? {
        guard let rawValue = self else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private extension Double {
    var smartAccountProfileCurrency: String {
        formatted(.currency(code: "USD").precision(.fractionLength(self >= 100 ? 0 : 2)))
    }
}
