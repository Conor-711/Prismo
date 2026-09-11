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

struct TodayHomePager<Header: View, Content: View>: View {
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
                        TodayHomeSectionHeading(title: "Their market views", symbol: "quote.bubble.fill",
                                                accent: BSmartColor.sky, identifier: "today.market-views.heading")
                    }
                    .padding(.horizontal, BSmartSpacing.large)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
            }, tabs: { tabs }, content: content, refresh: refresh
        )
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tabRow(spacing: 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BSmartSpacing.large)
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BSmartColor.line).frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.home-tabs")
    }

    private func tabRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(TodayHomeSection.allCases) { section in
                Button {
                    withAnimation(reduceMotion ? nil : BSmartMotion.quick) { selection = section }
                } label: {
                    Text((section == .market ? "Market" : section.title).bSmartLocalized)
                        .font(.system(size: tabSize, weight: .semibold))
                        .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 44, minHeight: tabHeight, alignment: .leading)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottomLeading) {
                            if selection == section {
                                Capsule().fill(BSmartColor.pulse)
                                    .frame(width: 46, height: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityLabel(section.title.bSmartLocalized)
                .accessibilityIdentifier("today.tab.\(section.rawValue)")
            }
        }
    }

}
