import SwiftUI

struct ProfileAssistantLauncher: View {
    @EnvironmentObject private var router: AppRouter
    @State private var presented = false
    @State private var visibilityToken = UUID()
    @Namespace private var transition

    var body: some View {
        Button {
            guard !presented else { return }
            router.setTabBarHidden(true, token: visibilityToken)
            presented = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(BSmartColor.brand)
                .frame(width: 44, height: 44)
                .background(BSmartColor.brand.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(BSmartColor.brand.opacity(0.55), lineWidth: 1))
                .shadow(color: BSmartColor.brand.opacity(0.16), radius: 6, y: 2)
        }
        .buttonStyle(ProfileAssistantButtonStyle())
        .accessibilityLabel("AI assistant".bSmartLocalized)
        .accessibilityIdentifier("profile.ai.open")
        .help("AI assistant".bSmartLocalized)
        .bSmartMatchedTransitionSource(id: "profile.ai", in: transition)
        .fullScreenCover(isPresented: $presented, onDismiss: {
            router.setTabBarHidden(false, token: visibilityToken)
        }) {
            AIAssistantView(onClose: { presented = false })
                .bSmartZoomNavigationTransition(sourceID: "profile.ai", in: transition)
        }
    }
}

private struct ProfileAssistantButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
