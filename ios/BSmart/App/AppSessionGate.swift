import SwiftUI

struct AppSessionGate<Content: View>: View {
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var model: AppModel
    @StateObject private var profile = AccountProfileStore()
    @ViewBuilder let content: () -> Content

    private var activeID: UUID? { account.canAccessAppContent ? account.identity?.id : nil }

    var body: some View {
        Group {
            if !account.didLoad {
                restoring
            } else if account.isTestSession && account.identity == nil {
                content().id("test-session")
            } else if activeID == nil {
                NavigationStack { TradingAccountView(isAppEntry: true) }
                    .accessibilityIdentifier("app.login")
            } else if let id = activeID, profile.accountID == id, let value = profile.profile {
                if value.needsSetup {
                    AccountProfileEditor(profile: value, accountID: id, onboarding: true) { saved in
                        profile.acceptSaved(saved, for: id)
                    }
                    .id(id)
                    .task(id: id) {
                        model.requireInitialOnboarding(for: id)
                    }
                } else {
                    content().id(id)
                }
            } else if profile.failed {
                VStack(spacing: 24) {
                    Text("Profile is unavailable. Please try again.".bSmartLocalized)
                        .multilineTextAlignment(.center)
                    Button("Retry".bSmartLocalized) { Task { await profile.load(account: account) } }
                        .buttonStyle(AccountPrimaryButtonStyle())
                    Button("Sign out".bSmartLocalized) { Task { await account.signOut() } }
                        .disabled(account.isBusy).frame(minHeight: 44)
                }
                .padding(32).frame(maxWidth: 460)
                .accessibilityIdentifier("app.profile-unavailable")
            } else {
                restoring
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bSmartPage()
        .task(id: activeID) {
            profile.clear()
            guard activeID != nil else { return }
            await profile.load(account: account)
        }
    }

    private var restoring: some View {
        VStack(spacing: 32) {
            AccountBrandHeader()
            ProgressView().tint(BSmartColor.brand)
        }
        .padding(32)
        .accessibilityIdentifier("app.session-loading")
    }
}
