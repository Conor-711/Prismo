import SwiftUI

struct AccountBrandHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("BSmartWordmark")
            .renderingMode(colorScheme == .dark ? .template : .original)
            .resizable().scaledToFit()
            .foregroundStyle(BSmartColor.brand)
            .frame(maxWidth: 224)
            .accessibilityLabel("bSmart")
            .frame(maxWidth: .infinity)
    }
}

struct AccountGoogleButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        AccountProviderButton(provider: .google, isBusy: isBusy, action: action)
    }
}

struct AccountActionRow: View {
    let title: String
    let symbol: String
    var destructive = false
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(destructive ? BSmartColor.bear : BSmartColor.brand)
            Text(title.bSmartLocalized).font(.body.weight(.medium))
                .foregroundStyle(destructive ? BSmartColor.bear : BSmartColor.primaryText)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(BSmartColor.tertiaryText)
            }
        }
        .padding(16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}

struct AccountPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 20)
            .bSmartActionSurface(cornerRadius: 18)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : (colorScheme == .dark ? 0.4 : 1))
    }
}
