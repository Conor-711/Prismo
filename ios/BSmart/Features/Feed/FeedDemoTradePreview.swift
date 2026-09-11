import SwiftUI

/// A display-only preview: no market-order store, signing or balance mutation.
struct FeedDemoTradePreview: View {
    let request: FeedQuickTradeRequest
    let close: () -> Void

    private var accent: Color { request.choice.side == .short ? BSmartColor.bear : BSmartColor.bull }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BSmartAssetMark(ticker: request.item.opinion.ticker, size: 56)
                Text("Trade preview".bSmartLocalized).font(.title3.weight(.semibold))
                Label((request.choice.side == .short ? "Short" : "Long").bSmartLocalized + " " + request.item.opinion.ticker,
                      systemImage: request.choice.side == .short ? "arrow.down.right" : "arrow.up.right")
                    .foregroundStyle(accent).font(.title2.weight(.semibold))
                    .accessibilityIdentifier("feed.demo.direction")
                VStack(spacing: 8) {
                    Text("Position value".bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                    Text("$\(request.choice.dollars)").font(.largeTitle.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("feed.demo.notional")
                }
                Button("Done".bSmartLocalized, action: close)
                    .font(.headline).foregroundStyle(BSmartColor.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(accent, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("feed.demo.done")
            }
            .padding(24)
            .navigationTitle("Demo").navigationBarTitleDisplayMode(.inline)
            .bSmartPage()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed.demo.preview")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
