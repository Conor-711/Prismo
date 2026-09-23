import SwiftUI

enum AccountProviderButtonContent {
    static func title(for provider: AccountIdentityProvider) -> String {
        switch provider {
        case .apple: "Continue with Apple".bSmartLocalized
        case .google: "Continue with Google".bSmartLocalized
        }
    }
}

struct AccountProviderButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    let provider: AccountIdentityProvider
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if provider == .apple {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20, weight: .regular))
                    } else {
                        Image("GoogleSignInMark").renderingMode(.original)
                            .resizable().scaledToFit()
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                Text(AccountProviderButtonContent.title(for: provider))
                    .font(.system(.body, design: .default, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if isBusy { ProgressView().tint(Color(white: 0.12)).accessibilityHidden(true) }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(Color(white: 0.12))
            .background(Color(white: 0.95), in: Capsule())
            .overlay(Capsule().stroke(colorScheme == .light ? BSmartColor.line : .clear, lineWidth: 0.75))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AccountProviderButtonContent.title(for: provider))
        .accessibilityIdentifier("account.signin.\(provider.rawValue)")
    }
}
