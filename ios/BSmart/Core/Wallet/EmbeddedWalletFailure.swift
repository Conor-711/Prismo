import Foundation
import PrivySDK
import OSLog

enum EmbeddedWalletFailure {
    enum Stage: String { case configuration, authentication, restoring, creating, signing }

    static func map(_ error: Error, stage: Stage) -> EmbeddedWalletError {
        if let error = error as? EmbeddedWalletError { return error }
        if let error = error as? PrivyError { return map(error.errorCode, stage: stage) }
        if let api = error as? ApiError {
            switch api {
            case .apiError(let status, let code, _):
                // Never log provider descriptions, JWTs, addresses, or response bodies.
                let knownCodes: Set<String> = ["invalid_native_app_id", "invalid_app_client_id", "invalid_origin",
                                              "invalid_jwt", "invalid_access_token", "invalid_app_id", "rate_limit_exceeded"]
                let safeCode = knownCodes.contains(code) ? code : "unclassified"
                Logger(subsystem: "today.bsmart.ios", category: "EmbeddedWallet")
                    .error("Privy stage=\(stage.rawValue, privacy: .public) status=\(status) code=\(safeCode, privacy: .public)")
                if status == 401 { return .authenticationFailed }
                if status == 403 { return .accessDenied }
                if status == 429 { return .rateLimited(seconds: 60) }
                if status >= 500 { return .networkUnavailable }
            case .networkError(let status, _):
                return status == 429 ? .rateLimited(seconds: 60) : .networkUnavailable
            default: break
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return (error as NSError).code == NSURLErrorTimedOut ? .timedOut : .networkUnavailable
        }
        return stage == .creating ? .creationFailed : .unavailable
    }

    static func map(_ code: PrivyErrorCode, stage: Stage) -> EmbeddedWalletError {
        switch code {
        case .initializationFailed, .authenticationFailure(reason: .noCustomAuthProviderConfigured): return .notConfigured
        case .authenticationFailure(reason: .failureDuringAuthentication(let error)): return map(error, stage: .authentication)
        case .authenticationFailure: return .authenticationFailed
        case .embeddedWalletFailure(reason: .creationFailed): return .creationFailed
        case .embeddedWalletFailure(reason: .timeout): return .timedOut
        case .embeddedWalletFailure(reason: .noWalletAvailable): return .walletMismatch
        default: return stage == .creating ? .creationFailed : .unavailable
        }
    }
}
