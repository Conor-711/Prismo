import SwiftUI

/// A display-only preview: no market-order store, signing or balance mutation.
struct FeedDemoTradePreview: View {
    let item: TradeFeedItem
    let side: PaperTradeSide
    let close: () -> Void

    private var accent: Color { side == .short ? BSmartColor.bear : BSmartColor.bull }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BSmartAssetMark(ticker: item.opinion.ticker, size: 56)
                Text("Trade preview".bSmartLocalized).font(.title3.weight(.semibold))
                Label((side == .short ? "Short" : "Long").bSmartLocalized + " " + item.opinion.ticker,
                      systemImage: side == .short ? "arrow.down.right" : "arrow.up.right")
                    .foregroundStyle(accent).font(.title2.weight(.semibold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel((side == .short ? "Short" : "Long").bSmartLocalized + " " + item.opinion.ticker)
                    .accessibilityIdentifier("feed.demo.direction")
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
