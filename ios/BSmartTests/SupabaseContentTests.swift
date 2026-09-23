import XCTest
@testable import BSmart

@MainActor
final class SupabaseContentTests: XCTestCase {
    @MainActor private final class Server {
        var version = "a"
        var failingCollection: String?
        var malformedCollection: String?
        var wrongRevision = false
        var accountName = "Original"
        var accountCount = 1
        var requests: [String] = []
        var manifestFailure = false
        var manifestHook: (() -> Void)?
        var pageHook: (() async throws -> Void)?

        var revision: String { String(repeating: version, count: 64) }
        func request(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
            let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
            if path == "manifest" {
                requests.append("manifest")
                manifestHook?()
                if manifestFailure { throw BSmartAPIError.httpStatus(503) }
                let entries = Dictionary(uniqueKeysWithValues: SupabaseContentManifest.names.map { name in
                    // Only author content changes between the two releases.
                    (name, ["count": name == "smart-accounts" ? accountCount : 0,
                            "sha256": String(repeating: name == "smart-accounts" ? version : "c", count: 64),
                            "checkedAt": "2026-09-01T00:00:00Z", "latestContentAt": NSNull()] as [String: Any])
                })
                return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "revision": revision, "collections": entries])
            }
            let name = values["collection"]!
            requests.append(name)
            if name == failingCollection { throw BSmartAPIError.httpStatus(503) }
            if let pageHook { try await pageHook() }
            let page = Int(values["page"] ?? "0")!
            let total = name == "smart-accounts" ? accountCount : 0
            var items: [[String: Any]] = (0..<total).dropFirst(page * 100).prefix(100).map { index in [
                "id": index == 0 ? "x:a" : "x:a\(index)", "name": accountName, "handle": "a", "platform": "X", "score": 110,
                "scoreChange": 0, "specialty": "Semiconductors", "horizon": "20D",
            ] }
            if name == malformedCollection { items = [["broken": true]] }
            return try JSONSerialization.data(withJSONObject: ["revision": wrongRevision ? String(repeating: "f", count: 64) : values["revision"]!,
                "page": page, "pages": max(1, (total + 99) / 100), "total": total, "items": items])
        }
        func client() -> SupabaseContentClient {
            SupabaseContentClient { [self] path, query in try await request(path, query) }
        }
    }

    func testSameInstalledClientReceivesNewAuthorsWithoutAppUpdate() async throws {
        let server = Server(), client: SupabaseContentClient
        client = server.client()
        try await client.prepareContentRefresh()
        let first = try await client.fetchSmartAccounts()
        XCTAssertEqual(first.first?.name, "Original")
        server.version = "b"; server.accountName = "Updated"
        server.requests = []
        try await client.prepareContentRefresh()
        let second = try await client.fetchSmartAccounts()
        XCTAssertEqual(second.first?.name, "Updated")
        XCTAssertEqual(server.requests, ["manifest", "smart-accounts"])
    }

    func testUnchangedManifestDoesNotDownloadCollections() async throws {
        let server = Server(), client: SupabaseContentClient
        client = server.client()
        try await client.prepareContentRefresh()
        server.requests = []
        try await client.prepareContentRefresh()
        XCTAssertEqual(server.requests, ["manifest"])
        XCTAssertNotNil(client.freshness(for: .smartAccount))
    }

    func testFailedRevisionKeepsOldSnapshotAndFreshness() async throws {
        let server = Server(), client: SupabaseContentClient
        client = server.client()
        try await client.prepareContentRefresh()
        let timestamp = client.latestDataAsOf
        server.version = "b"; server.accountName = "Never committed"; server.failingCollection = "smart-accounts"
        do { try await client.prepareContentRefresh(); XCTFail("Must reject partial revision") } catch {}
        let accounts = try await client.fetchSmartAccounts()
        XCTAssertEqual(accounts.first?.name, "Original")
        XCTAssertEqual(timestamp, client.latestDataAsOf)
        server.failingCollection = nil
        try await client.prepareContentRefresh()
        let refreshed = try await client.fetchSmartAccounts()
        XCTAssertEqual(refreshed.first?.name, "Never committed")
    }

    func testMalformedOrWrongRevisionCannotCommit() async throws {
        for malformed in [true, false] {
            let server = Server(), client: SupabaseContentClient
            client = server.client()
            server.malformedCollection = malformed ? "smart-accounts" : nil
            server.wrongRevision = !malformed
            do { try await client.prepareContentRefresh(); XCTFail("Must reject invalid content") } catch {}
            XCTAssertNil(client.latestDataAsOf)
            do { _ = try await client.fetchSmartAccounts(); XCTFail("No partial snapshot") } catch {}
        }
    }

    func testEvidenceUsesPinnedRevisionAndDoesNotRefreshTimestamps() async throws {
        let server = Server(), client: SupabaseContentClient
        client = server.client()
        try await client.prepareContentRefresh()
        let timestamp = client.latestDataAsOf
        let evidence = try await client.fetchSmartAccountEvidence(accountID: "x:a")
        XCTAssertTrue(evidence.isEmpty)
        XCTAssertEqual(timestamp, client.latestDataAsOf)
        server.wrongRevision = true
        do { _ = try await client.fetchSmartAccountEvidence(accountID: "x:a"); XCTFail("Must reject wrong revision") } catch {}
    }

    func testConcurrentRefreshesShareOneManifestRequest() async throws {
        let server = Server(), client: SupabaseContentClient
        client = server.client()
        server.pageHook = { await Task.yield() }
        async let first: Void = client.prepareContentRefresh()
        async let second: Void = client.prepareContentRefresh()
        _ = try await (first, second)
        XCTAssertEqual(server.requests.filter { $0 == "manifest" }.count, 1)
    }

    func testSupabaseModeDoesNotCreateLegacyInstallationSync() {
        let composition = BSmartClientFactory.make(arguments: ["--use-live-api"],
            environment: ["BSMART_CONTENT_BACKEND": "supabase"])
        XCTAssertTrue(composition.client is SupabaseContentClient)
        XCTAssertNil(composition.syncCoordinator)
        XCTAssertEqual(composition.portfolioBootstrapStrategy, .localOnly)
    }

    func testSupabaseBuildStaysLiveWithoutXcodeLaunchFlagsAndFixturesStillOverride() {
        let live = BSmartClientFactory.make(arguments: [], environment: ["BSMART_CONTENT_BACKEND": "supabase"])
        XCTAssertTrue(live.client is SupabaseContentClient)
        XCTAssertFalse(live.isUsingDemoData)
        let fixture = BSmartClientFactory.make(arguments: ["--use-fixture-data"], environment: ["BSMART_CONTENT_BACKEND": "supabase"])
        XCTAssertTrue(fixture.client is BundleBSmartAPIClient)
        XCTAssertTrue(fixture.isUsingDemoData)
    }

    func testManifestUnavailableDoesNotMasqueradeAsEmptyData() async throws {
        let server = Server(), client: SupabaseContentClient
        client = server.client(); server.manifestFailure = true
        do { try await client.prepareContentRefresh(); XCTFail("Unavailable must throw") } catch {}
        XCTAssertNil(client.latestDataAsOf)
    }

    func testCollectionLargerThanOnePageIsFullyLoaded() async throws {
        let server = Server()
        server.accountCount = 205
        let client = server.client()
        try await client.prepareContentRefresh()
        let accounts = try await client.fetchSmartAccounts()
        XCTAssertEqual(accounts.count, 205)
        XCTAssertEqual(server.requests.filter { $0 == "smart-accounts" }.count, 3)
        XCTAssertEqual(accounts.last?.id, "x:a204")
    }

    func testAppModelRefreshPreservesLocalHoldingsFollowsAndOfflineCache() async throws {
        let suite = "SupabaseContent.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = Server()
        let model = AppModel(client: server.client(), defaults: defaults, portfolioBootstrapStrategy: .localOnly)
        await model.load()
        XCTAssertNil(model.errorMessage)
        model.addPosition(ticker: "NVDA", companyName: "NVIDIA", shares: 4, averageCost: 123)
        model.toggleSmartAccountFollow("x:a")
        server.version = "b"; server.accountName = "Updated"
        await model.refreshLiveIntelligence()
        XCTAssertEqual(model.smartAccounts.first?.name, "Updated")
        XCTAssertEqual(model.positions.first?.averageCost, 123)
        XCTAssertTrue(model.isFollowingSmartAccount("x:a"))
        server.manifestFailure = true
        let reopened = AppModel(client: server.client(), defaults: defaults, portfolioBootstrapStrategy: .localOnly)
        await reopened.load()
        XCTAssertEqual(reopened.smartAccounts.first?.name, "Updated")
        XCTAssertEqual(reopened.positions.first?.shares, 4)
        XCTAssertTrue(reopened.isFollowingSmartAccount("x:a"))
        XCTAssertEqual(reopened.lastDataRefreshAt, model.lastDataRefreshAt)
    }
}
