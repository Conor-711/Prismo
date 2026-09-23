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

struct SmartAccountCurrentViewsSection: View {
    let insights: SmartAccountProfileInsights
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current ticker views".bSmartLocalized).font(.title3.weight(.bold))
            if insights.currentTickerViews.isEmpty {
                Text("No active ticker view in the latest 30-day window.".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(insights.currentTickerViews.prefix(expanded ? insights.currentTickerViews.count : 5))) { item in
                        let update = item.update
                        HStack(spacing: 12) {
                            BSmartAssetMark(ticker: update.ticker, size: 34).bSmartTickerDestination(update.ticker)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(update.ticker).font(.subheadline.weight(.semibold))
                                if let target = update.targetPrice {
                                    Text("Target %@".bSmartLocalized(target.smartAccountProfileCurrency))
                                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                                }
                            }
                            Spacer()
                            BSmartDetailNavigationLink(id: "current-account-view-\(update.id)") {
                                SmartAccountEvidenceDetailView(update: update)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(update.direction.label.bSmartLocalized)
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(update.direction.color)
                                    Image(systemName: "chevron.right").font(.caption)
                                        .foregroundStyle(BSmartColor.tertiaryText)
                                }.frame(minHeight: 44)
                            }.buttonStyle(.plain)
                        }.padding(.vertical, 8)
                        Divider().overlay(BSmartColor.line)
                    }
                }
                if insights.currentTickerViews.count > 5 {
                    Button { expanded.toggle() } label: {
                        Label((expanded ? "Show less" : "View all").bSmartLocalized,
                              systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("smart.account.current-views.all")
                }
            }
        }.accessibilityIdentifier("smart.account.current-views")
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
        VStack(alignment: .leading, spacing: 18) {
            Text("Latest views".bSmartLocalized).font(.title3.weight(.bold))
            if displayedUpdates.isEmpty {
                Text("No recent published view is available for this account.".bSmartLocalized)
                    .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedUpdates.enumerated()), id: \.element.id) { index, update in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Circle().fill(index == 0 ? BSmartColor.brand : BSmartColor.line)
                                    .frame(width: 10, height: 10).padding(.top, 4)
                                Rectangle().fill(BSmartColor.line).frame(width: 1)
                            }.frame(width: 10)
                            BSmartDetailNavigationLink(id: "latest-account-view-\(update.id)") {
                                SmartAccountEvidenceDetailView(update: update)
                            } label: {
                                latestViewRow(update).padding(.bottom, 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(index == 0 ? "smart.account.latest-view.first" : "smart.account.latest-view.\(index)")
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let onViewAll, updates.count > displayedUpdates.count {
                Button(action: onViewAll) {
                    HStack {
                        Text("View all %@ views".bSmartLocalized(updates.count.formatted()))
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("smart.account.latest-views.all")
            }
        }.accessibilityIdentifier("smart.account.latest-views")
    }

    private func latestViewRow(_ update: SmartAccountUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(update.publishedAt.bSmartCompactDate)
                    .font(.caption.weight(.semibold)).foregroundStyle(BSmartColor.secondaryText)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(BSmartColor.tertiaryText)
            }
            Text(update.smartAccountProfileDisplayTitle)
                .font(.subheadline).lineSpacing(3).lineLimit(3)
                .foregroundStyle(BSmartColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                BSmartAssetMark(ticker: update.ticker, size: 24)
                Text(update.ticker).font(.caption.weight(.semibold))
                Text(update.direction.label.bSmartLocalized)
                    .foregroundStyle(update.direction.color)
                Spacer(minLength: 0)
                Text(update.smartAccountProfileDisplayHorizon)
                    .foregroundStyle(BSmartColor.secondaryText)
            }.font(.caption)
        }.contentShape(Rectangle())
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
        formatted(.bSmartDollars.precision(.fractionLength(self >= 100 ? 0 : 2)))
    }
}
