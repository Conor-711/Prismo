import SwiftUI
import GoogleSignInSwift

struct TradingAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deletion: AccountDeletionCoordinator
    @State private var authorizer = AccountIdentityAuthorizer()
    @State private var signInTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    BSmartWordmark(fontSize: 24)
                    Spacer()
                    Image(systemName: "lock.shield")
                        .font(.title2).foregroundStyle(BSmartColor.brand)
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your bSmart account".bSmartLocalized)
                        .font(.system(.title2, design: .default, weight: .bold))
                    if let identity = account.identity {
                        Label(identity.provider == .apple ? "Apple" : "Google", systemImage: "person.crop.circle")
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    }
                }

                if deletion.record != nil || deletion.error == .storage {
                    NavigationLink { AccountDeletionView() } label: {
                        Label("Account deletion".bSmartLocalized, systemImage: "person.crop.circle.badge.minus")
                            .font(.headline).frame(minHeight: 48)
                    }
                } else if account.identity == nil {
                    VStack(spacing: 12) {
                        GoogleSignInButton(scheme: .light, style: .wide) { signIn(.google) }
                            .frame(height: 52)
                            .accessibilityIdentifier("account.signin.google")
                            .disabled(!account.configuration.providers.contains(.google))
                    }
                    .disabled(account.isBusy)
                    if account.isBusy {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if account.didLoad && account.configuration.providers.isEmpty {
                        Label("Account sign-in is not available yet.".bSmartLocalized, systemImage: "clock")
                            .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                            .accessibilityIdentifier("account.unavailable")
                    }
                } else {
                    Label("Signed in".bSmartLocalized, systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundStyle(BSmartColor.brand)
                        .accessibilityIdentifier("account.signed-in")
                    NavigationLink { TradingWalletView() } label: {
                        Text("Continue".bSmartLocalized)
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(BSmartColor.onAccent)
                            .background(BSmartColor.brand, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.continue")
                }

                if account.identity != nil {
                    if account.supportsAccountDeletion {
                        NavigationLink { AccountDeletionView() } label: {
                            Label("Delete account".bSmartLocalized, systemImage: "trash")
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText).frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("account.delete")
                    }
                    Button("Sign out".bSmartLocalized) { Task { await account.signOut() } }
                        .disabled(account.isBusy)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .accessibilityIdentifier("account.signout")
                }
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(BSmartColor.ink)
        .foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Account".bSmartLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .task { await account.load() }
        .onDisappear {
            signInTask?.cancel()
            signInTask = nil
        }
        .alert("Account".bSmartLocalized, isPresented: Binding(
            get: { account.errorMessage != nil }, set: { if !$0 { account.errorMessage = nil } }
        )) {
            Button("OK".bSmartLocalized) { account.errorMessage = nil }
        } message: { Text(account.errorMessage ?? "") }
        .accessibilityIdentifier("account.screen")
        .bSmartPage()
    }

    private func signIn(_ provider: AccountIdentityProvider) {
        guard !account.isBusy else { return }
        signInTask?.cancel()
        signInTask = Task { await account.signIn(provider) { try await authorizer.authorize(provider, challenge: $0) } }
    }
}
