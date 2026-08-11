import SwiftUI

struct DailyDigestPreviewCard: View {
    let signals: [PersonalizedPortfolioSignal]

    private var urgentCount: Int {
        signals.filter {
            $0.personalization.attention == .priority || $0.signal.kind == .divergence
        }.count
    }

    private var confirmedCount: Int {
        signals.filter { $0.signal.kind == .confirmation }.count
    }

    var body: some View {
        HStack(alignment: .center, spacing: BSmartSpacing.medium) {
            Image(systemName: "sun.max.fill")
                .font(.headline)
                .foregroundStyle(BSmartColor.ink)
                .frame(width: 38, height: 38)
                .background(BSmartColor.gold)
                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Daily portfolio brief")
                    .font(.subheadline.weight(.bold))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: BSmartSpacing.small)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .bSmartSurface(padding: BSmartSpacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily portfolio brief. %@".bSmartLocalized(summary))
        .accessibilityIdentifier("today.daily-digest")
    }

    private var summary: String {
        guard !signals.isEmpty else { return "No material changes for your tracked stocks.".bSmartLocalized }
        var parts: [String] = []
        if urgentCount > 0 { parts.append("%d need attention".bSmartLocalized(urgentCount)) }
        if confirmedCount > 0 { parts.append("%d confirmed".bSmartLocalized(confirmedCount)) }
        if parts.isEmpty { parts.append("%d monitored changes".bSmartLocalized(signals.count)) }
        return parts.joined(separator: " · ")
    }
}

struct DailyDigestView: View {
    @EnvironmentObject private var model: AppModel
    @State private var didTrackOpen = false

    private var signals: [PersonalizedPortfolioSignal] { model.personalizedDailyDigestSignals }
    private var attentionSignals: [PersonalizedPortfolioSignal] {
        signals.filter {
            $0.personalization.attention == .priority || $0.signal.kind == .divergence
        }
    }
    private var confirmationSignals: [PersonalizedPortfolioSignal] {
        let attentionIDs = Set(attentionSignals.map(\.id))
        return signals.filter { !attentionIDs.contains($0.id) && $0.signal.kind == .confirmation }
    }
    private var developingSignals: [PersonalizedPortfolioSignal] {
        let attentionIDs = Set(attentionSignals.map(\.id))
        let confirmationIDs = Set(confirmationSignals.map(\.id))
        return signals.filter {
            !attentionIDs.contains($0.id) && !confirmationIDs.contains($0.id)
        }
    }
    private var noCapitalCoverageCount: Int {
        signals.filter { $0.signal.smartMoneyCoverage == .unavailable }.count
    }
    private var digestDate: Date {
        model.dailyDigestSnapshot?.generatedAt
            ?? signals.map(\.signal.dataAsOf).max()
            ?? model.lastDataRefreshAt
            ?? Date()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                header
                overview

                if signals.isEmpty {
                    VStack(spacing: BSmartSpacing.medium) {
                        Image(systemName: "checkmark.seal")
                            .font(.title2)
                            .foregroundStyle(BSmartColor.brand)
                        Text("No material changes")
                            .font(.headline)
                        Text("bSmart is still monitoring your positions and watchlist.")
                            .font(.subheadline)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .bSmartSurface()
                } else {
                    signalSection(
                        title: "Needs attention",
                        detail: "Divergence or material risk",
                        symbol: "exclamationmark.triangle.fill",
                        color: BSmartColor.bear,
                        signals: attentionSignals
                    )
                    signalSection(
                        title: "Views and capital agree",
                        detail: "Independent evidence moved together",
                        symbol: "checkmark.seal.fill",
                        color: BSmartColor.brand,
                        signals: confirmationSignals
                    )
                    signalSection(
                        title: "Still developing",
                        detail: "One side moved first or coverage is incomplete",
                        symbol: "waveform.path.ecg",
                        color: BSmartColor.gold,
                        signals: developingSignals
                    )
                }

                Label(
                    "This brief summarizes observable evidence changes. It is not a trade instruction.",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.caption)
                .foregroundStyle(BSmartColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(BSmartSpacing.large)
            .padding(.bottom, BSmartSpacing.xLarge)
        }
        .background(BSmartColor.ink)
        .accessibilityIdentifier("daily-digest.screen")
        .navigationTitle("Daily brief")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didTrackOpen else { return }
            didTrackOpen = true
            model.trackDailyDigestOpened()
        }
        .bSmartPage()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text(digestDate.bSmartDigestDate)
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.brand)
                .textCase(.uppercase)
            Text("What changed for you")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("A concise read of Smart Account views, public onchain capital and where they disagree.")
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var overview: some View {
        HStack(spacing: 0) {
            digestMetric(value: "\(signals.count)", label: "Changes", color: BSmartColor.primaryText)
            Divider().overlay(BSmartColor.line)
            digestMetric(value: "\(attentionSignals.count)", label: "Attention", color: BSmartColor.bear)
            Divider().overlay(BSmartColor.line)
            digestMetric(value: "\(confirmationSignals.count)", label: "Confirmed", color: BSmartColor.brand)
            Divider().overlay(BSmartColor.line)
            digestMetric(value: "\(noCapitalCoverageCount)", label: "No capital", color: BSmartColor.gold)
        }
        .frame(maxWidth: .infinity)
        .bSmartSurface(padding: 0)
    }

    private func digestMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(BSmartColor.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    @ViewBuilder
    private func signalSection(
        title: String,
        detail: String,
        symbol: String,
        color: Color,
        signals: [PersonalizedPortfolioSignal]
    ) -> some View {
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                BSmartSectionHeader(title: title, detail: detail)

                ForEach(Array(signals.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(BSmartColor.line) }
                    NavigationLink {
                        EventDetailView(signal: item.signal)
                    } label: {
                        HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                            Image(systemName: symbol)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color)
                                .frame(width: 24, height: 24)
                                .background(color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.signal.ticker)
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(color)
                                    Text(item.signal.kind.label)
                                        .font(.caption2)
                                        .foregroundStyle(BSmartColor.tertiaryText)
                                }
                                Text(item.signal.title.bSmartLocalized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BSmartColor.primaryText)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.personalization.localizedImpactText(for: item.signal))
                                    .font(.caption)
                                    .foregroundStyle(BSmartColor.secondaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: BSmartSpacing.xSmall)
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
}
