import Foundation
import CryptoKit

enum AccountIdentityProvider: String, Codable, CaseIterable {
    case apple, google
}

struct AccountAuthConfiguration: Codable, Equatable {
    let providers: [AccountIdentityProvider]
    let depositsEnabled: Bool
    let tradingEnabled: Bool
    var withdrawalsEnabled: Bool? = nil

    static let unavailable = Self(providers: [], depositsEnabled: false, tradingEnabled: false)
}

struct AccountAuthChallenge: Codable {
    let id: UUID
    let nonce: String
    let expiresAt: Date
    let providerNonce: String?

    init(id: UUID, nonce: String, expiresAt: Date, providerNonce: String? = nil) {
        self.id = id; self.nonce = nonce; self.expiresAt = expiresAt; self.providerNonce = providerNonce
    }

    func identityNonce() throws -> String {
        guard let providerNonce else { return nonce }
        let expected = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        guard providerNonce == expected else { throw AccountAccessError.invalidResponse }
        return providerNonce
    }
}

struct AccountIdentityAssertion: CustomStringConvertible, CustomDebugStringConvertible {
    let idToken: String
    let authorizationCode: String?
    let appleUserID: String?
    let googleUserID: String?
    let nonce: String?

    init(idToken: String, authorizationCode: String?, appleUserID: String? = nil, googleUserID: String? = nil,
         nonce: String? = nil) {
        self.idToken = idToken; self.authorizationCode = authorizationCode; self.appleUserID = appleUserID
        self.googleUserID = googleUserID
        self.nonce = nonce
    }

    var description: String { "AccountIdentityAssertion(redacted)" }
    var debugDescription: String { description }

    func validate(for provider: AccountIdentityProvider) throws {
        func valid(_ text: String, maximum: Int) -> Bool {
            (32...maximum).contains(text.utf8.count) && text.utf8.allSatisfy { (33...126).contains($0) }
        }
        guard valid(idToken, maximum: 16_384) else { throw AccountAccessError.invalidResponse }
        if let nonce {
            guard (32...128).contains(nonce.utf8.count), nonce.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            }) else { throw AccountAccessError.invalidResponse }
        }
        switch provider {
        case .apple:
            guard googleUserID == nil else { throw AccountAccessError.invalidResponse }
            guard let authorizationCode, valid(authorizationCode, maximum: 2_048) else { throw AccountAccessError.invalidResponse }
            if let appleUserID {
                guard (1...255).contains(appleUserID.utf8.count), appleUserID.utf8.allSatisfy({ (33...126).contains($0) }) else {
                    throw AccountAccessError.invalidResponse
                }
            }
        case .google:
            guard authorizationCode == nil, appleUserID == nil else { throw AccountAccessError.invalidResponse }
            if let googleUserID {
                guard (1...255).contains(googleUserID.utf8.count), googleUserID.utf8.allSatisfy({ (33...126).contains($0) }) else {
                    throw AccountAccessError.invalidResponse
                }
            }
        }
    }
}

struct TradingAccountIdentity: Codable, Equatable {
    let id: UUID
    let provider: AccountIdentityProvider
}

enum AccountSessionAuthority: String, Codable {
    case supabase
}

struct TradingAccountSession: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let account: TradingAccountIdentity
    let accessToken: String
    let expiresAt: Date
    let refreshToken: String?
    let refreshExpiresAt: Date?
    let authority: AccountSessionAuthority?

    init(account: TradingAccountIdentity, accessToken: String, expiresAt: Date,
         refreshToken: String? = nil, refreshExpiresAt: Date? = nil, authority: AccountSessionAuthority? = nil) {
        self.account = account; self.accessToken = accessToken; self.expiresAt = expiresAt
        self.refreshToken = refreshToken; self.refreshExpiresAt = refreshExpiresAt
        self.authority = authority
    }

    var description: String { "TradingAccountSession(redacted)" }
    var debugDescription: String { description }

    func hasSameCredentials(as other: Self) -> Bool {
        account == other.account && authority == other.authority && accessToken == other.accessToken && refreshToken == other.refreshToken
    }

    func validateReceipt(now: Date = Date()) throws {
        if authority == .supabase {
            guard Self.validSupabaseAccessToken(accessToken), expiresAt > now,
                  expiresAt <= now.addingTimeInterval(86460), let refreshToken,
                  Self.validSupabaseRefreshToken(refreshToken), let refreshExpiresAt,
                  refreshExpiresAt >= expiresAt, refreshExpiresAt <= now.addingTimeInterval(30 * 86400 + 60) else {
                throw AccountAccessError.invalidResponse
            }
            return
        }
        guard Self.validToken(accessToken), expiresAt > now, expiresAt <= now.addingTimeInterval(1860) else {
            throw AccountAccessError.invalidResponse
        }
        if refreshToken == nil, refreshExpiresAt == nil { return }
        guard let refreshToken, Self.validToken(refreshToken), let refreshExpiresAt,
              refreshExpiresAt >= expiresAt, refreshExpiresAt <= now.addingTimeInterval(86460) else {
            throw AccountAccessError.invalidResponse
        }
    }

    func validateRenewal(of previous: Self, now: Date = Date()) throws {
        try validateReceipt(now: now)
        guard authority == previous.authority else { throw AccountAccessError.invalidResponse }
        if authority == .supabase {
            guard account == previous.account, accessToken != previous.accessToken,
                  refreshToken != previous.refreshToken else { throw AccountAccessError.invalidResponse }
            return
        }
        guard account == previous.account, accessToken != previous.accessToken,
              Self.validToken(accessToken), let refreshToken, Self.validToken(refreshToken),
              refreshToken != previous.refreshToken, let refreshExpiresAt,
              expiresAt > now, expiresAt <= now.addingTimeInterval(1860),
              refreshExpiresAt >= expiresAt, refreshExpiresAt <= now.addingTimeInterval(86460) else {
            throw AccountAccessError.invalidResponse
        }
    }

    static func validToken(_ token: String) -> Bool {
        (32...256).contains(token.utf8.count) && token.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }

    var hasValidAccessToken: Bool {
        authority == .supabase ? Self.validSupabaseAccessToken(accessToken) : Self.validToken(accessToken)
    }

    var hasValidRefreshToken: Bool {
        guard let refreshToken else { return false }
        return authority == .supabase ? Self.validSupabaseRefreshToken(refreshToken) : Self.validToken(refreshToken)
    }

    // Shape checks only. The fixed Supabase origin validates identity; never trust decoded JWT claims here.
    static func validSupabaseAccessToken(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        return (32...16384).contains(token.utf8.count) && parts.count == 3 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
            }
        }
    }

    static func validSupabaseRefreshToken(_ token: String) -> Bool {
        (8...2048).contains(token.utf8.count) && token.utf8.allSatisfy { (33...126).contains($0) }
    }
}

enum AccountAccessError: Error, LocalizedError {
    case unavailable, invalidResponse, expired, storage, cancelled, credentialUnavailable, walletSetupRequired

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Account sign-in is not available yet.".bSmartLocalized
        case .invalidResponse: return "Sign-in could not be verified. Please try again.".bSmartLocalized
        case .expired: return "Your session expired. Sign in again.".bSmartLocalized
        case .storage: return "Your account could not be saved securely on this device.".bSmartLocalized
        case .cancelled: return nil
        case .credentialUnavailable: return "Apple sign-in could not be checked. Try again before using your wallet.".bSmartLocalized
        case .walletSetupRequired: return "Sign-in is ready. Wallet setup in Supabase is not complete yet.".bSmartLocalized
        }
    }
}
