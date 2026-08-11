import SwiftUI

@main
struct BSmartApp: App {
    @UIApplicationDelegateAdaptor(BSmartAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var notifications = NotificationService()
    @StateObject private var notificationPreferences: NotificationPreferencesStore
    @StateObject private var language: AppLanguageStore
    private let syncCoordinator: BSmartSyncCoordinator?

    init() {
        let client: BSmartAPIClient
        let portfolioBootstrapStrategy: PortfolioBootstrapStrategy
        let syncCoordinator: BSmartSyncCoordinator?
        let isUsingDemoData: Bool

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-reset-state"),
           let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }

        if let scenario = DebugDataScenario.launched {
            client = DebugBSmartAPIClient(scenario: scenario)
            portfolioBootstrapStrategy = .remoteFallback
            syncCoordinator = nil
            isUsingDemoData = true
        } else {
            let composition = BSmartClientFactory.make()
            client = composition.client
            portfolioBootstrapStrategy = composition.portfolioBootstrapStrategy
            syncCoordinator = composition.syncCoordinator
            isUsingDemoData = composition.isUsingDemoData
        }
        #else
        let composition = BSmartClientFactory.make()
        client = composition.client
        portfolioBootstrapStrategy = composition.portfolioBootstrapStrategy
        syncCoordinator = composition.syncCoordinator
        isUsingDemoData = composition.isUsingDemoData
        #endif

        self.syncCoordinator = syncCoordinator
        _language = StateObject(wrappedValue: AppLanguageStore())
        _model = StateObject(wrappedValue: AppModel(
            client: client,
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
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
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
