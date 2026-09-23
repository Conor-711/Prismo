import SwiftUI

enum TodayHomeSection: String, CaseIterable, Identifiable {
    case portfolio, market, investors

    var id: String { rawValue }
    var title: String {
        switch self {
        case .portfolio: "Holdings & Tracking"
        case .market: "Market overview"
        case .investors: "Smart updates"
        }
    }
}

struct TodayHomeContent<Header: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: TodayHomeSection = .portfolio
    @ScaledMetric(relativeTo: .headline) private var tabHeight = 52.0
    @ScaledMetric(relativeTo: .headline) private var tabSize = 16.0
    @ViewBuilder let header: (CGSize) -> Header
    @ViewBuilder let content: (TodayHomeSection) -> Content
    let refresh: () async -> Void

    var body: some View {
        BSmartCollapsingPager(
            selection: $selection, sections: TodayHomeSection.allCases,
            pageIdentifier: { "today.page.\($0.rawValue)" },
            header: { viewport in
                VStack(alignment: .leading, spacing: 0) {
                    header(viewport)

                    VStack(alignment: .leading, spacing: 18) {
                        Rectangle().fill(BSmartColor.line).frame(height: 0.5)
                        TodayHomeSectionHeading(title: "Their market views",
                                                identifier: "today.market-views.heading")
                    }
                    .padding(.horizontal, BSmartSpacing.large)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }, tabs: { tabs }, content: { section in
                content(section)
                    .padding(.top, 12)
            }, refresh: refresh
        )
        // Let content scroll behind the floating dock through the bottom safe area.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 28) {
                    ForEach(TodayHomeSection.allCases) { section in
                        Button {
                            withAnimation(reduceMotion ? nil : BSmartMotion.quick) { selection = section }
                        } label: {
                            Text(section.title.bSmartLocalized)
                                .font(.system(size: tabSize, weight: .semibold))
                                .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                                .frame(minWidth: 44, minHeight: tabHeight, alignment: .leading)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottomLeading) {
                                    if selection == section {
                                        Capsule().fill(BSmartColor.pulse).frame(width: 46, height: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(section)
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                        .accessibilityIdentifier("today.tab.\(section.rawValue)")
                    }
                }
                .padding(.horizontal, BSmartSpacing.large)
            }
            .scrollIndicators(.hidden)
            .frame(height: tabHeight, alignment: .leading)
            .onChange(of: selection) { _, section in
                withAnimation(reduceMotion ? nil : BSmartMotion.quick) {
                    proxy.scrollTo(section, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.home-tabs")
    }
}
