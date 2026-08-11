#if DEBUG
import SwiftUI

private struct AppStatePreview: View {
    @StateObject private var model: AppModel
    @StateObject private var router = AppRouter()
    @StateObject private var notifications = NotificationService()
    @StateObject private var notificationPreferences: NotificationPreferencesStore
    @StateObject private var language: AppLanguageStore

    init(scenario: DebugDataScenario, localOnly: Bool = false) {
        let suiteName = "BSmartPreview.\(scenario.rawValue).\(localOnly)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        _model = StateObject(wrappedValue: AppModel(
            client: DebugBSmartAPIClient(scenario: scenario),
            defaults: defaults,
            portfolioBootstrapStrategy: localOnly ? .localOnly : .remoteFallback
        ))
        _notificationPreferences = StateObject(wrappedValue: NotificationPreferencesStore(defaults: defaults))
        _language = StateObject(wrappedValue: AppLanguageStore(defaults: defaults))
    }

    var body: some View {
        AppRootView()
            .environmentObject(model)
            .environmentObject(router)
            .environmentObject(notifications)
            .environmentObject(notificationPreferences)
            .environmentObject(language)
            .environment(\.locale, language.locale)
            .preferredColorScheme(.dark)
            .task { await model.load() }
    }
}

private struct SignalLibraryPreview: View {
    @StateObject private var model: AppModel

    init() {
        let suiteName = "BSmartPreview.signal-library"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        _model = StateObject(wrappedValue: AppModel(
            client: DebugBSmartAPIClient(scenario: .loaded),
            defaults: defaults,
            portfolioBootstrapStrategy: .remoteFallback
        ))
    }

    var body: some View {
        SignalLibraryView()
            .environmentObject(model)
            .preferredColorScheme(.dark)
            .task {
                await model.load()
                guard model.signals.count >= 2 else { return }
                model.toggleSignalSaved(model.signals[0].id)
                model.ignoreSignal(model.signals[1].id)
            }
    }
}

#Preview("App · Loaded") {
    AppStatePreview(scenario: .loaded)
}

#Preview("App · First use") {
    AppStatePreview(scenario: .loaded, localOnly: true)
}

#Preview("App · Loading") {
    AppStatePreview(scenario: .loading)
}

#Preview("App · Error") {
    AppStatePreview(scenario: .error)
}

#Preview("Today · No signals") {
    AppStatePreview(scenario: .noSignals)
}

#Preview("Signal library · Saved and ignored") {
    SignalLibraryPreview()
}
#endif
