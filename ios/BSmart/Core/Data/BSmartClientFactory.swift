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
    let directMrCollieClient: DirectMrCollieAnswering?
    let portfolioBootstrapStrategy: PortfolioBootstrapStrategy
    let syncCoordinator: BSmartSyncCoordinator?
    let isUsingDemoData: Bool
    let accountClient: AccountAuthenticating?
}

enum BSmartClientFactory {
    @MainActor
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

        let contentBackend = environment["BSMART_CONTENT_BACKEND"]
            ?? bundle.object(forInfoDictionaryKey: "BSMART_CONTENT_BACKEND") as? String

        let configuration = BSmartRuntimeConfiguration.resolve(
            arguments: arguments + (contentBackend == "supabase" ? ["--use-live-api"] : []),
            environment: environment,
            configuredBaseURL: bundle.object(forInfoDictionaryKey: "BSMART_API_BASE_URL") as? String,
            configuredDataEnvironment: bundle.object(forInfoDictionaryKey: "BSMART_DATA_ENVIRONMENT") as? String,
            isDebug: isDebug
        )
        let directMrCollieClient = DirectDeepSeekConfiguration.resolve(
            environment: environment,
            configuredAPIKey: bundle.object(forInfoDictionaryKey: "BSMART_DEEPSEEK_API_KEY") as? String,
            configuredBaseURL: bundle.object(forInfoDictionaryKey: "BSMART_DEEPSEEK_BASE_URL") as? String,
            configuredModel: bundle.object(forInfoDictionaryKey: "BSMART_MR_COLLIE_MODEL") as? String
        ).map { DirectDeepSeekMrCollieClient(configuration: $0, session: urlSession) }
        let accountClient = SupabaseAccountConfiguration.resolve(bundle: bundle).map {
            SupabaseAccountAuthClient(configuration: $0)
        }

        switch configuration.dataSource {
        case .fixture:
            #if DEBUG
            print("[BSmart Data] fixture bundle")
            #endif
            return BSmartClientComposition(
                client: BundleBSmartAPIClient(bundle: bundle),
                directMrCollieClient: directMrCollieClient,
                portfolioBootstrapStrategy: .localOnly,
                syncCoordinator: nil,
                isUsingDemoData: true,
                accountClient: accountClient
            )
        case let .live(baseURL):
            if contentBackend == "supabase" {
                return BSmartClientComposition(
                    client: SupabaseContentClient(configuration: SupabaseAccountConfiguration.resolve(bundle: bundle)),
                    directMrCollieClient: directMrCollieClient,
                    portfolioBootstrapStrategy: .localOnly,
                    syncCoordinator: nil,
                    isUsingDemoData: configuration.isUsingDemoData,
                    accountClient: accountClient
                )
            }
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
                directMrCollieClient: directMrCollieClient,
                portfolioBootstrapStrategy: .remoteFallback,
                syncCoordinator: BSmartSyncCoordinator(client: client, defaults: defaults),
                isUsingDemoData: configuration.isUsingDemoData,
                accountClient: accountClient
            )
        }
    }
}
