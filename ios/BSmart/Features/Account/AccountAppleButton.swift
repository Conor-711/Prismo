import SwiftUI

struct AccountAppleButton: View {
    var isEnabled: Bool
    let action: () -> Void

    var body: some View {
        AccountProviderButton(provider: .apple, action: action)
            .disabled(!isEnabled)
    }
}
