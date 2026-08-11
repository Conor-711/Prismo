import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var notificationPreferences: NotificationPreferencesStore
    @EnvironmentObject private var language: AppLanguageStore
    @State private var isShowingAlertSettings = false
    @State private var isConfirmingReset = false
    @State private var isResetting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
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

                    settingsSection("Notifications") {
                        settingsButton(
                            title: "Alert preferences",
                            detail: "Instant events, daily brief and quiet hours",
                            symbol: "bell.badge"
                        ) {
                            isShowingAlertSettings = true
                        }
                    }

                    settingsSection("Data & privacy") {
                        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
                            NavigationLink {
                                IntelligenceMethodView(isUsingDemoData: model.isUsingDemoData)
                            } label: {
                                settingsRow(
                                    title: "Data & methodology",
                                    detail: "Sources, Score and evidence relationships",
                                    symbol: "point.3.connected.trianglepath.dotted"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.data-methodology")

                            Divider().overlay(BSmartColor.line)

                            NavigationLink {
                                RiskDisclosureView()
                            } label: {
                                settingsRow(
                                    title: "Risk disclosure",
                                    detail: "Coverage, limitations and investment risk",
                                    symbol: "exclamationmark.shield"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.risk-disclosure")

                            Divider().overlay(BSmartColor.line)

                            Button(role: .destructive) {
                                isConfirmingReset = true
                            } label: {
                                HStack(spacing: BSmartSpacing.medium) {
                                    Image(systemName: "trash")
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                                        Text("Reset local app data")
                                            .font(.body.weight(.semibold))
                                        Text("Remove this device's portfolio, follows and event activity")
                                            .font(.caption)
                                            .foregroundStyle(BSmartColor.secondaryText)
                                    }

                                    Spacer(minLength: BSmartSpacing.small)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(BSmartColor.bear)
                            .disabled(isResetting)
                            .accessibilityIdentifier("settings.reset-local-data")

                            Divider().overlay(BSmartColor.line)

                            Label {
                                Text("Your installation identity is retained. This action does not delete a server account.")
                            } icon: {
                                Image(systemName: "lock.shield")
                                    .foregroundStyle(BSmartColor.brand)
                            }
                            .font(.caption)
                            .foregroundStyle(BSmartColor.tertiaryText)
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
            .sheet(isPresented: $isShowingAlertSettings) {
                NotificationSettingsView()
            }
            .confirmationDialog(
                "Reset local app data?",
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Reset local app data", role: .destructive) {
                    resetLocalData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your positions, watchlist, follows, event activity and alert preferences from this device.")
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

    private func settingsButton(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRow(title: title, detail: detail, symbol: symbol)
        }
        .buttonStyle(.plain)
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

    private func resetLocalData() {
        isResetting = true
        Task {
            await notifications.clearPendingLocalNotifications()
            notificationPreferences.resetLocalPreferences()
            await model.resetLocalAppData()
            isResetting = false
        }
    }
}
