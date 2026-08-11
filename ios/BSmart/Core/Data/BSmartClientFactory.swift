import Foundation

enum BSmartDataSource: Equatable {
    case fixture
    case live(URL)
}

struct BSmartRuntimeConfiguration: Equatable {
    static let productionBaseURL = URL(string: "https://api.bsmart.today")!

    let dataSource: BSmartDataSource
    let isUsingDemoData: Bool

    static func resolve(
        arguments: [String],
        environment: [String: String],
        configuredBaseURL: String?,
        configuredDataEnvironment: String? = nil,
        isDebug: Bool
    ) -> BSmartRuntimeConfiguration {
        let requestsFixtures = arguments.contains("--use-fixture-data")
            || environment["BSMART_USE_FIXTURE_DATA"] == "1"
        let requestsLiveAPI = arguments.contains("--use-live-api")
            || environment["BSMART_USE_LIVE_API"] == "1"
        if isDebug && (requestsFixtures || !requestsLiveAPI) {
            return BSmartRuntimeConfiguration(dataSource: .fixture, isUsingDemoData: true)
        }

        let candidate = environment["BSMART_API_BASE_URL"] ?? configuredBaseURL
        let url = candidate.flatMap(validBaseURL) ?? productionBaseURL
        let dataEnvironment = environment["BSMART_DATA_ENVIRONMENT"] ?? configuredDataEnvironment
        return BSmartRuntimeConfiguration(
            dataSource: .live(url),
            isUsingDemoData: dataEnvironment?.lowercased() == "demo"
        )
    }

    private static func validBaseURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }
}

struct BSmartClientComposition {
    let client: BSmartAPIClient
    let portfolioBootstrapStrategy: PortfolioBootstrapStrategy
    let syncCoordinator: BSmartSyncCoordinator?
    let isUsingDemoData: Bool
}

enum BSmartClientFactory {
    static func make(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        urlSession: URLSession = .shared,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BSmartClientComposition {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif

        let configuration = BSmartRuntimeConfiguration.resolve(
            arguments: arguments,
            environment: environment,
            configuredBaseURL: bundle.object(forInfoDictionaryKey: "BSMART_API_BASE_URL") as? String,
            configuredDataEnvironment: bundle.object(forInfoDictionaryKey: "BSMART_DATA_ENVIRONMENT") as? String,
            isDebug: isDebug
        )

        switch configuration.dataSource {
        case .fixture:
            #if DEBUG
            print("[BSmart Data] fixture bundle")
            #endif
            return BSmartClientComposition(
                client: BundleBSmartAPIClient(bundle: bundle),
                portfolioBootstrapStrategy: .localOnly,
                syncCoordinator: nil,
                isUsingDemoData: true
            )
        case let .live(baseURL):
            #if DEBUG
            print("[BSmart Data] live API: \(baseURL.absoluteString)")
            #endif
            let installationId = InstallationIdentity.resolve(defaults: defaults)
            let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let registration = InstallationRegistration(
                installationId: installationId,
                platform: "ios",
                appVersion: appVersion,
                locale: Locale.current.identifier,
                timeZone: TimeZone.current.identifier
            )
            let tokenStore = KeychainInstallationSessionStore(
                service: bundle.bundleIdentifier ?? "today.bsmart.ios",
                account: installationId.uuidString
            )
            let authorization = AnonymousInstallationSessionProvider(
                baseURL: baseURL,
                urlSession: urlSession,
                store: tokenStore,
                registration: registration
            )
            let client = HTTPBSmartAPIClient(
                baseURL: baseURL,
                session: urlSession,
                authorizationProvider: authorization
            )
            return BSmartClientComposition(
                client: client,
                portfolioBootstrapStrategy: .remoteFallback,
                syncCoordinator: BSmartSyncCoordinator(client: client, defaults: defaults),
                isUsingDemoData: configuration.isUsingDemoData
            )
        }
    }
}
