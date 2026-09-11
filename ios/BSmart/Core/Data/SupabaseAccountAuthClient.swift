import Foundation
import CryptoKit
import Security

actor SupabaseAccountAuthClient: AccountAuthenticating {
    private let config: SupabaseAccountConfiguration
    private let transport: SupabaseAccountTransport
    private var challenges: [UUID: (provider: AccountIdentityProvider, value: AccountAuthChallenge)] = [:]

    init(configuration: SupabaseAccountConfiguration, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        config = configuration
        transport = SupabaseAccountTransport(configuration: configuration, sessionConfiguration: sessionConfiguration)
    }

    func configuration() async throws -> AccountAuthConfiguration {
        struct Settings: Decodable { let external: [String: Bool] }
        let data = try await transport.request("auth/v1/settings")
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        let providers = AccountIdentityProvider.allCases.filter {
            settings.external[$0.rawValue] == true && ($0 != .apple || config.appleEnabled)
        }
        // Login readiness is not funded-transfer acceptance.
        return .init(providers: providers, depositsEnabled: false, tradingEnabled: false)
    }

    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        challenges = challenges.filter { $0.value.value.expiresAt > Date() }
        guard challenges.count < 8, provider != .apple || config.appleEnabled else { throw AccountAccessError.unavailable }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccountAccessError.storage }
        let nonce = bytes.map { String(format: "%02x", $0) }.joined()
        let hash = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        let challenge = AccountAuthChallenge(id: UUID(), nonce: nonce, expiresAt: Date().addingTimeInterval(300), providerNonce: hash)
        challenges[challenge.id] = (provider, challenge)
        return challenge
    }

    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        try assertion.validate(for: provider)
        guard let pending = challenges.removeValue(forKey: challenge), pending.provider == provider,
              pending.value.expiresAt > Date(), pending.value.nonce == assertion.nonce else { throw AccountAccessError.invalidResponse }
        let subject = provider == .apple ? assertion.appleUserID : assertion.googleUserID
        guard let subject, !subject.isEmpty else { throw AccountAccessError.invalidResponse }
        let body = try JSONSerialization.data(withJSONObject: [
            "provider": provider.rawValue, "id_token": assertion.idToken, "nonce": pending.value.nonce
        ])
        let response = try await exchange(grant: "id_token", body: body)
        do {
            let user = try await verifiedUser(token: response.accessToken)
            guard user.id == response.user.id,
                  user.identities.contains(where: { $0.provider == provider.rawValue && $0.identityData.sub == subject }) else {
                throw AccountAccessError.invalidResponse
            }
            return try response.session(user: user, provider: provider)
        } catch {
            try? await signOut(token: response.accessToken)
            throw error
        }
    }

    func account(token: String) async throws -> TradingAccountIdentity {
        let user = try await verifiedUser(token: token)
        return try user.identity(provider: nil)
    }

    func account(token: String, provider: AccountIdentityProvider) async throws -> TradingAccountIdentity {
        try await verifiedUser(token: token).identity(provider: provider)
    }

    func refresh(token: String) async throws -> TradingAccountSession {
        try await renew(token: token, provider: nil)
    }

    func refresh(token: String, provider: AccountIdentityProvider) async throws -> TradingAccountSession {
        try await renew(token: token, provider: provider)
    }

    private func renew(token: String, provider: AccountIdentityProvider?) async throws -> TradingAccountSession {
        guard TradingAccountSession.validSupabaseRefreshToken(token) else { throw AccountAccessError.expired }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": token])
        let response = try await exchange(grant: "refresh_token", body: body)
        do {
            let user = try await verifiedUser(token: response.accessToken)
            guard user.id == response.user.id else { throw AccountAccessError.invalidResponse }
            return try response.session(user: user, provider: provider)
        } catch {
            try? await signOut(token: response.accessToken)
            throw error
        }
    }

    func signOut(token: String) async throws {
        _ = try await transport.request("auth/v1/logout", method: "POST", query: [.init(name: "scope", value: "local")],
                                        token: token, expectedStatus: 204)
    }

    func wallet(token: String) async throws -> TradingWalletRegistration {
        let data = try await transport.request("functions/v1/bsmart-wallet", token: token)
        return try BSmartJSONCoding.makeDecoder().decode(TradingWalletRegistration.self, from: data)
    }

    func walletChallenge(address: String, token: String) async throws -> TradingWalletChallenge {
        guard TradingWalletChallenge.validAddress(address) else { throw DeviceWalletError.invalidProof }
        let body = try JSONSerialization.data(withJSONObject: ["address": address])
        let data = try await transport.request("functions/v1/bsmart-wallet/challenges", method: "POST", body: body, token: token)
        return try BSmartJSONCoding.makeDecoder().decode(TradingWalletChallenge.self, from: data)
    }

    func bindWallet(challenge: UUID, signature: String, token: String) async throws -> TradingWalletRegistration {
        guard signature.range(of: #"^0x[0-9a-fA-F]{130}$"#, options: .regularExpression) != nil else {
            throw DeviceWalletError.invalidProof
        }
        let body = try JSONSerialization.data(withJSONObject: ["challengeId": challenge.uuidString.lowercased(), "signature": signature])
        let data = try await transport.request("functions/v1/bsmart-wallet", method: "PUT", body: body, token: token)
        return try BSmartJSONCoding.makeDecoder().decode(TradingWalletRegistration.self, from: data)
    }

    private func verifiedUser(token: String) async throws -> SupabaseUser {
        let data = try await transport.request("auth/v1/user", token: token)
        return try Self.decoder().decode(SupabaseUser.self, from: data)
    }

    private func exchange(grant: String, body: Data) async throws -> SupabaseTokenResponse {
        let data = try await transport.request("auth/v1/token", method: "POST",
                                               query: [.init(name: "grant_type", value: grant)], body: body)
        return try Self.decoder().decode(SupabaseTokenResponse.self, from: data)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private struct SupabaseUser: Decodable {
    struct Identity: Decodable {
        struct Data: Decodable { let sub: String }
        let provider: String
        let identityData: Data
    }
    let id: UUID
    let identities: [Identity]

    func identity(provider: AccountIdentityProvider?) throws -> TradingAccountIdentity {
        let supported = identities.compactMap { AccountIdentityProvider(rawValue: $0.provider) }
        guard let selected = provider ?? supported.first, supported.contains(selected) else { throw AccountAccessError.invalidResponse }
        return .init(id: id, provider: selected)
    }
}

private struct SupabaseTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Double
    let expiresAt: Double?
    let user: SupabaseUser

    func session(user: SupabaseUser, provider: AccountIdentityProvider?) throws -> TradingAccountSession {
        guard tokenType.lowercased() == "bearer", expiresIn > 0, expiresIn <= 86400 else { throw AccountAccessError.invalidResponse }
        let now = Date()
        let expiry = min(expiresAt.map(Date.init(timeIntervalSince1970:)) ?? now.addingTimeInterval(expiresIn),
                         now.addingTimeInterval(expiresIn))
        let result = TradingAccountSession(account: try user.identity(provider: provider), accessToken: accessToken,
            expiresAt: expiry, refreshToken: refreshToken, refreshExpiresAt: now.addingTimeInterval(30 * 86400), authority: .supabase)
        try result.validateReceipt(now: now)
        return result
    }
}
