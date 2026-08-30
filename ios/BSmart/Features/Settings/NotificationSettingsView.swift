import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var notificationPreferences: NotificationPreferencesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSmartSpacing.xLarge) {
                    intro
                    preferences
                    trackedStocks
                    preview
                    boundary
                }
                .padding(BSmartSpacing.large)
            }
            .background(BSmartColor.ink)
            .accessibilityIdentifier("alerts.screen")
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await notifications.refreshAuthorizationStatus()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.title2)
                    .foregroundStyle(BSmartColor.brand)
                    .frame(width: 42, height: 42)
                    .background(BSmartColor.brand.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSmartRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: BSmartSpacing.xSmall) {
                    Text("Portfolio-aware alerts")
                        .font(.title3.weight(.bold))
                    Text("bSmart alerts you when qualified views or public capital moves materially change for a tracked stock.")
                        .font(.subheadline)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Label(permissionLabel, systemImage: permissionSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(permissionColor)
                Spacer()
                if notifications.authorizationStatus == .denied {
                    Button("Open Settings") { notifications.openSystemSettings() }
                        .font(.caption.weight(.bold))
                } else if notifications.authorizationStatus == .notDetermined {
                    Button("Enable") {
                        Task { await notifications.requestAuthorization() }
                    }
                    .font(.caption.weight(.bold))
                }
            }
        }
        .bSmartSurface()
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 0) {
            BSmartSectionHeader(title: "Delivery")
                .padding(.bottom, BSmartSpacing.small)
            preferenceToggle(
                title: "Important changes",
                detail: "Material Smart Account, Smart Money, confirmation and divergence signals.",
                isOn: Binding(
                    get: { notificationPreferences.preferences.instantAlertsEnabled },
                    set: notificationPreferences.setInstantAlertsEnabled
                )
            )
            Divider().overlay(BSmartColor.line)
            preferenceToggle(
                title: "Daily digest",
                detail: "Lower-priority changes grouped into one portfolio summary.",
                isOn: Binding(
                    get: { notificationPreferences.preferences.dailyDigestEnabled },
                    set: notificationPreferences.setDailyDigestEnabled
                )
            )
            if notificationPreferences.preferences.dailyDigestEnabled {
                timePicker(
                    title: "Delivery time",
                    minutes: notificationPreferences.preferences.dailyDigestMinutes,
                    setter: { notificationPreferences.setDailyDigestTime($0) }
                )
            }
            Divider().overlay(BSmartColor.line)
            preferenceToggle(
                title: "Quiet hours",
                detail: "Hold non-critical alerts overnight and include them in the next digest.",
                isOn: Binding(
                    get: { notificationPreferences.preferences.quietHoursEnabled },
                    set: notificationPreferences.setQuietHoursEnabled
                )
            )
            if notificationPreferences.preferences.quietHoursEnabled {
                HStack(spacing: BSmartSpacing.large) {
                    timePicker(
                        title: "From",
                        minutes: notificationPreferences.preferences.quietHoursStartMinutes,
                        setter: { notificationPreferences.setQuietHoursStart($0) }
                    )
                    timePicker(
                        title: "Until",
                        minutes: notificationPreferences.preferences.quietHoursEndMinutes,
                        setter: { notificationPreferences.setQuietHoursEnd($0) }
                    )
                }
            }
        }
        .bSmartSurface()
    }

    @ViewBuilder
    private var trackedStocks: some View {
        if !model.positions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                BSmartSectionHeader(title: "Tracked stocks", detail: "Alerts and daily digest")
                    .padding(.bottom, BSmartSpacing.small)

                ForEach(Array(model.positions.sorted { $0.ticker < $1.ticker }.enumerated()), id: \.element.id) { index, position in
                    if index > 0 {
                        Divider().overlay(BSmartColor.line)
                    }

                    Toggle(
                        isOn: Binding(
                            get: { notificationPreferences.isTickerEnabled(position.ticker) },
                            set: { notificationPreferences.setTicker(position.ticker, isEnabled: $0) }
                        )
                    ) {
                        HStack(spacing: BSmartSpacing.medium) {
                            BSmartAssetMark(ticker: position.ticker, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(position.ticker)
                                    .font(.subheadline.weight(.bold))
                                Text("\(position.companyName) · \(position.resolvedKind.label)")
                                    .font(.caption)
                                    .foregroundStyle(BSmartColor.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .tint(BSmartColor.brand)
                    .padding(.vertical, BSmartSpacing.medium)
                    .accessibilityIdentifier("alerts.ticker.\(position.ticker)")
                }
            }
            .bSmartSurface()
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: BSmartSpacing.medium) {
            BSmartSectionHeader(title: "Notification preview")

            if let signal = previewSignal {
                HStack(alignment: .top, spacing: BSmartSpacing.medium) {
                    BSmartAssetMark(ticker: signal.ticker, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(signal.ticker) · \(signal.kind.label)")
                            .font(.subheadline.weight(.bold))
                        Text(signal.title.bSmartLocalized)
                            .font(.caption)
                            .foregroundStyle(BSmartColor.secondaryText)
                            .lineLimit(2)
                    }
                }

                Button {
                    Task { await notifications.schedulePreview(for: signal) }
                } label: {
                    Label("Send preview alert", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                if let message = notifications.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(BSmartColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Enable alerts for a covered ticker before previewing an alert.")
                    .font(.subheadline)
                    .foregroundStyle(BSmartColor.secondaryText)
            }
        }
        .bSmartSurface()
    }

    private var previewSignal: PortfolioSignal? {
        (model.portfolioSignals + model.signals).first {
            notificationPreferences.isTickerEnabled($0.ticker)
        }
    }

    private var boundary: some View {
        Label(
            "Alerts describe evidence changes and open research context. They are not trade instructions.",
            systemImage: "shield.lefthalf.filled"
        )
        .font(.caption)
        .foregroundStyle(BSmartColor.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, BSmartSpacing.small)
    }

    private func preferenceToggle(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.bSmartLocalized)
                    .font(.subheadline.weight(.semibold))
                Text(detail.bSmartLocalized)
                    .font(.caption)
                    .foregroundStyle(BSmartColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(BSmartColor.brand)
        .padding(.vertical, BSmartSpacing.medium)
    }

    private func timePicker(
        title: String,
        minutes: Int,
        setter: @escaping (Date) -> Void
    ) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { notificationPreferences.date(for: minutes) },
                set: setter
            ),
            displayedComponents: .hourAndMinute
        )
        .font(.caption.weight(.semibold))
        .tint(BSmartColor.brand)
        .padding(.vertical, BSmartSpacing.small)
        .frame(maxWidth: .infinity)
    }

    private var permissionLabel: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Notifications enabled"
        case .denied: "Notifications disabled"
        case .notDetermined: "Permission not requested"
        @unknown default: "Notification status unavailable"
        }
    }

    private var permissionSymbol: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .notDetermined: "circle.dashed"
        @unknown default: "questionmark.circle"
        }
    }

    private var permissionColor: Color {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: BSmartColor.brand
        case .denied: BSmartColor.bear
        case .notDetermined: BSmartColor.gold
        @unknown default: BSmartColor.secondaryText
        }
    }
}
