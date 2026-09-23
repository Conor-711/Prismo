import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: AppLanguageStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var account: AccountAccessStore
    @EnvironmentObject private var deviceWallet: DeviceWalletStore
    @EnvironmentObject private var notifications: NotificationService
    @State private var confirmsDisableWalletAuthentication = false
    @State private var isShowingOnboardingPreview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    settingsSection("Account") {
                        NavigationLink {
                            TradingAccountView()
                        } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(BSmartColor.brand).frame(width: 24, height: 24)
                                Text("Account".bSmartLocalized).font(.body.weight(.semibold))
                                Spacer()
                                if account.identity != nil {
                                    Text("Signed in".bSmartLocalized)
                                        .font(.subheadline).foregroundStyle(BSmartColor.brand)
                                } else if account.isTestSession {
                                    Text("Test login".bSmartLocalized)
                                        .font(.subheadline).foregroundStyle(BSmartColor.brand)
                                }
                                Image(systemName: "chevron.right").font(.caption)
                                    .foregroundStyle(BSmartColor.tertiaryText)
                            }.foregroundStyle(BSmartColor.primaryText).frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("settings.account")
                        if account.isTestSession {
                            Button { Task { await account.signOut() } } label: {
                                AccountActionRow(title: "Exit test login",
                                    symbol: "rectangle.portrait.and.arrow.right", showsChevron: false)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("settings.test-signout")
                        }
                        NavigationLink { TradingWalletView() } label: {
                            HStack(spacing: BSmartSpacing.medium) {
                                Image(systemName: "wallet.bifold")
                                    .foregroundStyle(BSmartColor.brand).frame(width: 24, height: 24)
                                Text("Trading wallet".bSmartLocalized).font(.body.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.foregroundStyle(BSmartColor.primaryText).frame(minHeight: 48)
                        }.accessibilityIdentifier("settings.wallet")
                        if case .verified(let wallet) = deviceWallet.state, wallet.accountID == account.identity?.id {
                            NavigationLink { ArbitrumReceiveView(service: account) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AccountActionRow(title: "Account address", symbol: "qrcode")
                                    Text(wallet.address).font(.caption.monospaced())
                                        .foregroundStyle(BSmartColor.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("settings.wallet.address.full")
                                }
                            }.accessibilityIdentifier("settings.wallet.address")
                        }
                    }

                    if account.identity != nil {
                        settingsSection("Wallet security") {
                            VStack(alignment: .leading, spacing: 12) {
                                if case .verified(let wallet) = deviceWallet.state, wallet.provider == .privy {
                                    Label("Account wallet".bSmartLocalized, systemImage: "checkmark.shield")
                                        .foregroundStyle(BSmartColor.brand)
                                } else {
                                Toggle(isOn: Binding(get: { deviceWallet.userPresenceRequired }, set: { required in
                                    if required { Task { await deviceWallet.setUserPresenceRequired(true) } }
                                    else { confirmsDisableWalletAuthentication = true }
                                })) {
                                    Label("Use Face ID".bSmartLocalized, systemImage: "faceid")
                                }.tint(BSmartColor.brand)
                                    .disabled(deviceWallet.isBusy || !walletIsReady)
                                    .accessibilityIdentifier("settings.wallet.face-id")
                                }
                                if deviceWallet.isBusy { ProgressView() }
                                else if !walletIsReady {
                                    Button("Unlock your bSmart wallet".bSmartLocalized) {
                                        Task { await deviceWallet.prepare() }
                                    }
                                }
                                if let error = deviceWallet.errorMessage {
                                    Text(error).font(.caption).foregroundStyle(BSmartColor.bear)
                                }
                            }
                        }
                    }

                    settingsSection("Language") {
                        VStack(spacing: 0) {
                            ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, option in
                                if index > 0 {
                                    Divider().overlay(BSmartColor.line)
                                }
                                languageRow(option)
                            }
                        }
                    }

                    settingsSection("Appearance") {
                        VStack(spacing: 0) {
                            ForEach(Array(AppAppearance.allCases.enumerated()), id: \.element.id) { index, option in
                                if index > 0 {
                                    Divider().overlay(BSmartColor.line)
                                }
                                appearanceRow(option)
                            }
                        }
                    }

                    if NotificationService.isEnabled {
                        settingsSection("Notifications") {
                            VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                                Toggle("Content notifications".bSmartLocalized, isOn: Binding(
                                    get: { notifications.dataUpdatesEnabled },
                                    set: { enabled in Task { await notifications.setDataUpdatesEnabled(enabled) } }
                                ))
                                .accessibilityIdentifier("settings.notifications.master")
                                Divider().overlay(BSmartColor.line)
                                Toggle("Followed authors".bSmartLocalized, isOn: Binding(
                                    get: { notifications.notifyAuthors }, set: notifications.setNotifyAuthors
                                ))
                                .disabled(!notifications.dataUpdatesEnabled)
                                .accessibilityIdentifier("settings.notifications.authors")
                                Toggle("Followed tickers".bSmartLocalized, isOn: Binding(
                                    get: { notifications.notifyTickers }, set: notifications.setNotifyTickers
                                ))
                                .disabled(!notifications.dataUpdatesEnabled)
                                .accessibilityIdentifier("settings.notifications.tickers")
                                Toggle("Open positions".bSmartLocalized, isOn: Binding(
                                    get: { notifications.notifyHoldings }, set: notifications.setNotifyHoldings
                                ))
                                .disabled(!notifications.dataUpdatesEnabled)
                                .accessibilityIdentifier("settings.notifications.holdings")
                                if notifications.authorizationStatus == .denied {
                                    Button("Open Settings".bSmartLocalized) { notifications.openSystemSettings() }
                                }
                                if notifications.dataUpdatesRegistrationFailed {
                                    Text("Notification registration failed. We will retry when connected.".bSmartLocalized)
                                        .font(.subheadline).foregroundStyle(BSmartColor.bear)
                                }
                            }
                            .tint(BSmartColor.brand)
                        }
                    }

                    settingsSection("Feedback") {
                        Link(destination: AppSupportLinks.alphaFeedback) {
                            settingsRow(
                                title: "Send product feedback",
                                detail: "Report confusing signals, missing states or workflow issues",
                                symbol: "bubble.left.and.text.bubble.right"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.send-feedback")
                    }

                    settingsSection("Help") {
                        Button {
                            isShowingOnboardingPreview = true
                        } label: {
                            AccountActionRow(
                                title: "Replay onboarding",
                                symbol: "play.rectangle",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.onboarding-preview")
                    }

                    settingsSection("About") {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                                BSmartWordmark(fontSize: 17)
                                Text("Investment intelligence, not investment advice.")
                                    .font(.caption)
                                    .foregroundStyle(BSmartColor.secondaryText)
                            }

                            Spacer()

                            Text(versionLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(BSmartColor.tertiaryText)
                        }
                    }
                }
                .padding(BSmartSpacing.large)
            }
            .background(BSmartColor.ink)
            .navigationTitle("Settings".bSmartLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.screen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".bSmartLocalized) { dismiss() }
                }
            }
            .task { await notifications.refreshAuthorizationStatus() }
            .confirmationDialog("Turn off wallet Face ID?".bSmartLocalized,
                isPresented: $confirmsDisableWalletAuthentication, titleVisibility: .visible) {
                Button("Turn off".bSmartLocalized, role: .destructive) {
                    Task { await deviceWallet.setUserPresenceRequired(false) }
                }
                Button("Cancel".bSmartLocalized, role: .cancel) {}
            } message: {
                Text("Anyone using your unlocked device and signed-in account can authorize wallet operations without another identity check.".bSmartLocalized)
            }
            .fullScreenCover(isPresented: $isShowingOnboardingPreview) {
                OnboardingView(isPreview: true) {
                    isShowingOnboardingPreview = false
                }
            }
        }
        .bSmartPage()
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.small) {
            Text(title.bSmartLocalized.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(BSmartColor.tertiaryText)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .bSmartSurface()
        }
    }

    private func languageRow(_ option: AppLanguage) -> some View {
        Button {
            withAnimation(BSmartMotion.quick) {
                language.select(option)
            }
        } label: {
            HStack(spacing: BSmartSpacing.medium) {
                Image(systemName: option == language.selection ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(option == language.selection ? BSmartColor.brand : BSmartColor.tertiaryText)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                    Text(option.displayName)
                        .font(.body.weight(.semibold))
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }

                Spacer(minLength: BSmartSpacing.small)
            }
            .padding(.vertical, BSmartSpacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(option == language.selection ? "Selected".bSmartLocalized : "")
        .accessibilityAddTraits(option == language.selection ? .isSelected : [])
        .accessibilityIdentifier("settings.language.\(option.rawValue)")
    }

    private func appearanceRow(_ option: AppAppearance) -> some View {
        Button {
            withAnimation(BSmartMotion.standard) {
                appearance.select(option)
            }
        } label: {
            HStack(spacing: BSmartSpacing.medium) {
                Image(systemName: option.symbol)
                    .foregroundStyle(option == appearance.selection ? BSmartColor.brand : BSmartColor.tertiaryText)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                    Text(option.displayName)
                        .font(.body.weight(.semibold))
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                }

                Spacer(minLength: BSmartSpacing.small)

                if option == appearance.selection {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BSmartColor.brand)
                }
            }
            .padding(.vertical, BSmartSpacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option == appearance.selection ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(option.rawValue)")
    }

    private func settingsRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: BSmartSpacing.medium) {
            Image(systemName: symbol)
                .foregroundStyle(BSmartColor.brand)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                Text(title.bSmartLocalized)
                    .font(.body.weight(.semibold))
                Text(detail.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
            }

            Spacer(minLength: BSmartSpacing.small)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(BSmartColor.tertiaryText)
        }
        .contentShape(Rectangle())
    }

    private var versionLabel: String {
        AppBuildInfo.current.displayLabel
    }

    private var walletIsReady: Bool {
        if case .verified(let wallet) = deviceWallet.state { return wallet.accountID == account.identity?.id }
        return false
    }

}
