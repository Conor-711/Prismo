import SwiftUI

struct RiskDisclosureView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                disclosure(
                    title: "Research context",
                    symbol: "doc.text.magnifyingglass",
                    body: "bSmart organizes public evidence for research. It does not provide personalized investment advice, execute trades or guarantee an outcome."
                )

                disclosure(
                    title: "Incomplete coverage",
                    symbol: "circle.dotted",
                    body: "Social and on-chain sources can be delayed, unavailable or incomplete. A missing observation does not prove that an account or wallet took no action."
                )

                disclosure(
                    title: "Score limitations",
                    symbol: "gauge.with.dots.needle.33percent",
                    body: "Historical Score is based on observable calls and market outcomes. Rankings can change and do not predict future returns."
                )

                disclosure(
                    title: "Market risk",
                    symbol: "waveform.path.ecg",
                    body: "Equities and tokenized equity derivatives can lose value rapidly. Verify primary sources and consider your own objectives, horizon and risk capacity before acting."
                )
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Risk disclosure")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("risk-disclosure.screen")
        .bSmartPage()
    }

    private func disclosure(title: String, symbol: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            Label(title, systemImage: symbol)
                .font(.headline)

            Text(body.bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bSmartSurface()
    }
}
