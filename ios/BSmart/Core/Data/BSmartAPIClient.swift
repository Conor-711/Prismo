import Foundation

protocol BSmartAPIClient {
    func fetchPortfolio() async throws -> [PortfolioPosition]
    func fetchSignals() async throws -> [PortfolioSignal]
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate]
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement]
    func fetchTickerIntelligence() async throws -> [TickerIntelligence]
    func fetchSmartAccounts() async throws -> [SmartAccountProfile]
    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate]
    func fetchSmartMoney() async throws -> [SmartMoneySignal]
    func fetchDailyDigest() async throws -> DailyDigestSnapshot?
}

protocol BSmartDataFreshnessProviding: Sendable {
    var latestDataAsOf: Date? { get }
    func freshness(for source: BSmartLiveDataSource) -> BSmartDataFreshness?
}

extension BSmartAPIClient {
    func fetchDailyDigest() async throws -> DailyDigestSnapshot? { nil }

    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] {
        try await fetchSmartAccountUpdates().filter { $0.authorId == accountID }
    }
}

enum BSmartAPIError: LocalizedError {
    case invalidResponse
    case missingFixture(String)
    case httpStatus(Int)
    case secureStorage(Int32)
    case unverifiedSmartMoney(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "bSmart returned an invalid response."
        case let .missingFixture(name): "Missing development fixture: \(name)."
        case let .httpStatus(status): "bSmart request failed with status \(status)."
        case .secureStorage: "bSmart could not access the secure installation session."
        case let .unverifiedSmartMoney(reason): "bSmart rejected unverified Smart Money data: \(reason)"
        }
    }
}

final class HTTPBSmartAPIClient: BSmartAPIClient, BSmartRemoteSyncing, BSmartDataFreshnessProviding, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let authorizationProvider: BSmartAuthorizationProviding?
    private let freshnessLock = NSLock()
    private var storedLatestDataAsOf: Date?
    private var storedFreshness: [BSmartLiveDataSource: BSmartDataFreshness] = [:]

    var latestDataAsOf: Date? {
        freshnessLock.withLock { storedLatestDataAsOf }
    }

    func freshness(for source: BSmartLiveDataSource) -> BSmartDataFreshness? {
        freshnessLock.withLock { storedFreshness[source] }
    }

    init(
        baseURL: URL,
        session: URLSession = .shared,
        authorizationProvider: BSmartAuthorizationProviding? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authorizationProvider = authorizationProvider
        self.decoder = Self.makeDecoder()
    }

    func fetchPortfolio() async throws -> [PortfolioPosition] {
        try await get("v1/portfolio")
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        try await get("v1/feed")
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] {
        try await get("v1/smart-account-updates")
    }

    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] {
        try await get("v1/smart-money-movements")
    }

    func fetchTickerIntelligence() async throws -> [TickerIntelligence] {
        try await get("v1/intelligence")
    }

    func fetchSmartAccounts() async throws -> [SmartAccountProfile] {
        try await get("v1/smart-accounts")
    }

    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] {
        let encoded = accountID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? accountID
        return try await get("v1/smart-accounts/\(encoded)/evidence")
    }

    func fetchSmartMoney() async throws -> [SmartMoneySignal] {
        let signals: [SmartMoneySignal] = try await get("v1/smart-money")
        try Self.validateSmartMoney(signals)
        return signals
    }

    func fetchDailyDigest() async throws -> DailyDigestSnapshot? {
        do {
            return try await get("v1/daily-digest")
        } catch let error as BSmartAPIError {
            if case .httpStatus(404) = error { return nil }
            throw error
        }
    }

    func fetchLegacyEvents() async throws -> [InvestmentEvent] {
        try await get("v1/events")
    }

    func fetchLegacyResearch() async throws -> [TickerResearch] {
        try await get("v1/research")
    }

    func upsertPortfolioEntry(id: UUID, input: PortfolioEntryInput) async throws {
        _ = try await request(
            "v1/portfolio/\(id.uuidString)",
            method: "PUT",
            body: try Self.makeEncoder().encode(input)
        )
    }

    func deletePortfolioEntry(id: UUID) async throws {
        _ = try await request("v1/portfolio/\(id.uuidString)", method: "DELETE")
    }

    func putSignalUserState(signalId: UUID, input: SignalUserStateInput) async throws {
        _ = try await request(
            "v1/signals/\(signalId.uuidString)/state",
            method: "PUT",
            body: try Self.makeEncoder().encode(input)
        )
    }

    func putNotificationPreferences(_ preferences: NotificationPreferences) async throws {
        _ = try await request(
            "v1/notification-preferences",
            method: "PUT",
            body: try Self.makeEncoder().encode(preferences)
        )
    }

    func putDeviceRegistration(_ registration: DeviceRegistrationInput) async throws {
        _ = try await request(
            "v1/devices",
            method: "PUT",
            body: try Self.makeEncoder().encode(registration)
        )
    }

    func postTelemetryEvent(_ event: ClientTelemetryEvent) async throws {
        _ = try await request(
            "v1/telemetry/events",
            method: "POST",
            body: try Self.makeEncoder().encode(ClientTelemetryBatch(events: [event]))
        )
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        let data = try await request(path)
        return try decoder.decode(Response.self, from: data)
    }

    private func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        for attempt in 0..<2 {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let authorizationProvider {
                let token = try await authorizationProvider.accessToken()
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BSmartAPIError.invalidResponse
            }
            if httpResponse.statusCode == 401, attempt == 0, let authorizationProvider {
                await authorizationProvider.invalidate()
                continue
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw BSmartAPIError.httpStatus(httpResponse.statusCode)
            }
            recordDataAsOf(httpResponse.value(forHTTPHeaderField: "X-BSmart-Data-As-Of"))
            recordSourceFreshness(from: httpResponse, path: path)
            return data
        }
        throw BSmartAPIError.httpStatus(401)
    }

    private func recordDataAsOf(_ value: String?) {
        guard let value,
              let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
                ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value))
        else { return }
        freshnessLock.withLock {
            if storedLatestDataAsOf == nil || date > storedLatestDataAsOf! {
                storedLatestDataAsOf = date
            }
        }
    }

    private func recordSourceFreshness(from response: HTTPURLResponse, path: String) {
        let source: BSmartLiveDataSource?
        if path == "v1/smart-account-updates" {
            source = .smartAccount
        } else if path == "v1/smart-money" || path.hasPrefix("v1/smart-money-movements") {
            source = .smartMoney
        } else {
            source = nil
        }
        guard let source,
              let checkedAt = parseServerDate(response.value(forHTTPHeaderField: "X-BSmart-Data-As-Of"))
        else { return }
        let latestContentAt = parseServerDate(
            response.value(forHTTPHeaderField: "X-BSmart-Latest-Content-At")
        )
        let itemCount = Int(
            response.value(forHTTPHeaderField: "X-BSmart-Source-Item-Count") ?? ""
        ) ?? 0
        let incoming = BSmartDataFreshness(
            checkedAt: checkedAt,
            latestContentAt: latestContentAt,
            itemCount: itemCount
        )
        freshnessLock.withLock {
            guard let current = storedFreshness[source], current.checkedAt > incoming.checkedAt else {
                storedFreshness[source] = incoming
                return
            }
        }
    }

    private func parseServerDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value))
    }

    fileprivate static func makeDecoder() -> JSONDecoder {
        BSmartJSONCoding.makeDecoder()
    }

    fileprivate static func makeEncoder() -> JSONEncoder {
        BSmartJSONCoding.makeEncoder()
    }

    static func validateSmartMoney(_ signals: [SmartMoneySignal]) throws {
        guard !signals.isEmpty else {
            throw BSmartAPIError.unverifiedSmartMoney("the live account collection is empty")
        }
        let supportedSources = Set(["hyperdash", "hyperdash_cached", "hyperliquid_fallback"])
        for signal in signals {
            guard supportedSources.contains(signal.resolvedSource) else {
                throw BSmartAPIError.unverifiedSmartMoney("account \(signal.id) has no supported source")
            }
            guard signal.sourceUpdatedAt != nil else {
                throw BSmartAPIError.unverifiedSmartMoney("account \(signal.id) has no source timestamp")
            }
            guard signal.resolvedScoreSource != "unverified" else {
                throw BSmartAPIError.unverifiedSmartMoney("account \(signal.id) has no score source")
            }
            if signal.resolvedSource == "hyperdash",
               signal.resolvedScoreSource != "hyperdash-copy-score" {
                throw BSmartAPIError.unverifiedSmartMoney("Hyperdash score provenance does not match Copy Score")
            }
        }
    }
}

final class BundleBSmartAPIClient: BSmartAPIClient {
    private let bundle: Bundle
    private let decoder = HTTPBSmartAPIClient.makeDecoder()

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func fetchPortfolio() async throws -> [PortfolioPosition] {
        try decode("portfolio")
    }

    func fetchSignals() async throws -> [PortfolioSignal] {
        try decode("portfolio-signals")
    }

    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] {
        try decode("smart-account-updates")
    }

    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] {
        try decode("smart-money-movements")
    }

    func fetchTickerIntelligence() async throws -> [TickerIntelligence] {
        try decode("ticker-intelligence")
    }

    func fetchSmartAccounts() async throws -> [SmartAccountProfile] {
        try decode("smart-accounts")
    }

    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] {
        let evidence: [SmartAccountUpdate] = try decode("smart-account-evidence")
        return evidence.filter { $0.authorId == accountID }
    }

    func fetchSmartMoney() async throws -> [SmartMoneySignal] {
        try decode("smart-money")
    }

    private func decode<Response: Decodable>(_ name: String) throws -> Response {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw BSmartAPIError.missingFixture(name)
        }
        return try decoder.decode(Response.self, from: Data(contentsOf: url))
    }
}
