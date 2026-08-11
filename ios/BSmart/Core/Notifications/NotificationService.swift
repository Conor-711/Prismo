import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var statusMessage: String?

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        registerForRemoteNotificationsIfAuthorized()
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            statusMessage = allowed ? "Alerts are enabled." : "Alerts remain disabled."
            return allowed
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func schedulePreview(for signal: PortfolioSignal) async {
        if authorizationStatus == .notDetermined {
            guard await requestAuthorization() else { return }
        }

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            statusMessage = "Enable notifications in Settings to preview an alert."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(signal.ticker) · \(signal.kind.label)"
        content.body = signal.title
        content.sound = .default
        content.userInfo = [BSmartDeepLink.signalIDKey: signal.id.uuidString]
        content.threadIdentifier = "ticker.\(signal.ticker.lowercased())"
        content.targetContentIdentifier = signal.id.uuidString

        let request = UNNotificationRequest(
            identifier: "preview.\(signal.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            statusMessage = "Preview scheduled. Background bSmart, then tap the alert."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func clearPendingLocalNotifications() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        try? await center.setBadgeCount(0)
        statusMessage = nil
    }

    private func registerForRemoteNotificationsIfAuthorized() {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

@MainActor
final class BSmartAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = AppRouter()
    private var syncCoordinator: BSmartSyncCoordinator?
    private var pendingRegistration: DeviceRegistrationInput?

    func configure(syncCoordinator: BSmartSyncCoordinator?) {
        self.syncCoordinator = syncCoordinator
        guard let pendingRegistration, let syncCoordinator else { return }
        self.pendingRegistration = nil
        Task { await syncCoordinator.enqueueDeviceRegistration(pendingRegistration) }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let registration = DeviceRegistrationInput(
            apnsToken: deviceToken.map { String(format: "%02x", $0) }.joined(),
            environment: Self.apnsEnvironment,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier
        )
        guard let syncCoordinator else {
            pendingRegistration = registration
            return
        }
        Task { await syncCoordinator.enqueueDeviceRegistration(registration) }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let signalID = (userInfo[BSmartDeepLink.signalIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        let ticker = userInfo["ticker"] as? String
        if let syncCoordinator {
            let event = ClientTelemetryEvent(
                name: .notificationOpened,
                signalId: signalID,
                ticker: ticker,
                context: .push
            )
            Task { await syncCoordinator.enqueueTelemetry(event) }
        }

        if let rawDeepLink = userInfo[BSmartDeepLink.deepLinkKey] as? String,
           let deepLink = URL(string: rawDeepLink),
           router.handle(url: deepLink) {
            return
        }

        guard let signalID
        else { return }
        router.openSignal(signalID)
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
}
