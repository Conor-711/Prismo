import SwiftUI

struct IntelligenceMethodView: View {
    let isUsingDemoData: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                if isUsingDemoData {
                    Label("This build uses demonstration evidence and events.", systemImage: "testtube.2")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BSmartColor.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .bSmartSurface()
                }

                methodSection(
                    title: "Smart Account",
                    symbol: SignalEvidenceSource.smartAccount.symbol,
                    body: "Public investment creators from X, YouTube, Reddit, Xueqiu and Toss are evaluated from their historical calls. Score represents the strength of observed historical evidence and market consensus around an account; it is not a guarantee of future performance."
                )

                methodSection(
                    title: "Smart Money",
                    symbol: SignalEvidenceSource.smartMoney.symbol,
                    body: "bSmart scores public capital accounts in tokenized US equity markets and reports observed entries, adds, reductions and exits when coverage passes the minimum evidence threshold. Consumer-facing names are stable aliases, not verified owner identities."
                )

                methodSection(
                    title: "Evidence relationships",
                    symbol: "arrow.left.arrow.right",
                    body: "Confirmation means account views and qualifying capital moved in the same direction. Divergence means they moved in opposing directions. Account leads and Money leads identify which evidence changed before the other side was available."
                )

                methodSection(
                    title: "Coverage",
                    symbol: "chart.bar.doc.horizontal",
                    body: "Every event carries an as-of time, data status and limitations. Missing Smart Money evidence is shown as unavailable rather than treated as neutral. Delayed or insufficient coverage cannot be promoted into a confirmed relationship."
                )
            }
            .padding(BSmartSpacing.large)
        }
        .background(BSmartColor.ink)
        .navigationTitle("Data & methodology")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("methodology.screen")
        .bSmartPage()
    }

    private func methodSection(title: String, symbol: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(BSmartColor.brand)

            Text(body.bSmartLocalized)
                .font(.subheadline)
                .foregroundStyle(BSmartColor.secondaryText)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bSmartSurface()
    }
}
