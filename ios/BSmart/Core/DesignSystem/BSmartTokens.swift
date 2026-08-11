import SwiftUI

enum BSmartColor {
    static let ink = Color(red: 9 / 255, green: 11 / 255, blue: 11 / 255)
    static let canvas = Color(red: 6 / 255, green: 8 / 255, blue: 8 / 255)
    static let surface = Color(red: 18 / 255, green: 21 / 255, blue: 20 / 255)
    static let elevated = Color(red: 24 / 255, green: 28 / 255, blue: 27 / 255)
    static let recessed = Color(red: 13 / 255, green: 16 / 255, blue: 15 / 255)
    static let line = Color(red: 38 / 255, green: 44 / 255, blue: 42 / 255)
    static let strongLine = Color(red: 58 / 255, green: 68 / 255, blue: 64 / 255)
    static let primaryText = Color(red: 247 / 255, green: 248 / 255, blue: 249 / 255)
    static let secondaryText = Color(red: 171 / 255, green: 179 / 255, blue: 188 / 255)
    static let tertiaryText = Color(red: 107 / 255, green: 116 / 255, blue: 126 / 255)
    static let brand = Color(red: 89 / 255, green: 224 / 255, blue: 190 / 255)
    /// High-attention Signal Pulse accent. Brand identity continues to use `brand`.
    static let pulse = Color(red: 212 / 255, green: 255 / 255, blue: 68 / 255)
    static let pulseInk = Color(red: 11 / 255, green: 16 / 255, blue: 8 / 255)
    static let electric = Color(red: 92 / 255, green: 118 / 255, blue: 255 / 255)
    static let sky = Color(red: 104 / 255, green: 183 / 255, blue: 255 / 255)
    static let bear = Color(red: 255 / 255, green: 92 / 255, blue: 108 / 255)
    static let gold = Color(red: 255 / 255, green: 202 / 255, blue: 75 / 255)
    static let orange = Color(red: 255 / 255, green: 145 / 255, blue: 92 / 255)
}

enum BSmartSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
    static let xxxLarge: CGFloat = 40
}

enum BSmartRadius {
    static let control: CGFloat = 4
    static let card: CGFloat = 8
}

enum BSmartMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static let standard = Animation.easeInOut(duration: 0.22)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)
}

extension View {
    func bSmartSurface(padding: CGFloat = BSmartSpacing.large) -> some View {
        self
            .padding(padding)
            .background(BSmartColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(BSmartColor.line, lineWidth: 0.5)
            }
    }

    func bSmartPage() -> some View {
        self
            .foregroundStyle(BSmartColor.primaryText)
            .background(BSmartColor.ink.ignoresSafeArea())
            .tint(BSmartColor.brand)
    }

    func bSmartPanel(
        padding: CGFloat = BSmartSpacing.medium,
        fill: Color = BSmartColor.surface,
        border: Color = BSmartColor.line
    ) -> some View {
        self
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BSmartRadius.card, style: .continuous)
                    .stroke(border, lineWidth: 0.6)
            }
    }
}
