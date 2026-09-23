import SwiftUI

enum SmartSection: String, CaseIterable, Identifiable {
    case accounts = "Smart Account"
    case money = "Smart Money"

    var id: Self { self }
    var key: String { self == .accounts ? "accounts" : "money" }
}

struct SmartHubTabs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: SmartSection
    let accountCount: Int
    let moneyCount: Int
    @ScaledMetric(relativeTo: .headline) private var tabHeight = 50.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(SmartSection.allCases) { section in
                        Button {
                            withAnimation(reduceMotion ? nil : BSmartMotion.quick) { selection = section }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(section.rawValue).font(.headline)
                                Text((section == .accounts ? accountCount : moneyCount).formatted())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(BSmartColor.tertiaryText)
                            }
                            .foregroundStyle(selection == section ? BSmartColor.primaryText : BSmartColor.tertiaryText)
                            .fixedSize(horizontal: true, vertical: true)
                            .frame(minHeight: tabHeight)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottomLeading) {
                                if selection == section {
                                    Capsule().fill(BSmartColor.brand).frame(width: 46, height: 3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(section)
                        .accessibilityLabel(section.rawValue)
                        .accessibilityIdentifier("smart.section.\(section.key)")
                        .accessibilityAddTraits(selection == section ? .isSelected : [])
                    }
                }
                .padding(.horizontal, BSmartSpacing.large)
            }
            .frame(height: tabHeight)
            .onChange(of: selection) { _, value in
                withAnimation(reduceMotion ? nil : BSmartMotion.quick) { proxy.scrollTo(value, anchor: .center) }
            }
        }
        .background(BSmartColor.ink)
        .overlay(alignment: .bottom) { Rectangle().fill(BSmartColor.line).frame(height: 0.5) }
        .accessibilityIdentifier("smart.tabs")
    }
}
