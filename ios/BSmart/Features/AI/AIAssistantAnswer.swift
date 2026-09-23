import SwiftUI

struct AIAssistantAnswer: View {
    @EnvironmentObject private var model: AppModel
    let response: AIAssistantResponse
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.large) {
            HStack(spacing: BSmartSpacing.small) {
                AIAssistantAvatar(size: 26)
                Text("Mr Collie").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let date = response.dataAsOf {
                    Text(date.bSmartDataTimestamp).font(.caption)
                        .foregroundStyle(BSmartColor.tertiaryText)
                }
            }
            Text(response.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ai.response")
            Text(response.summary)
                .font(.body).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let context = response.context {
                Text(context).font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, BSmartSpacing.medium)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(BSmartColor.brand.opacity(0.5)).frame(width: 2)
                    }
            }
            if let notice {
                Label(notice, systemImage: "wifi.exclamationmark")
                    .font(.footnote).foregroundStyle(BSmartColor.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !response.evidence.isEmpty { evidence }
            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                Text("Next research step".bSmartLocalized).font(.subheadline.weight(.semibold))
                Text(response.nextStep).font(.body).lineSpacing(4)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(BSmartColor.primaryText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.message.assistant")
    }

    private var evidence: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(response.evidence) { item in
                    VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Label(item.source.bSmartLocalized, systemImage: item.symbol)
                                if let metric = item.metric { Spacer(minLength: 8); Text(metric).monospacedDigit() }
                            }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.source.bSmartLocalized, systemImage: item.symbol)
                                if let metric = item.metric { Text(metric).monospacedDigit() }
                            }
                        }
                        .font(.caption.weight(.medium)).foregroundStyle(BSmartColor.brand)
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text(item.detail).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, BSmartSpacing.medium)
                    Divider().overlay(BSmartColor.softDivider)
                }
            }
        } label: {
            Label("%d evidence sources".bSmartLocalized(response.evidence.count), systemImage: "text.book.closed")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .tint(BSmartColor.brand)
        .accessibilityIdentifier("ai.evidence")
    }

    @ViewBuilder
    private var actions: some View {
        if let signal = response.signal {
            BSmartDetailNavigationLink(id: "ai-signal-\(signal.id)") {
                EventDetailView(signal: signal)
            } label: { actionLabel("Open event evidence") }
            .buttonStyle(.plain)
            .accessibilityLabel("Open event evidence".bSmartLocalized)
        } else if let ticker = response.ticker,
                  let intelligence = model.intelligence.first(where: {
                      $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame
                  }) {
            BSmartDetailNavigationLink(id: "ai-ticker-\(intelligence.ticker)") {
                TickerIntelligenceView(ticker: intelligence)
            } label: { actionLabel("Open ticker research") }
            .buttonStyle(.plain)
            .accessibilityLabel("Open ticker research".bSmartLocalized)
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: BSmartSpacing.small) {
            Text(title.bSmartLocalized).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right").font(.subheadline.weight(.medium))
        }
        .foregroundStyle(BSmartColor.brand)
        .padding(.horizontal, BSmartSpacing.medium)
        .padding(.vertical, BSmartSpacing.medium)
        .frame(minHeight: 48)
        .background(BSmartColor.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: BSmartRadius.card))
        .contentShape(Rectangle())
    }
}
