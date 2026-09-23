#if DEBUG
import SwiftUI

/// Explicit UI-test surface only. No auth, order submission or production demo entry.
struct FeedLayoutPreview: View {
    @State private var fixture: TradeFeedDemoData?
    @State private var selection = DiscoverSection.popular
    @State private var popularRefresh = 0

    var body: some View {
        NavigationStack {
            DiscoverContent(selection: $selection, content: { section in
                if let fixture {
                    if section == .popular {
                        PopularOpinionsView(demo: fixture, refresh: popularRefresh, isActive: selection == .popular)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(fixture.items) { item in
                                TradeFeedRow(item: item, onTradeDismiss: {}, demo: fixture)
                                    .padding(.vertical, 22)
                                Divider()
                            }
                        }
                    }
                }
            }, refresh: { popularRefresh += 1 })
            .navigationTitle("\("Discover".bSmartLocalized) · Demo").navigationBarTitleDisplayMode(.inline)
            .bSmartPage()
            .task { fixture = try? TradeFeedDemoData.load() }
        }
    }
}
#endif
