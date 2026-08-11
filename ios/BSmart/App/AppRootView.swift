import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var language: AppLanguageStore

    var body: some View {
        Group {
            if !model.hasFinishedInitialLoad {
                BSmartLoadingView()
            } else if let errorMessage = model.errorMessage, model.signals.isEmpty {
                BSmartErrorView(message: errorMessage) {
                    Task { await model.retry() }
                }
            } else if !model.hasCompletedPortfolioSetup {
                PortfolioSetupView()
            } else {
                TabView(selection: $router.selection) {
                    TodayView()
                        .tag(AppSection.today)
                        .tabItem { Label(language.localized("Today"), systemImage: "house.fill") }
                        .badge(model.unreadPortfolioSignalCount)

                    SmartHubView()
                        .tag(AppSection.smart)
                        .tabItem { Label(language.localized("Smart"), systemImage: "bolt.horizontal.circle.fill") }

                    PortfolioView()
                        .tag(AppSection.portfolio)
                        .tabItem { Label(language.localized("Portfolio"), systemImage: "chart.pie.fill") }

                    ResearchView()
                        .tag(AppSection.research)
                        .tabItem { Label(language.localized("Research"), systemImage: "magnifyingglass") }
                }
                .tint(BSmartColor.pulse)
                .toolbarBackground(BSmartColor.surface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
            }
        }
        .bSmartPage()
    }
}
