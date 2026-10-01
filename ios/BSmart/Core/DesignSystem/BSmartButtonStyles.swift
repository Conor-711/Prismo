import SwiftUI

struct BSmartPlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .transaction { $0.animation = nil }
    }
}

struct BSmartActionButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(prominent ? BSmartColor.onAccent : BSmartColor.primaryText)
            .background(prominent ? BSmartColor.brand : BSmartColor.elevated,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(prominent ? Color.clear : BSmartColor.line, lineWidth: 0.75)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .transaction { $0.animation = nil }
    }
}

struct BSmartToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(BSmartColor.primaryText)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line, lineWidth: 0.75)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .transaction { $0.animation = nil }
    }
}

extension ButtonStyle where Self == BSmartPlainButtonStyle {
    static var bSmartPlain: Self { Self() }
}

extension ButtonStyle where Self == BSmartActionButtonStyle {
    static var bSmartPrimary: Self { Self(prominent: true) }
    static var bSmartSecondary: Self { Self(prominent: false) }
}

extension ButtonStyle where Self == BSmartToolbarButtonStyle {
    static var bSmartToolbar: Self { Self() }
}
