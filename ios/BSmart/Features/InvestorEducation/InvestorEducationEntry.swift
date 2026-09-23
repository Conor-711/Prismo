import SwiftUI

struct InvestorEducationEntry: View {
    private var isChinese: Bool { BSmartLocalization.isSimplifiedChinese }

    var body: some View {
        BSmartDetailNavigationLink(id: "investor-education") {
            InvestorEducationView()
        } label: {
            HStack(spacing: 4) {
                Text("Ranking questions?".bSmartLocalized)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("discovery.education.title")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .foregroundStyle(BSmartColor.onAccent).padding(.horizontal, isChinese ? 8 : 6).padding(.vertical, 8)
            .frame(maxWidth: isChinese ? 120 : 144)
            .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 6))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Questions about the rankings?".bSmartLocalized)
        .accessibilityIdentifier("discovery.education")
    }
}
