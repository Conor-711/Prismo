import SwiftUI

extension View {
    func bSmartInputSurface(focused: Bool = false) -> some View {
        background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(focused ? BSmartColor.brand : BSmartColor.inputOutline,
                            lineWidth: focused ? 1.5 : 0.75)
                    .allowsHitTesting(false)
            }
    }

    func bSmartActionSurface(fill: Color = BSmartColor.brand, cornerRadius: CGFloat = 8) -> some View {
        modifier(BSmartActionSurface(fill: fill, cornerRadius: cornerRadius))
    }
}

private struct BSmartActionSurface: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let fill: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let subdued = !isEnabled && colorScheme == .light
        content
            .foregroundStyle(subdued ? BSmartColor.tertiaryText : BSmartColor.onAccent)
            .tint(subdued ? BSmartColor.tertiaryText : BSmartColor.onAccent)
            .background(subdued ? BSmartColor.disabledControl : fill,
                        in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
