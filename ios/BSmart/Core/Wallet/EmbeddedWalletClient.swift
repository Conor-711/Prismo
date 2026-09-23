import Foundation

protocol TradingWalletSigning: FundingDeviceSigning, HyperliquidDeviceSigning,
    HyperliquidWithdrawalSigning, AcrossWithdrawalSigning, UnifiedAccountSetupSigning, HyperliquidLeverageSigning {}

extension KeychainDeviceWalletVault: TradingWalletSigning {}

@MainActor
protocol EmbeddedWalletClient: Sendable {
    var isConfigured: Bool { get }
    func resolve(accountID: UUID, address: String?, create: Bool) async throws -> DeviceWalletSummary?
    func personalSign(accountID: UUID, address: String, message: String) async throws -> String
    func signTypedData(accountID: UUID, address: String, json: String) async throws -> String
    func signDigest(accountID: UUID, address: String, digest: Data) async throws -> String
}

struct PrivyWalletConfiguration: Equatable, Sendable {
    let appID: String
    let clientID: String

    init?(appID: String?, clientID: String?) {
        guard let appID, let clientID, Self.valid(appID), Self.valid(clientID) else { return nil }
        self.appID = appID; self.clientID = clientID
    }

    static func resolve(bundle: Bundle = .main) -> Self? {
        .init(appID: bundle.object(forInfoDictionaryKey: "BSMART_PRIVY_APP_ID") as? String,
              clientID: bundle.object(forInfoDictionaryKey: "BSMART_PRIVY_CLIENT_ID") as? String)
    }

    private static func valid(_ value: String) -> Bool {
        (8...160).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        } && !value.lowercased().contains("your_")
    }
}

enum EmbeddedWalletError: Error, LocalizedError, Equatable {
    case notConfigured, unavailable, authenticationFailed, identityMismatch, walletMismatch, unsupportedRecovery
    case accessDenied, networkUnavailable, creationFailed, timedOut, busy
    case rateLimited(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Embedded wallet setup is not complete. Existing wallets have not changed.".bSmartLocalized
        case .unavailable:
            return "Wallet connection failed. Retry with the same account; your wallet has not changed.".bSmartLocalized
        case .authenticationFailed:
            return "Wallet sign-in could not be verified. Sign in again; if it persists, check the wallet authentication configuration.".bSmartLocalized
        case .identityMismatch:
            return "Wallet identity does not match this account. Sign in again.".bSmartLocalized
        case .walletMismatch:
            return "The linked wallet was not found in this account. No replacement wallet was created.".bSmartLocalized
        case .unsupportedRecovery:
            return "This wallet uses account recovery, not a device recovery phrase.".bSmartLocalized
        case .accessDenied:
            return "Privy denied wallet access. Check this iOS client's allowed app identifier and JWT configuration.".bSmartLocalized
        case .networkUnavailable:
            return "Cannot reach Privy. Check your network and retry; no replacement wallet was created.".bSmartLocalized
        case .creationFailed:
            return "Privy could not create the account wallet. Check wallet settings in Privy and retry with this account.".bSmartLocalized
        case .timedOut:
            return "Privy did not respond in time. Retry to check the existing wallet before continuing.".bSmartLocalized
        case .busy:
            return "Wallet connection is still finishing. Please retry shortly.".bSmartLocalized
        case .rateLimited(let seconds):
            return "Privy is rate limiting requests. Retry in %d seconds.".bSmartLocalized(seconds)
        }
    }
}
