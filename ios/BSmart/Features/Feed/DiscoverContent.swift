import SwiftUI

struct DiscoverContent<Content: View>: View {
    @Environment(\.bSmartFloatingNavigationFrame) private var floatingNavigationFrame
    @ViewBuilder let content: () -> Content
    let refresh: () async -> Void

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 0) {
                    content()
                        .padding(BSmartSpacing.large)
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                    Color.clear.frame(height: BSmartFloatingNavigationLayout.bottomSpacing(
                        viewport: viewport.frame(in: .global), navigationFrame: floatingNavigationFrame
                    ))
                }
            }
            .refreshable { await refresh() }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("discover.ranking.page")
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
}
