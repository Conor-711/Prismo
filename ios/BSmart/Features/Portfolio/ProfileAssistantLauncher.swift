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
            Image("SmartMoneyBorderCollie")
                .resizable().scaledToFill()
                .frame(width: 58, height: 58)
                .background(BSmartColor.elevated, in: Circle())
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(BSmartColor.brand, lineWidth: 1.5))
                .shadow(color: BSmartColor.floatingShadow, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI assistant".bSmartLocalized)
        .accessibilityIdentifier("profile.ai.open")
        .bSmartMatchedTransitionSource(id: "profile.ai", in: transition)
        .fullScreenCover(isPresented: $presented, onDismiss: {
            router.setTabBarHidden(false, token: visibilityToken)
        }) {
            AIAssistantView(onClose: { presented = false })
                .bSmartZoomNavigationTransition(sourceID: "profile.ai", in: transition)
        }
    }
}
