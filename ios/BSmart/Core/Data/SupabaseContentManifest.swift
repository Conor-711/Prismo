import Foundation

protocol BSmartContentRefreshing {
    func prepareContentRefresh() async throws
}

struct SupabaseContentManifest: Decodable, Equatable {
    struct Collection: Decodable, Equatable {
        let count: Int
        let sha256: String
        let checkedAt: Date
        let latestContentAt: Date?
    }
    let schemaVersion: Int
    let revision: String
    let collections: [String: Collection]

    static let names: Set<String> = ["smart-accounts", "smart-account-updates", "smart-account-evidence",
        "portfolio-signals", "ticker-intelligence", "smart-money", "smart-money-movements", "smart-money-evidence"]

    func validate() throws {
        let hash = #"^[a-f0-9]{64}$"#
        guard schemaVersion == 1, revision.range(of: hash, options: .regularExpression) != nil,
              Set(collections.keys) == Self.names,
              collections.values.allSatisfy({ $0.count >= 0 && $0.count <= 1_000_000
                  && $0.sha256.range(of: hash, options: .regularExpression) != nil
                  && $0.checkedAt <= Date().addingTimeInterval(300)
                  && ($0.latestContentAt ?? .distantPast) <= Date().addingTimeInterval(300) })
        else { throw BSmartAPIError.invalidResponse }
    }
}

struct SupabaseContentPage<Item: Decodable>: Decodable {
    let revision: String
    let page: Int
    let pages: Int
    let total: Int
    let items: [Item]
}

final class SupabaseContentFreshness: @unchecked Sendable {
    private let lock = NSLock()
    private var manifest: SupabaseContentManifest?

    func commit(_ value: SupabaseContentManifest) { lock.withLock { manifest = value } }
    var latest: Date? { lock.withLock { manifest?.collections.values.map(\.checkedAt).max() } }
    func value(for source: BSmartLiveDataSource) -> BSmartDataFreshness? {
        lock.withLock {
            let name = source == .smartAccount ? "smart-account-updates" : "smart-money"
            guard let entry = manifest?.collections[name] else { return nil }
            return BSmartDataFreshness(checkedAt: entry.checkedAt, latestContentAt: entry.latestContentAt, itemCount: entry.count)
        }
    }
}
