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
        _accountAccess = StateObject(wrappedValue: access)
        _deviceWallet = StateObject(wrappedValue: DeviceWalletStore(service: access))
        _accountDeletion = StateObject(wrappedValue: AccountDeletionCoordinator(client: accountClient as? AccountDeleting,
            storage: deletionStorage, cleanup: DeviceAccountDeletionCleanup(account: access),
            google: NativeGoogleAccountDisconnector(), endpoint: (accountClient as? HTTPAccountAuthClient)?.accountDeletionEndpoint
                ?? URL(string: "https://api.bsmart.today/v1/auth/account/deletions")!))
        _model = StateObject(wrappedValue: AppModel(
            client: client,
            bootstrapFallbackClient: isUsingDemoData ? nil : BundleBSmartAPIClient(),
            directMrCollieClient: directMrCollieClient,
            portfolioBootstrapStrategy: portfolioBootstrapStrategy,
            syncCoordinator: syncCoordinator,
            isUsingDemoData: isUsingDemoData
        ))
        _notificationPreferences = StateObject(wrappedValue: NotificationPreferencesStore(
            syncCoordinator: syncCoordinator
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
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
                .onChange(of: accountAccess.identity) { _, _ in deviceWallet.lock() }
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
                    appDelegate.configure(syncCoordinator: syncCoordinator)
                    await syncCoordinator?.flush()
                    await model.load()
                    await notificationPreferences.synchronize()
                    await notifications.refreshAuthorizationStatus()
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
                .task(id: scenePhase) {
                    guard scenePhase == .active, !model.isUsingDemoData else { return }
                    while !Task.isCancelled {
                        if model.hasFinishedInitialLoad {
                            await model.refreshLiveIntelligence()
                        }
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
        }
    }
}
