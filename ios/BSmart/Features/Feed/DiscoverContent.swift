import SwiftUI

enum DiscoverSection: String, CaseIterable {
    case popular, latest

    var title: String {
        switch self {
        case .popular: "Trending"
        case .latest: "Latest trades"
        }
    }
}

struct DiscoverContent<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: DiscoverSection
    @ScaledMetric(relativeTo: .headline) private var tabSize = 17.0
    @ScaledMetric(relativeTo: .headline) private var tabHeight = 48.0
    @ViewBuilder let content: (DiscoverSection) -> Content
    let refresh: () async -> Void

    var body: some View {
        BSmartCollapsingPager(
            selection: $selection, sections: DiscoverSection.allCases,
            pageIdentifier: { "discover.page.\($0.rawValue)" },
            header: { _ in EmptyView() }, tabs: { tabs }, content: content, refresh: refresh
        )
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tabs: some View {
        HStack(spacing: 32) {
            ForEach(DiscoverSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(reduceMotion ? nil : BSmartMotion.quick) { selection = section }
                } label: {
                    Text(section.title.bSmartLocalized)
                        .font(.system(size: tabSize, weight: .semibold))
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 44, minHeight: tabHeight, alignment: .leading)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottomLeading) {
                            if selection == section {
                                Capsule().fill(BSmartColor.brand).frame(width: 46, height: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityIdentifier("discover.tab.\(section.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BSmartSpacing.large)
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.mode")
    }
}
