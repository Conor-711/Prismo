import SwiftUI

struct SubjectOptionInterpretationView: View {
    let event: TodaySubjectEvent
    @State private var showsExplanation = false

    var body: some View {
        if let interpretation = SubjectOptionInterpretation(event: event) {
            HStack(spacing: 0) {
                Text(interpretation.titleKey.bSmartLocalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint(interpretation))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("subject.option-interpretation.title.\(event.id)")
                Button { showsExplanation = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BSmartColor.secondaryText)
                        .offset(y: -5)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bSmartPlain)
                .frame(width: 22, height: 22)
                .accessibilityLabel("Explain exposure".bSmartLocalized)
                .accessibilityIdentifier("subject.option-interpretation.info.\(event.id)")
                .popover(isPresented: $showsExplanation, arrowEdge: .top) {
                    explanation(interpretation)
                        .presentationCompactAdaptation(.popover)
                        .presentationBackground(BSmartColor.ink)
                }
            }
            .frame(minHeight: 22, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subject.option-interpretation.\(event.id)")
        }
    }

    private func explanation(_ interpretation: SubjectOptionInterpretation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(interpretation.titleKey.bSmartLocalized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BSmartColor.primaryText)
                Spacer(minLength: 0)
                Button { showsExplanation = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bSmartToolbar)
                .accessibilityLabel("Close".bSmartLocalized)
                .accessibilityIdentifier("subject.option-interpretation.close.\(event.id)")
            }
            Text(interpretation.explanationKey.bSmartLocalized)
                .font(.system(size: 12))
            Text("Not the investor's overall outlook".bSmartLocalized)
            Text("13F reports quarter-end holdings, not real-time trades; unreported short positions prevent reconstruction of the full strategy.".bSmartLocalized)
            Text("Underlying returns are not option returns. Strike, expiry, premium and volatility affect option outcomes.".bSmartLocalized)
            Text("Sync underlying only, not the option".bSmartLocalized)
            Link("SEC: Form 13F".bSmartLocalized,
                 destination: URL(string: "https://www.sec.gov/rules-regulations/staff-guidance/frequently-asked-questions-about-form-13f")!)
                .foregroundStyle(BSmartColor.brand)
                .buttonStyle(.bSmartPlain)
        }
        .font(.system(size: 11))
        .foregroundStyle(BSmartColor.secondaryText)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .background(BSmartColor.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("subject.option-interpretation.explanation.\(event.id)")
    }

    private func tint(_ value: SubjectOptionInterpretation) -> Color {
        guard value.change == .added || value.change == .held else { return BSmartColor.secondaryText }
        switch value.kind {
        case .call: return BSmartColor.bull
        case .put: return BSmartColor.bear
        case .unknown: return BSmartColor.secondaryText
        }
    }
}
