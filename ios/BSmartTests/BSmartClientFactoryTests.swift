import XCTest
@testable import BSmart

final class BSmartClientFactoryTests: XCTestCase {
    func testDebugDefaultsToFixturesAndRequiresAnExplicitLiveOptIn() throws {
        let configuredURL = "https://staging.bsmart.test"

        XCTAssertEqual(
            BSmartRuntimeConfiguration.resolve(
                arguments: [],
                environment: [:],
                configuredBaseURL: configuredURL,
                isDebug: true
            ).dataSource,
            .fixture
        )
        XCTAssertEqual(
            BSmartRuntimeConfiguration.resolve(
                arguments: ["--use-fixture-data"],
                environment: [:],
                configuredBaseURL: configuredURL,
                isDebug: true
            ).dataSource,
            .fixture
        )
        XCTAssertEqual(
            BSmartRuntimeConfiguration.resolve(
                arguments: ["--use-live-api"],
                environment: [:],
                configuredBaseURL: configuredURL,
                isDebug: true
            ).dataSource,
            .live(try XCTUnwrap(URL(string: configuredURL)))
        )
        XCTAssertEqual(
            BSmartRuntimeConfiguration.resolve(
                arguments: [],
                environment: ["BSMART_USE_LIVE_API": "1"],
                configuredBaseURL: configuredURL,
                isDebug: true
            ).dataSource,
            .live(try XCTUnwrap(URL(string: configuredURL)))
        )
        XCTAssertEqual(
            BSmartRuntimeConfiguration.resolve(
                arguments: [],
                environment: [:],
                configuredBaseURL: configuredURL,
                isDebug: false
            ).dataSource,
            .live(try XCTUnwrap(URL(string: configuredURL)))
        )
    }

    func testInternalAlphaUsesLiveTransportButKeepsDemoDisclosure() throws {
        let configuredURL = "https://mock-api.bsmart.test"
        let configuration = BSmartRuntimeConfiguration.resolve(
            arguments: [],
            environment: [:],
            configuredBaseURL: configuredURL,
            configuredDataEnvironment: "demo",
            isDebug: false
        )

        XCTAssertEqual(
            configuration.dataSource,
            .live(try XCTUnwrap(URL(string: configuredURL)))
        )
        XCTAssertTrue(configuration.isUsingDemoData)
    }

    func testInstallationIdentityPersistsForTheSameAppInstallation() throws {
        let suiteName = "BSmartClientFactoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = InstallationIdentity.resolve(defaults: defaults)
        let second = InstallationIdentity.resolve(defaults: defaults)

        XCTAssertEqual(first, second)
    }

    func testJSONDecoderAcceptsFractionalISO8601DatesFromClientAPI() throws {
        let installationId = UUID()
        let payload = Data(
            """
            {
              "installationId": "\(installationId.uuidString)",
              "accessToken": "test-token",
              "expiresAt": "2026-11-02T15:10:14.090289Z"
            }
            """.utf8
        )

        let session = try BSmartJSONCoding.makeDecoder().decode(
            InstallationSession.self,
            from: payload
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = try XCTUnwrap(formatter.date(from: "2026-11-02T15:10:14.090289Z"))

        XCTAssertEqual(session.installationId, installationId)
        XCTAssertEqual(session.accessToken, "test-token")
        XCTAssertEqual(session.expiresAt.timeIntervalSince1970, expectedDate.timeIntervalSince1970, accuracy: 0.001)
    }

    func testJSONDecoderAcceptsLegacyNumericKeychainDates() throws {
        let expected = InstallationSession(
            installationId: UUID(),
            accessToken: "legacy-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let legacyData = try JSONEncoder().encode(expected)

        let decoded = try BSmartJSONCoding.makeDecoder().decode(
            InstallationSession.self,
            from: legacyData
        )

        XCTAssertEqual(decoded, expected)
    }

    func testLiveSmartMoneyRequiresVerifiableHyperdashProvenance() throws {
        let valid = Data(
            """
            [{
              "id": "0x123",
              "walletLabel": "0x123",
              "score": 91.2,
              "ticker": "NVDA",
              "direction": "Long",
              "notionalValue": 125000,
              "changedAt": "2026-08-07T00:00:00Z",
              "scoreSource": "hyperdash-copy-score",
              "source": "hyperdash",
              "sourceUpdatedAt": "2026-08-07T00:10:00Z",
              "sourceURL": "https://hyperdash.com/trader/0x123"
            }]
            """.utf8
        )
        let signals = try BSmartJSONCoding.makeDecoder().decode([SmartMoneySignal].self, from: valid)

        XCTAssertNoThrow(try HTTPBSmartAPIClient.validateSmartMoney(signals))

        let unverified = Data(
            """
            [{
              "id": "0x123",
              "walletLabel": "0x123",
              "score": 91.2,
              "ticker": "NVDA",
              "direction": "Long",
              "notionalValue": 125000,
              "changedAt": "2026-08-07T00:00:00Z"
            }]
            """.utf8
        )
        let unverifiedSignals = try BSmartJSONCoding.makeDecoder().decode(
            [SmartMoneySignal].self,
            from: unverified
        )

        XCTAssertThrowsError(try HTTPBSmartAPIClient.validateSmartMoney(unverifiedSignals))
    }

    func testLiveClientRegistersOnceAndAuthorizesSubsequentRequests() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://api.bsmart.test"))
        let installationId = UUID()
        let portfolioId = UUID()
        let signalId = UUID()
        let store = MemoryInstallationSessionStore()
        let requests = RequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BSmartStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        BSmartStubURLProtocol.handler = { request in
            await requests.append(request)

            switch request.url?.path {
            case "/v1/installations":
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = try XCTUnwrap(request.bodyData)
                let registration = try JSONDecoder().decode(InstallationRegistration.self, from: body)
                XCTAssertEqual(registration.installationId, installationId)
                let response = InstallationSession(
                    installationId: installationId,
                    accessToken: "test-token",
                    expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                return (201, try encoder.encode(response))
            case "/v1/feed", "/v1/intelligence":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                return (200, Data("[]".utf8))
            case "/v1/portfolio/\(portfolioId.uuidString)":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
                if request.httpMethod == "PUT" {
                    let input = try JSONDecoder().decode(
                        PortfolioEntryInput.self,
                        from: try XCTUnwrap(request.bodyData)
                    )
                    XCTAssertEqual(input.ticker, "NVDA")
                } else {
                    XCTAssertEqual(request.httpMethod, "DELETE")
                }
                return (204, Data())
            case "/v1/signals/\(signalId.uuidString)/state":
                XCTAssertEqual(request.httpMethod, "PUT")
                let input = try JSONDecoder().decode(
                    SignalUserStateInput.self,
                    from: try XCTUnwrap(request.bodyData)
                )
                XCTAssertTrue(input.isSaved)
                return (200, Data("{}".utf8))
            case "/v1/notification-preferences":
                XCTAssertEqual(request.httpMethod, "PUT")
                return (200, Data("{}".utf8))
            case "/v1/devices":
                XCTAssertEqual(request.httpMethod, "PUT")
                let input = try JSONDecoder().decode(
                    DeviceRegistrationInput.self,
                    from: try XCTUnwrap(request.bodyData)
                )
                XCTAssertEqual(input.apnsToken, "a1b2")
                return (204, Data())
            default:
                XCTFail("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return (404, Data())
            }
        }
        defer { BSmartStubURLProtocol.handler = nil }

        let authorization = AnonymousInstallationSessionProvider(
            baseURL: baseURL,
            urlSession: session,
            store: store,
            registration: InstallationRegistration(
                installationId: installationId,
                platform: "ios",
                appVersion: "1.0",
                locale: "en_US",
                timeZone: "UTC"
            ),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let client = HTTPBSmartAPIClient(
            baseURL: baseURL,
            session: session,
            authorizationProvider: authorization
        )

        async let signals = client.fetchSignals()
        async let intelligence = client.fetchTickerIntelligence()
        _ = try await (signals, intelligence)
        try await client.upsertPortfolioEntry(
            id: portfolioId,
            input: PortfolioEntryInput(position: PortfolioPosition(
                id: portfolioId,
                ticker: "NVDA",
                companyName: "NVIDIA",
                shares: 2,
                averageCost: 100,
                currentPrice: 120,
                entryKind: .position
            ))
        )
        try await client.deletePortfolioEntry(id: portfolioId)
        try await client.putSignalUserState(
            signalId: signalId,
            input: SignalUserStateInput(state: SignalUserState(signalId: signalId, isSaved: true))
        )
        try await client.putNotificationPreferences(NotificationPreferences())
        try await client.putDeviceRegistration(DeviceRegistrationInput(
            apnsToken: "a1b2",
            environment: "development",
            appVersion: "1.0",
            locale: "en_US",
            timeZone: "UTC"
        ))

        let recordedRequests = await requests.values
        XCTAssertEqual(recordedRequests.filter { $0.url?.path == "/v1/installations" }.count, 1)
        XCTAssertEqual(recordedRequests.count, 8)
        XCTAssertEqual(try store.load()?.accessToken, "test-token")
        XCTAssertEqual(
            try XCTUnwrap(client.latestDataAsOf).timeIntervalSince1970,
            Date(timeIntervalSince1970: 1_786_036_260).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testLiveClientRecordsPerSourceFreshness() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://api.bsmart.test"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BSmartStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        BSmartStubURLProtocol.handler = { _ in (200, Data("[]".utf8)) }
        defer { BSmartStubURLProtocol.handler = nil }
        let client = HTTPBSmartAPIClient(baseURL: baseURL, session: session)

        _ = try await client.fetchSmartAccountUpdates()

        let freshness = try XCTUnwrap(client.freshness(for: .smartAccount))
        XCTAssertEqual(freshness.itemCount, 4)
        XCTAssertEqual(
            freshness.latestContentAt,
            try Date.ISO8601FormatStyle().parse("2026-08-06T16:00:00Z")
        )
        XCTAssertTrue(freshness.hasNoNewQualifiedContent)
    }
}

private final class MemoryInstallationSessionStore: InstallationSessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var session: InstallationSession?

    func load() throws -> InstallationSession? {
        lock.withLock { session }
    }

    func save(_ session: InstallationSession) throws {
        lock.withLock { self.session = session }
    }

    func clear() throws {
        lock.withLock { session = nil }
    }
}

private actor RequestRecorder {
    private(set) var values: [URLRequest] = []

    func append(_ request: URLRequest) {
        values.append(request)
    }
}

private final class BSmartStubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (statusCode: Int, data: Data)
    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: BSmartAPIError.invalidResponse)
            return
        }

        Task {
            do {
                let result = try await handler(request)
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: result.statusCode,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json",
                        "X-BSmart-Data-As-Of": "2026-08-06T17:11:00Z",
                        "X-BSmart-Latest-Content-At": "2026-08-06T16:00:00Z",
                        "X-BSmart-Source-Item-Count": "4",
                    ]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: result.data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
