import SwiftUI

struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var wallet: DeviceWalletStore
    @EnvironmentObject private var deletion: AccountDeletionCoordinator
    @State private var authorizer = AccountIdentityAuthorizer()
    @State private var operation: Task<Void, Never>?
    @State private var recoveryConfirmed = false
    @State private var showsConfirmation = false
    @State private var showsRecovery = false
    @State private var errorMessage: String?
    @State private var registration: TradingWalletRegistration?

    private var busy: Bool { operation != nil || deletion.isBusy || account.isBusy || wallet.isBusy }
    private var readyWallet: DeviceWalletSummary? {
        guard case .verified(let value) = wallet.state, value.accountID == account.identity?.id else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 30)).foregroundStyle(BSmartColor.secondaryText)
                if let record = deletion.record {
                    status(record)
                } else {
                    Text("Delete your bSmart account".bSmartLocalized).font(.title2.bold())
                    Text("Your account and account-linked profile will be deleted. This does not withdraw funds or delete your wallet. Keep your recovery phrase to access your funds without bSmart.".bSmartLocalized)
                        .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                    if let registration, registration.accountId == account.identity?.id {
                        if let address = registration.address {
                            Text(address).font(.caption.monospaced()).textSelection(.enabled)
                            if let local = readyWallet, local.address == address {
                                Label((local.recoveryVerified ? "Recovery verified" : "Recovery not verified").bSmartLocalized,
                                      systemImage: local.recoveryVerified ? "checkmark.shield" : "key")
                                    .font(.subheadline).foregroundStyle(BSmartColor.brand)
                                action("View recovery phrase", icon: "key") { showsRecovery = true }
                            }
                            Text("Without your recovery phrase, deleting this account may leave you unable to access your wallet. bSmart cannot recover your keys.".bSmartLocalized)
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        } else {
                            Label("No wallet linked".bSmartLocalized, systemImage: "wallet.bifold")
                                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        }
                        Toggle((registration.address == nil ? "I understand that account deletion is permanent"
                                : "I have saved my recovery phrase or accept the risk of losing wallet access").bSmartLocalized,
                               isOn: $recoveryConfirmed)
                            .font(.subheadline).tint(BSmartColor.brand)
                        action("Delete account", icon: "trash", destructive: true) { showsConfirmation = true }
                            .disabled(!recoveryConfirmed || busy)
                    } else {
                        action("Check linked wallet", icon: "arrow.clockwise") { run { try await loadRegistration() } }
                    }
                }
                if busy { ProgressView().frame(maxWidth: .infinity) }
                if let message = errorMessage ?? deletion.error.map(message) {
                    Text(message).font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
                        .accessibilityIdentifier("account.deletion-error")
                }
            }
            .padding(24).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .navigationTitle("Delete account".bSmartLocalized).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your bSmart account?".bSmartLocalized, isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("Delete account".bSmartLocalized, role: .destructive) { startDeletion() }
        } message: {
            Text("Sign in again to confirm. Your wallet keys and on-chain funds will not be deleted.".bSmartLocalized)
        }
        .fullScreenCover(isPresented: $showsRecovery) { NavigationStack { DeviceWalletRecoveryView() } }
        .task {
            do {
                try await deletion.resume()
                if deletion.record == nil, account.identity != nil { try await loadRegistration() }
            } catch is CancellationError {} catch { errorMessage = message(error) }
        }
        .onDisappear { operation?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { operation?.cancel(); recoveryConfirmed = false }
        }
        .accessibilityIdentifier("account.deletion-screen")
        .bSmartPage()
    }

    @ViewBuilder
    private func status(_ record: AccountDeletionRecord) -> some View {
        Text(title(record).bSmartLocalized).font(.title2.bold())
            .accessibilityIdentifier("account.deletion-state")
        if record.stage == .completed {
            Text("Your wallet and on-chain funds remain under your control. Use your saved recovery phrase to access them independently.".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            action("Done", icon: "checkmark") {
                do { try deletion.acknowledgeOrDiscardPrepared(ticket: record.ticket); dismiss() }
                catch { errorMessage = message(error) }
            }
        } else if record.stage == .prepared {
            action("Discard unsent request", icon: "xmark") {
                do { try deletion.acknowledgeOrDiscardPrepared(ticket: record.ticket); dismiss() }
                catch { errorMessage = message(error) }
            }
        } else {
            Text("Your request is saved. You can close the app and check its status here later.".bSmartLocalized)
                .font(.subheadline).foregroundStyle(BSmartColor.secondaryText)
            action("Check deletion status", icon: "arrow.clockwise") { run { try await deletion.resume() } }
            if record.stage == .submitted, deletion.error == .requestNotFound {
                action("Sign in to confirm deletion again", icon: "person.crop.circle.badge.checkmark", destructive: true) {
                    run {
                        let result = try await account.reauthenticateForDeletion(expected: record.account) {
                            try await authorizer.authorize(record.account.provider, challenge: $0)
                        }
                        do {
                            try Task.checkCancellation()
                            guard scenePhase == .active else { throw CancellationError() }
                            try await deletion.retryUnconfirmed(session: result.session, googleUserID: result.googleUserID, confirmed: true)
                        } catch {
                            await account.revokeTemporaryDeletionSession(result.session)
                            throw error
                        }
                        await account.revokeTemporaryDeletionSession(result.session)
                    }
                }
            }
            if record.stage == .serverCompleted, !record.providerDisconnected {
                action("Confirm Google disconnect", icon: "person.crop.circle.badge.checkmark") {
                    run {
                        let challenge = AccountAuthChallenge(id: UUID(), nonce: try AccountDeletionTicket.random().statusToken,
                                                             expiresAt: Date().addingTimeInterval(300))
                        let assertion = try await authorizer.authorize(.google, challenge: challenge)
                        try Task.checkCancellation()
                        guard scenePhase == .active else { throw CancellationError() }
                        guard assertion.googleUserID == record.googleUserID else { throw AccountDeletionError.accountChanged }
                        try await deletion.resume()
                    }
                }
            }
        }
    }

    private func startDeletion() {
        guard let identity = account.identity, let expected = registration,
              expected.accountId == identity.id, recoveryConfirmed else { return }
        run {
            let registration = try await account.walletRegistration()
            guard registration == expected, scenePhase == .active else { throw AccountDeletionError.accountChanged }
            let result = try await account.reauthenticateForDeletion(expected: identity) {
                try await authorizer.authorize(identity.provider, challenge: $0)
            }
            do {
                try Task.checkCancellation()
                guard scenePhase == .active else { throw CancellationError() }
                let record = try AccountDeletionRecord(account: identity, endpoint: deletion.endpoint,
                    ticket: .random(), walletAddress: registration.address, googleUserID: result.googleUserID)
                try await deletion.submit(record, session: result.session, confirmed: true, recoveryConfirmed: true)
            } catch {
                await account.revokeTemporaryDeletionSession(result.session)
                throw error
            }
            await account.revokeTemporaryDeletionSession(result.session)
        }
    }

    private func loadRegistration() async throws {
        let value = try await account.walletRegistration()
        try Task.checkCancellation()
        guard value.accountId == account.identity?.id, deletion.record == nil else { throw AccountDeletionError.accountChanged }
        registration = value
        recoveryConfirmed = false
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        errorMessage = nil
        operation = Task { @MainActor in
            defer { operation = nil }
            do { try await action() }
            catch is CancellationError {} catch { errorMessage = message(error) }
        }
    }

    private func action(_ title: String, icon: String, destructive: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title.bSmartLocalized, systemImage: icon).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(destructive ? Color.red : BSmartColor.brand)
                .background(BSmartColor.secondaryText.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BSmartColor.line, lineWidth: 1))
        }.buttonStyle(.plain).disabled(busy)
    }

    private func title(_ record: AccountDeletionRecord) -> String {
        switch record.stage {
        case .prepared: return "Deletion request not sent"
        case .submitted: return "Confirming deletion status"
        case .accepted: return "Account deletion in progress"
        case .serverCompleted: return "Finishing account cleanup"
        case .completed: return "Account deleted"
        }
    }

    private func message(_ error: Error) -> String {
        switch error as? AccountDeletionError {
        case .storage: return "Deletion progress could not be saved securely. Try again on this device.".bSmartLocalized
        case .requestNotFound: return "The saved request could not be confirmed. Check again or sign in to confirm deletion.".bSmartLocalized
        case .providerDisconnectRequired: return "Confirm the original Google account to finish disconnecting it.".bSmartLocalized
        case .accountChanged: return "Use the same account that requested deletion.".bSmartLocalized
        default: return "Deletion is not confirmed. Your saved request has not been removed.".bSmartLocalized
        }
    }
}
