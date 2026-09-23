import SwiftUI

struct TradingAccountView: View {
    var isAppEntry = false
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deletion: AccountDeletionCoordinator
    @State private var authorizer = AccountIdentityAuthorizer()
    @State private var signInTask: Task<Void, Never>?
    @StateObject private var profileStore = AccountProfileStore()
    @State private var showsSetup = false
    @State private var showsEditor = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if deletion.record != nil || deletion.error == .storage {
                        AccountBrandHeader()
                        NavigationLink { AccountDeletionView() } label: {
                            AccountActionRow(title: "Account deletion", symbol: "person.crop.circle.badge.minus")
                        }.buttonStyle(.plain)
                        if account.identity != nil {
                            Button("Sign out".bSmartLocalized) { Task { await account.signOut() } }
                                .disabled(account.isBusy)
                                .accessibilityIdentifier("account.signout")
                        }
                    } else if account.identity == nil || isAppEntry {
                        signInContent
                            .frame(minHeight: max(0, geometry.size.height - 64))
                    } else {
                        signedInContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(BSmartColor.ink)
        .foregroundStyle(BSmartColor.primaryText)
        .navigationTitle(account.identity == nil || isAppEntry ? "" : "Account".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !account.didLoad { await account.load() } }
        .task(id: account.identity?.id) { if !isAppEntry { await loadProfile() } }
        .sheet(isPresented: $showsEditor, onDismiss: { Task { await loadProfile() } }) {
            if let id = account.identity?.id { AccountProfileEditorPage(accountID: id) }
        }
        .fullScreenCover(isPresented: $showsSetup) {
            if let id = account.identity?.id, profileStore.accountID == id, let profile = profileStore.profile {
                AccountProfileEditor(profile: profile, accountID: id, onboarding: true) { saved in
                    profileStore.acceptSaved(saved, for: id)
                    showsSetup = false
                }
                .id(id)
            }
        }
        .onDisappear {
            if !showsSetup { signInTask?.cancel(); signInTask = nil }
        }
        .alert("Account".bSmartLocalized, isPresented: Binding(
            get: { account.errorMessage != nil }, set: { if !$0 { account.errorMessage = nil } }
        )) {
            Button("OK".bSmartLocalized) { account.errorMessage = nil }
        } message: { Text(account.errorMessage ?? "") }
        .accessibilityIdentifier("account.screen")
        .bSmartPage()
    }

    private var signInContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            AccountBrandHeader()
            Spacer(minLength: 80)
            VStack(alignment: .leading, spacing: 24) {
                Text("Sign in".bSmartLocalized)
                    .font(.system(.title, design: .default, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                AccountGoogleButton(isBusy: account.isBusy) { signIn(.google) }
                    .disabled(account.isBusy || !account.configuration.providers.contains(.google))
                if AccountIdentityAuthorizer.isAppleSignInEnabled {
                    AccountAppleButton(isEnabled: !account.isBusy && account.configuration.providers.contains(.apple)) {
                        signIn(.apple)
                    }
                }
                if account.isTestSession {
                    Button("Exit test login".bSmartLocalized) { Task { await account.signOut() } }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityIdentifier("account.test-signout")
                } else if isAppEntry && account.identity == nil {
                    Button("Test login".bSmartLocalized) { account.startTestSession() }
                        .font(.body.weight(.medium))
                        .foregroundStyle(BSmartColor.brand)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(BSmartColor.brand.opacity(0.08), in: Capsule())
                        .disabled(account.isBusy || !account.didLoad)
                        .accessibilityIdentifier("account.signin.test")
                }
                if !account.isBusy && account.didLoad && account.configuration.providers.isEmpty {
                    Label("Account sign-in is not available yet.".bSmartLocalized, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.unavailable")
                    Button("Retry".bSmartLocalized) { Task { await account.load() } }
                        .frame(minHeight: 44)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var signedInContent: some View {
        VStack(spacing: 24) {
            if profileStore.loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 220)
            } else if let profile = profileStore.profile, profileStore.accountID == account.identity?.id {
                VStack(spacing: 16) {
                    BSmartAvatar(url: profile.avatarURL, name: profile.username, size: 88)
                        .padding(6)
                        .background(BSmartColor.surface, in: Circle())
                        .overlay(Circle().strokeBorder(BSmartColor.brand.opacity(0.18), lineWidth: 1))
                    VStack(spacing: 6) {
                        Text(profile.username)
                            .font(.system(.title, design: .default, weight: .semibold))
                            .multilineTextAlignment(.center)
                        if !profile.needsSetup {
                            Text("@" + profile.handle).font(.subheadline)
                                .foregroundStyle(BSmartColor.secondaryText)
                        }
                    }
                    Label("Signed in".bSmartLocalized, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BSmartColor.brand)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(BSmartColor.brand.opacity(0.08), in: Capsule())
                        .accessibilityIdentifier("account.signed-in")
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)

                VStack(spacing: 0) {
                    if profile.needsSetup {
                        Button { showsSetup = true } label: {
                            AccountActionRow(title: "Set up your profile", symbol: "person.crop.circle")
                        }.accessibilityIdentifier("account.setup")
                    } else {
                        Button { showsEditor = true } label: {
                            AccountActionRow(title: "Edit profile", symbol: "person.crop.circle")
                        }.accessibilityIdentifier("account.edit-profile")
                    }
                    Divider().padding(.leading, 64)
                    HStack(spacing: 14) {
                        Image(systemName: "lock.shield")
                            .frame(width: 36, height: 36)
                            .foregroundStyle(BSmartColor.brand)
                        Text("Sign-in method".bSmartLocalized).font(.body)
                        Spacer(minLength: 8)
                        Text(account.identity?.provider == .apple ? "Apple" : "Google")
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }.padding(16)
                }
                .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 20))
                .buttonStyle(.plain)

                if !profile.needsSetup {
                    NavigationLink { TradingWalletView() } label: {
                        HStack {
                            Text("Trading wallet".bSmartLocalized)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(AccountPrimaryButtonStyle())
                    .accessibilityIdentifier("account.continue")
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark").font(.largeTitle)
                    Text("Profile is unavailable. Please try again.".bSmartLocalized)
                        .multilineTextAlignment(.center)
                    Button("Retry".bSmartLocalized) { Task { await loadProfile() } }
                        .buttonStyle(.bordered).tint(BSmartColor.brand)
                }
                .foregroundStyle(BSmartColor.secondaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 32)
            }

            VStack(spacing: 0) {
                Button { Task { await account.signOut() } } label: {
                    AccountActionRow(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", showsChevron: false)
                }
                .disabled(account.isBusy)
                .accessibilityIdentifier("account.signout")
                if account.supportsAccountDeletion {
                    Divider().padding(.leading, 64)
                    NavigationLink { AccountDeletionView() } label: {
                        AccountActionRow(title: "Delete account", symbol: "trash", destructive: true)
                    }.accessibilityIdentifier("account.delete")
                }
            }
            .background(BSmartColor.surface, in: RoundedRectangle(cornerRadius: 20))
            .buttonStyle(.plain)
        }
    }

    private func loadProfile() async {
        showsSetup = false
        await profileStore.load(account: account)
        guard !Task.isCancelled, account.identity?.id == profileStore.accountID,
              profileStore.profile?.needsSetup == true else { return }
        showsSetup = true
    }

    private func signIn(_ provider: AccountIdentityProvider) {
        guard !account.isBusy else { return }
        signInTask?.cancel()
        signInTask = Task { await account.signIn(provider) { try await authorizer.authorize(provider, challenge: $0) } }
    }
}
