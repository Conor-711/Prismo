import Foundation

struct AccountPreferences: Decodable, Equatable {
    let onboardingCompleted: Bool
    let followedAuthors: [String]
    let followedMoney: [String]
    let revision: Int

    func validate() throws -> Self {
        let all = followedAuthors + followedMoney
        guard followedAuthors.count <= 1000, followedMoney.count <= 1000,
              all.allSatisfy({ !$0.isEmpty && $0.count <= 256 && $0.trimmingCharacters(in: .whitespacesAndNewlines) == $0 }),
              Set(followedAuthors).count == followedAuthors.count,
              Set(followedMoney).count == followedMoney.count, revision >= 0 else {
            throw BSmartAPIError.invalidResponse
        }
        return self
    }
}

enum AccountFollowKind: String, Codable { case author, money }

@MainActor
protocol AccountPreferencesProviding {
    func load(accountID: UUID) async throws -> AccountPreferences
    func setFollowing(_ following: Bool, kind: AccountFollowKind, id: String,
                      accountID: UUID) async throws -> AccountPreferences
    func completeOnboarding(accountID: UUID) async throws -> AccountPreferences
}

@MainActor
struct NativeAccountPreferencesClient: AccountPreferencesProviding {
    let client: NativeTradeFeedClient

    func load(accountID: UUID) async throws -> AccountPreferences {
        let value: AccountPreferences = try await client.request("/state", expectedAccountID: accountID)
        return try value.validate()
    }

    func setFollowing(_ following: Bool, kind: AccountFollowKind, id: String,
                      accountID: UUID) async throws -> AccountPreferences {
        struct Input: Encodable { let kind: AccountFollowKind; let id: String; let following: Bool }
        let body = try JSONEncoder().encode(Input(kind: kind, id: id, following: following))
        let value: AccountPreferences = try await client.request("/state/follow", method: "PUT", body: body,
                                                                  expectedAccountID: accountID)
        return try value.validate()
    }

    func completeOnboarding(accountID: UUID) async throws -> AccountPreferences {
        let value: AccountPreferences = try await client.request("/state/onboarding", method: "PUT",
                                                                  expectedAccountID: accountID)
        guard value.onboardingCompleted else { throw BSmartAPIError.invalidResponse }
        return try value.validate()
    }
}

enum OpinionLinkError: String, Error {
    case sourceUnavailable = "opinion_unavailable"
    case marketUnavailable = "market_unavailable"
    case invalidIntent = "invalid_input"
    case conflict = "attribution_conflict"
    case existingOrder = "existing_order"
    case rateLimit = "rate_limit"
    case walletRequired = "wallet_required"
    case unavailable = "feed_unavailable"

    var message: String {
        switch self {
        case .sourceUnavailable:
            return "This opinion is not yet available for trade linking. No order was submitted.".bSmartLocalized
        case .marketUnavailable:
            return "This market is not currently available for opinion trading. No order was submitted.".bSmartLocalized
        case .invalidIntent:
            return "The order details have expired or changed. Please confirm again. No order was submitted.".bSmartLocalized
        case .conflict, .existingOrder:
            return "This order already has a record. Check order history before placing another order.".bSmartLocalized
        case .rateLimit:
            return "Too many order requests. Please wait a moment. No order was submitted.".bSmartLocalized
        case .walletRequired:
            return "Your trading wallet needs to reconnect. No order was submitted.".bSmartLocalized
        case .unavailable:
            return "Opinion verification is temporarily unavailable. No order was submitted.".bSmartLocalized
        }
    }
}

@MainActor
struct NativeTradeFeedClient {
    let account: AccountAccessStore
    var transport: SupabaseAccountTransport?

    init(account: AccountAccessStore, transport: SupabaseAccountTransport? = nil) {
        self.account = account
        self.transport = transport ?? SupabaseAccountConfiguration.resolve().map { SupabaseAccountTransport(configuration: $0) }
    }

    func request<T: Decodable>(_ path: String = "", method: String = "GET", query: [URLQueryItem] = [],
                               body: Data? = nil, expectedAccountID: UUID? = nil) async throws -> T {
        guard let transport else { throw AccountAccessError.unavailable }
        return try await account.withFeedSession(expectedAccountID: expectedAccountID) { token in
            let data = try await transport.request("functions/v1/bsmart-feed" + path, method: method,
                                                    query: query, body: body, token: token)
            return try BSmartJSONCoding.makeDecoder().decode(T.self, from: data)
        }
    }

    func page(offset: Int, profileID: UUID? = nil, mine: Bool = false) async throws -> TradeFeedPage {
        var query = [URLQueryItem(name: "offset", value: String(offset)), .init(name: "limit", value: "10"),
                     .init(name: "includeTheses", value: "true")]
        if mine { query.append(.init(name: "mine", value: "true")) }
        if let profileID { query.append(.init(name: "profileId", value: profileID.uuidString)) }
        let page: TradeFeedPage = try await request(query: query)
        try page.validate(offset: offset)
        return page
    }

    func popular(offset: Int) async throws -> PopularOpinionsPage {
        let page: PopularOpinionsPage = try await request("/popular", query: [
            .init(name: "offset", value: String(offset)), .init(name: "limit", value: "10")])
        try page.validate(offset: offset)
        return page
    }

    func rankings(query: DiscoveryRankingQuery, offset: Int, limit: Int, asOf: Date?) async throws -> DiscoveryRankingsPage {
        var parameters = [URLQueryItem(name: "kind", value: query.kind.rawValue),
            .init(name: "sort", value: query.sort.rawValue), .init(name: "window", value: query.window.rawValue),
            .init(name: "offset", value: String(offset)), .init(name: "limit", value: String(limit))]
        if let asOf {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parameters.append(.init(name: "asOf", value: formatter.string(from: asOf)))
        }
        let page: DiscoveryRankingsPage = try await request("/rankings", query: parameters)
        try page.validate(query: query, offset: offset, limit: limit, anchor: asOf)
        return page
    }

    func subjectStats(_ subject: TradeSubject) async throws -> SubjectTradeStats {
        let result: SubjectTradeStats = try await request("/subject-stats", query: [
            .init(name: "kind", value: subject.kind.rawValue), .init(name: "id", value: subject.id),
            .init(name: "platform", value: subject.platform)])
        try result.validate(subject: subject)
        return result
    }

    func profile(_ id: UUID) async throws -> FeedPublicProfile {
        let result: FeedPublicProfile = try await request("/profiles/" + id.uuidString)
        guard result.id == id, result.isValid else { throw BSmartAPIError.invalidResponse }
        return result
    }

    func portfolio(_ id: UUID) async throws -> FeedPublicPortfolio {
        let result: FeedPublicPortfolio = try await request("/profiles/" + id.uuidString + "/portfolio")
        try result.validate()
        return result
    }

    func traders(opinionID: UUID, offset: Int) async throws -> OpinionTradersPage {
        let result: OpinionTradersPage = try await request("/opinions/\(opinionID.uuidString)/traders",
            query: [.init(name: "offset", value: String(offset)), .init(name: "limit", value: "30")])
        try result.validate(offset: offset)
        return result
    }

    @discardableResult
    func synchronize(accountID: UUID? = nil, cloid: String? = nil) async throws -> Bool {
        struct Result: Decodable { let checked, verified, failed: Int }
        let body = try JSONEncoder().encode(cloid.map { ["cloid": $0] } ?? [:])
        let result: Result = try await request("/sync", method: "POST", body: body, expectedAccountID: accountID)
        guard (0...1).contains(result.checked), (0...result.checked).contains(result.verified),
              result.failed == 0 else { throw AccountAccessError.unavailable }
        return result.verified == result.checked
    }
}

@MainActor
protocol OpinionOrderAttributing {
    func register(order: HyperliquidOrderIntent) async throws
    func synchronize(order: HyperliquidOrderIntent) async
}

@MainActor
struct NativeOpinionOrderAttribution: OpinionOrderAttributing {
    let source: OpinionTradeSource
    let accountID: UUID
    let client: NativeTradeFeedClient

    struct Registration: Encodable {
        let opinionId: UUID
        let authorId, ticker, cloid, coin, side, size, limitPrice: String
        let nonce, expiresAfter: UInt64
    }

    static func registration(source: OpinionTradeSource, order: HyperliquidOrderIntent) throws -> Registration {
        guard let author = source.authorID, !author.isEmpty, !order.reduceOnly else { throw BSmartAPIError.invalidResponse }
        return Registration(opinionId: source.opinionID, authorId: author, ticker: source.ticker,
            cloid: order.cloid, coin: order.market.coin, side: order.side.rawValue,
            size: order.size.wire, limitPrice: order.limitPrice.wire, nonce: order.nonce, expiresAfter: order.expiresAfter)
    }

    func register(order: HyperliquidOrderIntent) async throws {
        guard order.accountID == accountID else { throw DeviceWalletError.accountChanged }
        struct Receipt: Decodable { let id: UUID; let cloid: String }
        let body = try JSONEncoder().encode(Self.registration(source: source, order: order))
        let receipt: Receipt = try await client.request("/orders", method: "POST", body: body, expectedAccountID: accountID)
        guard receipt.cloid == order.cloid else { throw BSmartAPIError.invalidResponse }
    }

    func synchronize(order: HyperliquidOrderIntent) async {
        if (try? await client.synchronize(accountID: accountID, cloid: order.cloid)) == true {
            client.account.feedSharingDidChange(accountID: accountID)
        }
    }
}
