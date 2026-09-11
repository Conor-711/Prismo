import SwiftUI

struct TradeSlideToConfirm: View {
    let title: String
    let accent: Color
    let isEnabled: Bool
    let action: () -> Void
    var identifier = "trading-order.submit"
    @State private var translation: CGFloat = 0
    @State private var submitted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 60)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? accent.opacity(0.15) : BSmartColor.recessed)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isEnabled ? accent : BSmartColor.tertiaryText)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .padding(.leading, 62).padding(.trailing, 12)
                    .frame(maxWidth: .infinity)
                    .opacity(max(0, 1 - translation / travel * 2))
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isEnabled ? BSmartColor.onAccent : BSmartColor.tertiaryText)
                    .frame(width: 50, height: 50)
                    .background(isEnabled ? accent : BSmartColor.elevated, in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: 5 + translation)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .global)
                            .onChanged { value in
                                guard isEnabled, !submitted else { return }
                                translation = min(travel, max(0, value.translation.width))
                            }
                            .onEnded { value in
                                guard isEnabled, !submitted else { reset(); return }
                                if value.translation.width >= travel * 0.92 {
                                    confirm()
                                }
                                reset()
                            }
                    )
            }
        }
        .frame(height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isEnabled ? "" : "Unavailable".bSmartLocalized)
        .accessibilityAction { if isEnabled { confirm(); reset() } }
        .accessibilityIdentifier(identifier)
        .onChange(of: isEnabled) { _, _ in reset() }
    }

    private func confirm() {
        guard !submitted else { return }
        submitted = true
        action()
        submitted = false
    }

    private func reset() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { translation = 0 }
    }
}
