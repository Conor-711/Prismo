import SwiftUI

struct AIAssistantWelcome: View {
    let dataAsOf: Date?
    let ask: (AIAssistantPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.xxLarge) {
            VStack(alignment: .leading, spacing: BSmartSpacing.large) {
                AIAssistantAvatar(size: 56)
                Text("What should we look into?".bSmartLocalized)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, BSmartSpacing.xLarge)

            VStack(alignment: .leading, spacing: BSmartSpacing.small) {
                Text("Suggested questions".bSmartLocalized)
                    .font(.headline).padding(.bottom, BSmartSpacing.small)
                ForEach(AIAssistantPrompt.allCases) { prompt in
                    Button { ask(prompt) } label: {
                        HStack(alignment: .center, spacing: BSmartSpacing.medium) {
                            Image(systemName: prompt.symbol)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(BSmartColor.brand)
                                .frame(width: 28)
                            Text(prompt.title.bSmartLocalized)
                                .font(.body).multilineTextAlignment(.leading)
                                .foregroundStyle(BSmartColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                        .padding(.vertical, BSmartSpacing.large)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(prompt.title.bSmartLocalized)
                    .accessibilityIdentifier("ai.prompt.\(prompt.rawValue)")
                    Divider().overlay(BSmartColor.softDivider)
                }
            }
            if let dataAsOf {
                Label(dataAsOf.bSmartDataTimestamp, systemImage: "clock")
                    .font(.caption).foregroundStyle(BSmartColor.tertiaryText)
                    .accessibilityLabel("Evidence updated %@".bSmartLocalized(dataAsOf.bSmartDataTimestamp))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai.welcome")
    }
}

struct AIAssistantAvatar: View {
    let size: CGFloat

    var body: some View {
        Image("SmartMoneyBorderCollie")
            .resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}
