import SwiftUI

struct TradeLeveragePicker: View {
    @Binding var value: Int
    let maximum: Int
    let accent: Color
    let isLocked: Bool
    @State private var centeredValue: Int?

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(1...max(1, maximum), id: \.self) { multiple in
                            Button {
                                withAnimation(.snappy) { centeredValue = multiple }
                            } label: {
                                VStack(spacing: 7) {
                                    Rectangle().fill(BSmartColor.line).frame(width: 1, height: 8)
                                    Text("\(multiple)x")
                                        .font(.system(size: 23, weight: value == multiple ? .bold : .medium))
                                        .foregroundStyle(value == multiple ? accent : BSmartColor.tertiaryText)
                                        .monospacedDigit()
                                    Rectangle().fill(BSmartColor.line).frame(width: 1, height: 8)
                                }
                                .frame(width: 64, height: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(multiple)
                            .accessibilityAddTraits(value == multiple ? .isSelected : [])
                            .accessibilityIdentifier("trade.leverage.\(multiple)")
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max(0, (geometry.size.width - 64) / 2), for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centeredValue, anchor: .center)
                .scrollDisabled(isLocked)
                .disabled(isLocked)
                .overlay(alignment: .top) { Capsule().fill(accent).frame(width: 3, height: 8) }
                .overlay(alignment: .bottom) { Capsule().fill(accent).frame(width: 3, height: 8) }
            }
            .frame(height: 58)
            .accessibilityIdentifier("trade.leverage-picker")
            Text("Leverage".bSmartLocalized).font(.caption).foregroundStyle(BSmartColor.secondaryText)
        }
        .frame(maxWidth: 290)
        .onAppear { centeredValue = value }
        .onChange(of: value) { _, next in
            if centeredValue != next { centeredValue = next }
        }
        .onChange(of: centeredValue) { _, next in
            guard !isLocked, let next, next != value else { return }
            value = min(max(1, next), maximum)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}
