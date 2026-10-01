import SwiftUI

enum TodayHomeSection: String, CaseIterable, Identifiable {
    case activity, assets

    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: "Activity"
        case .assets: "Assets"
        }
    }
}

struct TodayHomeContent<Header: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: TodayHomeSection
    @ScaledMetric(relativeTo: .headline) private var tabHeight = 46.0
    @ViewBuilder let header: (CGSize) -> Header
    @ViewBuilder let content: (TodayHomeSection) -> Content
    let refresh: () async -> Void

    var body: some View {
        BSmartCollapsingPager(
            selection: $selection, sections: TodayHomeSection.allCases,
            extendsUnderHomeIndicator: true,
            pageIdentifier: { "today.page.\($0.rawValue)" },
            header: { viewport in header(viewport) },
            tabs: { tabs }, content: { section in
                content(section)
            }, refresh: refresh
        )
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(TodayHomeSection.allCases) { section in
                Button {
                    withAnimation(reduceMotion ? nil : BSmartMotion.quick) { selection = section }
                } label: {
                    Text(section.title.bSmartLocalized)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: tabHeight)
                        .overlay(alignment: .bottom) {
                            if selection == section {
                                BSmartColor.brand.frame(height: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bSmartPlain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityIdentifier("today.tab.\(section.rawValue)")
            }
        }
        .background(alignment: .bottom) { BSmartColor.line.frame(height: 0.5) }
        .padding(.horizontal, BSmartSpacing.large)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.home-tabs")
    }
}
