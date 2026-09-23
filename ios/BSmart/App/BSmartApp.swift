import SwiftUI
import GoogleSignIn
import AuthenticationServices

@main
struct BSmartApp: App {
    @UIApplicationDelegateAdaptor(BSmartAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var notifications = NotificationService()
    @StateObject private var notificationPreferences: NotificationPreferencesStore
    @StateObject private var language: AppLanguageStore
    @StateObject private var appearance: AppAppearanceStore
    @StateObject private var hyperliquidTrading: HyperliquidTradingStore
    @StateObject private var paperTrading: PaperTradingEngine
    @StateObject private var accountAccess: AccountAccessStore
    @StateObject private var deviceWallet: DeviceWalletStore
    @StateObject private var accountDeletion: AccountDeletionCoordinator
    private let syncCoordinator: BSmartSyncCoordinator?
    private let embeddedWallet: PrivyEmbeddedWalletClient

    init() {
        let client: BSmartAPIClient
        let portfolioBootstrapStrategy: PortfolioBootstrapStrategy
        let directMrCollieClient: DirectMrCollieAnswering?
        let syncCoordinator: BSmartSyncCoordinator?
        let isUsingDemoData: Bool
        let accountClient: AccountAuthenticating?

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-reset-state"),
           let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        if let scenario = DebugDataScenario.launched {
            client = DebugBSmartAPIClient(scenario: scenario)
            portfolioBootstrapStrategy = .remoteFallback
            syncCoordinator = nil
            directMrCollieClient = nil
            isUsingDemoData = true
            accountClient = nil
        } else {
            let composition = BSmartClientFactory.make()
            client = composition.client
            portfolioBootstrapStrategy = composition.portfolioBootstrapStrategy
            syncCoordinator = composition.syncCoordinator
            directMrCollieClient = composition.directMrCollieClient
            isUsingDemoData = composition.isUsingDemoData
            accountClient = composition.accountClient
        }
        #else
        let composition = BSmartClientFactory.make()
        client = composition.client
        portfolioBootstrapStrategy = composition.portfolioBootstrapStrategy
        syncCoordinator = composition.syncCoordinator
        directMrCollieClient = composition.directMrCollieClient
        isUsingDemoData = composition.isUsingDemoData
        accountClient = composition.accountClient
        #endif

        self.syncCoordinator = syncCoordinator
        _language = StateObject(wrappedValue: AppLanguageStore())
        _appearance = StateObject(wrappedValue: AppAppearanceStore())
        let marketClient: HyperliquidMarketDataClient
        #if DEBUG
        marketClient = ProcessInfo.processInfo.arguments.contains("--ui-trading-fixture")
            ? DebugTradingMarketClient()
            : HTTPHyperliquidMarketDataClient()
        #else
        marketClient = HTTPHyperliquidMarketDataClient()
        #endif
        _hyperliquidTrading = StateObject(wrappedValue: HyperliquidTradingStore(client: marketClient))
        _paperTrading = StateObject(wrappedValue: PaperTradingEngine())
        let deletionStorage = KeychainAccountDeletionStore(service:
            (Bundle.main.bundleIdentifier ?? "today.bsmart.ios") + (isUsingDemoData ? ".demo" : ""))
        let accountNamespace = SupabaseAccountConfiguration.resolve()?.sessionNamespace ?? "supabase.unconfigured"
        let accountStorage = KeychainAccountSessionStore(service:
            (Bundle.main.bundleIdentifier ?? "today.bsmart.ios") + "." + accountNamespace)
        let access = AccountAccessStore(client: accountClient, storage: accountStorage, deletionStorage: deletionStorage)
        (client as? SupabaseContentClient)?.bind(account: access)
        _accountAccess = StateObject(wrappedValue: access)
        let preferences: AccountPreferencesProviding? = isUsingDemoData ? nil : NativeAccountPreferencesClient(client: NativeTradeFeedClient(
            account: access,
            transport: SupabaseAccountConfiguration.resolve().map {
                SupabaseAccountTransport(configuration: $0, requestTimeout: 8, resourceTimeout: 12)
            }
        ))
        let embedded = PrivyEmbeddedWalletClient(account: access)
        embeddedWallet = embedded
        let vault = HybridTradingWalletVault(embedded: embedded)
        _deviceWallet = StateObject(wrappedValue: DeviceWalletStore(service: access, vault: vault, signing: vault))
        _accountDeletion = StateObject(wrappedValue: AccountDeletionCoordinator(client: accountClient as? AccountDeleting,
            storage: deletionStorage, cleanup: DeviceAccountDeletionCleanup(account: access),
            google: NativeGoogleAccountDisconnector(), endpoint: (accountClient as? HTTPAccountAuthClient)?.accountDeletionEndpoint
                ?? URL(string: "https://api.bsmart.today/v1/auth/account/deletions")!))
        _model = StateObject(wrappedValue: AppModel(
            client: client,
            bootstrapFallbackClient: isUsingDemoData ? nil : BundleBSmartAPIClient(),
            accountPreferences: preferences,
            directMrCollieClient: directMrCollieClient,
            portfolioBootstrapStrategy: portfolioBootstrapStrategy,
            syncCoordinator: syncCoordinator,
            isUsingDemoData: isUsingDemoData
        ))
        _notificationPreferences = StateObject(wrappedValue: NotificationPreferencesStore(
            syncCoordinator: syncCoordinator
        ))
    }

    private var mayLoadContent: Bool {
        #if DEBUG
        if DebugDataScenario.launched != nil && model.isUsingDemoData
            && !ProcessInfo.processInfo.arguments.contains("--ui-auth-gate") { return true }
        #endif
        return accountAccess.canAccessAppContent || accountAccess.isTestSession
    }

    private var contentSessionID: String {
        "\(mayLoadContent):\(accountAccess.identity?.id.uuidString.lowercased() ?? "guest")"
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .background(BSmartKeyboardDismissal().frame(width: 0, height: 0))
                .scrollDismissesKeyboard(.interactively)
                .environmentObject(model)
                .environmentObject(appDelegate.router)
                .environmentObject(notifications)
                .environmentObject(notificationPreferences)
                .environmentObject(language)
                .environmentObject(appearance)
                .environmentObject(hyperliquidTrading)
                .environmentObject(paperTrading)
                .environmentObject(accountAccess)
                .environmentObject(deviceWallet)
                .environmentObject(accountDeletion)
                .onChange(of: accountAccess.isTestSession) { _, _ in
                    appDelegate.router.resetForAccountChange()
                    deviceWallet.lock()
                    model.activateAccountContext(accountAccess.identity?.id)
                }
                .onChange(of: accountAccess.identity) { previous, current in
                    if previous != nil && previous?.id != current?.id {
                        appDelegate.router.resetForAccountChange()
                    }
                    model.activateAccountContext(current?.id)
                    notifications.accountChanged()
                    deviceWallet.lock()
                    Task { await embeddedWallet.accountDidChange() }
                }
                .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)
                    .receive(on: DispatchQueue.main)) { _ in
                    accountAccess.appleCredentialDidChange()
                    Task { await accountAccess.recheckAppleCredential() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { deviceWallet.lock() }
                }
                .environment(\.locale, language.locale)
                .preferredColorScheme(appearance.selection.colorScheme)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    appDelegate.router.handle(url: url)
                }
                .task {
                    notifications.bind(account: accountAccess, model: model)
                    appDelegate.configure(syncCoordinator: syncCoordinator, notifications: notifications)
                }
                .onReceive(NotificationCenter.default.publisher(for: .bSmartContentPushOpened)) { _ in
                    guard mayLoadContent else { return }
                    Task { await model.refreshLiveIntelligence() }
                }
                .task(id: contentSessionID) {
                    guard mayLoadContent else { return }
                    model.activateAccountContext(accountAccess.identity?.id)
                    Task { await syncCoordinator?.flush() }
                    let contentLoad = Task { await model.load() }
                    await model.restoreAccountState()
                    await contentLoad.value
                    notifications.contentDidFinishLoading()
                    await notificationPreferences.synchronize()
                    await notifications.refreshAuthorizationStatus()
                    if NotificationService.isEnabled && !accountAccess.isTestSession && !model.isUsingDemoData && notifications.dataUpdatesEnabled
                        && notifications.authorizationStatus == .notDetermined {
                        await notifications.requestAuthorization()
                    }
                    #if DEBUG
                    appDelegate.router.applyDebugLaunchSection(from: ProcessInfo.processInfo.arguments)
                    #endif
                }
                // System authentication may briefly make the scene inactive without leaving the app.
                .task(id: scenePhase == .background) {
                    guard scenePhase != .background else { return }
                    await accountAccess.maintainSession()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, !model.isUsingDemoData else { return }
                    try? await accountDeletion.resume()
                }
                .task(id: "\(scenePhase):\(mayLoadContent)") {
                    guard scenePhase == .active, mayLoadContent, !model.isUsingDemoData else { return }
                    while !Task.isCancelled {
                        if model.hasFinishedInitialLoad {
                            await model.refreshLiveIntelligence()
                        }
                        await model.synchronizePendingFollows()
                        notifications.setPushLocale(language.locale.identifier)
                        await notifications.refreshAuthorizationStatus()
                        await notifications.refreshLiveHoldings(account: accountAccess)
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
                .onChange(of: model.followedSmartAccountIDs) { notifications.interestsChanged() }
                .onChange(of: model.followedSmartMoneyIDs) { notifications.interestsChanged() }
                .onChange(of: model.positions) { notifications.interestsChanged() }
        }
    }
}
