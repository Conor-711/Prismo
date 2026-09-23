import Foundation
import UIKit
import UserNotifications

private struct PushInterestSnapshot: Codable {
    var authors = Set<String>()
    var money = Set<String>()
    var tickers = Set<String>()
    var holdings = Set<String>()

    @MainActor static func from(_ model: AppModel) -> Self {
        .init(authors: Set(model.followedSmartAccountIDs.map { $0.lowercased() }),
              money: Set(model.followedSmartMoneyIDs.map { $0.lowercased() }),
              tickers: Set(model.watchlist.map { $0.ticker.uppercased() }),
              holdings: Set(model.heldPositions.map { $0.ticker.uppercased() }))
    }

    mutating func applyChanges(from old: Self, to current: Self) {
        authors.formUnion(current.authors.subtracting(old.authors))
        authors.subtract(old.authors.subtracting(current.authors))
        money.formUnion(current.money.subtracting(old.money))
        money.subtract(old.money.subtracting(current.money))
        tickers.formUnion(current.tickers.subtracting(old.tickers))
        tickers.subtract(old.tickers.subtracting(current.tickers))
        holdings.formUnion(current.holdings.subtracting(old.holdings))
        holdings.subtract(old.holdings.subtracting(current.holdings))
    }
}

@MainActor
final class NotificationService: ObservableObject {
    static let isEnabled = Bundle.main.object(forInfoDictionaryKey: "BSMART_PUSH_ENABLED") as? String == "YES"
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var statusMessage: String?
    @Published private(set) var dataUpdatesEnabled = UserDefaults.standard.object(forKey: "bsmart.push.data-updates") as? Bool ?? true
    @Published private(set) var dataUpdatesRegistrationFailed = false
    @Published private(set) var notifyAuthors = UserDefaults.standard.object(forKey: "bsmart.push.authors") as? Bool ?? true
    @Published private(set) var notifyTickers = UserDefaults.standard.object(forKey: "bsmart.push.tickers") as? Bool ?? true
    @Published private(set) var notifyHoldings = UserDefaults.standard.object(forKey: "bsmart.push.holdings") as? Bool ?? true
    private let contentRegistration = ContentPushRegistration()
    private weak var model: AppModel?
    private weak var account: AccountAccessStore?
    private var scopedAccountID: UUID?
    private var scopedInterests = PushInterestSnapshot()
    private var observedModelInterests: PushInterestSnapshot?
    private var loadedInterestScope = false
    private var deviceToken: String?
    private var pushLocale = Locale.current.identifier
    private var liveHeldTickers = Set<String>()
    private var liveHoldingsAccountID: UUID?
    private var lastLiveHoldingsRefresh: Date?

    func bind(account: AccountAccessStore, model: AppModel) {
        guard Self.isEnabled else { return }
        self.model = model
        self.account = account
        contentRegistration.bind(account: account)
        contentRegistration.onResult = { [weak self] success in self?.dataUpdatesRegistrationFailed = !success }
        interestsChanged()
    }

    func receiveDeviceToken(_ token: String) {
        guard Self.isEnabled else { return }
        deviceToken = token
        synchronizeDataUpdates()
    }

    func remoteRegistrationFailed() {
        guard Self.isEnabled else { return }
        dataUpdatesRegistrationFailed = true
    }

    func setDataUpdatesEnabled(_ enabled: Bool) async {
        guard Self.isEnabled else { return }
        dataUpdatesEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "bsmart.push.data-updates")
        if enabled && authorizationStatus == .notDetermined { await requestAuthorization() }
        else { await refreshAuthorizationStatus() }
    }

    func setPushLocale(_ locale: String) {
        pushLocale = locale
        synchronizeDataUpdates()
    }

    func setNotifyAuthors(_ enabled: Bool) {
        notifyAuthors = enabled
        UserDefaults.standard.set(enabled, forKey: "bsmart.push.authors")
        interestsChanged()
    }

    func setNotifyTickers(_ enabled: Bool) {
        notifyTickers = enabled
        UserDefaults.standard.set(enabled, forKey: "bsmart.push.tickers")
        interestsChanged()
    }

    func setNotifyHoldings(_ enabled: Bool) {
        notifyHoldings = enabled
        UserDefaults.standard.set(enabled, forKey: "bsmart.push.holdings")
        interestsChanged()
    }

    func accountChanged() {
        loadedInterestScope = false
        scopedAccountID = nil
        observedModelInterests = nil
        interestsChanged()
    }

    func contentDidFinishLoading() {
        loadedInterestScope = true
        interestsChanged()
    }

    func interestsChanged() {
        if loadedInterestScope, let model, model.hasFinishedInitialLoad, let id = account?.identity?.id {
            let current = PushInterestSnapshot.from(model)
            if scopedAccountID != id {
                scopedAccountID = id
                observedModelInterests = current
                let key = "bsmart.push.interests.v1.\(id.uuidString.lowercased())"
                if let data = UserDefaults.standard.data(forKey: key),
                   let saved = try? JSONDecoder().decode(PushInterestSnapshot.self, from: data) {
                    scopedInterests = saved
                } else if UserDefaults.standard.string(forKey: "bsmart.push.interests.owner.v1") == nil {
                    // Existing device-wide follows are migrated only to the first verified account.
                    UserDefaults.standard.set(id.uuidString, forKey: "bsmart.push.interests.owner.v1")
                    scopedInterests = current
                } else {
                    scopedInterests = PushInterestSnapshot()
                }
            } else if let observedModelInterests {
                scopedInterests.applyChanges(from: observedModelInterests, to: current)
                self.observedModelInterests = current
            }
            if let encoded = try? JSONEncoder().encode(scopedInterests) {
                UserDefaults.standard.set(encoded, forKey: "bsmart.push.interests.v1.\(id.uuidString.lowercased())")
            }
        }
        synchronizeDataUpdates()
    }

    func refreshLiveHoldings(account: AccountAccessStore) async {
        guard Self.isEnabled, let id = account.identity?.id, !account.isTestSession else { return }
        if liveHoldingsAccountID != id {
            liveHoldingsAccountID = id
            liveHeldTickers = []
            lastLiveHoldingsRefresh = nil
        }
        guard notifyHoldings, lastLiveHoldingsRefresh.map({ Date().timeIntervalSince($0) > 300 }) ?? true else { return }
        lastLiveHoldingsRefresh = Date()
        do {
            let registration = try await account.walletRegistration()
            guard account.identity?.id == id, registration.accountId == id else { return }
            guard let address = registration.address else {
                liveHeldTickers = []
                interestsChanged()
                return
            }
            let positions = TradingPositionsStore(service: account)
            await positions.refresh(wallet: .init(accountID: id, address: address, recoveryVerified: false))
            guard account.identity?.id == id, positions.errorMessage == nil else { return }
            liveHeldTickers = Set(positions.rows.map { $0.symbol.uppercased() })
            interestsChanged()
        } catch {
            // A read error must not be interpreted as an empty trading account.
        }
    }

    private func synchronizeDataUpdates() {
        guard Self.isEnabled else { return }
        let validScope = scopedAccountID == account?.identity?.id
        let authors = validScope ? scopedInterests.authors.sorted() : []
        let money = validScope ? scopedInterests.money.sorted() : []
        let tickers = validScope ? scopedInterests.tickers.sorted() : []
        let holdings = (validScope ? scopedInterests.holdings : []).union(
            liveHoldingsAccountID == account?.identity?.id ? liveHeldTickers : []).sorted()
        let interests = ContentPushInterests(
            installationId: contentRegistration.installationId,
            authors: Array(authors.prefix(150)), money: Array(money.prefix(150)),
            tickers: Array(tickers.prefix(150)), holdings: Array(holdings.prefix(150)),
            notifyAuthors: notifyAuthors, notifyTickers: notifyTickers, notifyHoldings: notifyHoldings)
        contentRegistration.synchronize(token: deviceToken,
            enabled: dataUpdatesEnabled && [.authorized, .provisional].contains(authorizationStatus),
            locale: pushLocale, interests: interests)
    }

    func refreshAuthorizationStatus() async {
        guard Self.isEnabled else { return }
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        registerForRemoteNotificationsIfAuthorized()
        synchronizeDataUpdates()
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isEnabled else { return false }
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
        guard Self.isEnabled else { return }
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
        guard Self.isEnabled else { return }
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
        guard Self.isEnabled else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

@MainActor
final class BSmartAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = AppRouter()
    private var syncCoordinator: BSmartSyncCoordinator?
    private var pendingRegistration: DeviceRegistrationInput?
    private weak var notifications: NotificationService?

    func configure(syncCoordinator: BSmartSyncCoordinator?, notifications: NotificationService) {
        guard NotificationService.isEnabled else { return }
        self.syncCoordinator = syncCoordinator
        self.notifications = notifications
        if let pendingRegistration { notifications.receiveDeviceToken(pendingRegistration.apnsToken) }
        guard let pendingRegistration, let syncCoordinator else { return }
        self.pendingRegistration = nil
        Task { await syncCoordinator.enqueueDeviceRegistration(pendingRegistration) }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if NotificationService.isEnabled {
            UNUserNotificationCenter.current().delegate = self
        } else {
            application.unregisterForRemoteNotifications()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard NotificationService.isEnabled else { return }
        let registration = DeviceRegistrationInput(
            apnsToken: deviceToken.map { String(format: "%02x", $0) }.joined(),
            environment: Self.apnsEnvironment,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier
        )
        notifications?.receiveDeviceToken(registration.apnsToken)
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
        NotificationService.isEnabled ? [.banner, .sound] : []
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        notifications?.remoteRegistrationFailed()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard NotificationService.isEnabled else { return }
        let userInfo = response.notification.request.content.userInfo
        if ["content_update", "content_digest"].contains(userInfo["type"] as? String ?? "") {
            router.openNotificationInbox()
            NotificationCenter.default.post(name: .bSmartContentPushOpened, object: nil)
            return
        }
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
        ContentPushDevice.environment()
    }
}
