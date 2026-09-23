import AuthenticationServices
import GoogleSignIn
import UIKit

@MainActor
final class AccountIdentityAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let isAppleSignInEnabled = Bundle.main.object(forInfoDictionaryKey: "BSMART_APPLE_SIGN_IN_ENABLED") as? String == "YES"
    private var continuation: CheckedContinuation<AccountIdentityAssertion, Error>?
    private var expectedState: String?
    private var rawNonce: String?
    private var controller: ASAuthorizationController?
    private weak var window: UIWindow?

    func authorize(_ provider: AccountIdentityProvider, challenge: AccountAuthChallenge) async throws -> AccountIdentityAssertion {
        try Task.checkCancellation()
        let providerNonce = try challenge.identityNonce()
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive }).flatMap(\.windows).first(where: \.isKeyWindow),
              let root = window.rootViewController else { throw AccountAccessError.unavailable }
        self.window = window
        switch provider {
        case .google:
            let lease = try GoogleIdentityOperationGate.shared.begin()
            defer { GoogleIdentityOperationGate.shared.finish(lease) }
            guard let clientID = configured("BSMART_GOOGLE_IOS_CLIENT_ID"),
                  let serverID = configured("BSMART_GOOGLE_SERVER_CLIENT_ID") else { throw AccountAccessError.unavailable }
            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverID)
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: providerNonce
                )
                try Task.checkCancellation()
                guard let token = result.user.idToken?.tokenString else { throw AccountAccessError.invalidResponse }
                return AccountIdentityAssertion(idToken: token, authorizationCode: nil, googleUserID: result.user.userID,
                                                nonce: challenge.providerNonce == nil ? nil : challenge.nonce)
            } catch {
                if (error as NSError).code == GIDSignInError.canceled.rawValue { throw AccountAccessError.cancelled }
                throw error
            }
        case .apple:
            guard Self.isAppleSignInEnabled,
                  continuation == nil else { throw AccountAccessError.unavailable }
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.nonce = providerNonce
            request.requestedScopes = [.email]
            request.state = challenge.id.uuidString
            let controller = ASAuthorizationController(authorizationRequests: [request])
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                    self.expectedState = request.state
                    self.rawNonce = challenge.providerNonce == nil ? nil : challenge.nonce
                    self.controller = controller
                    controller.delegate = self
                    controller.presentationContextProvider = self
                    controller.performRequests()
                }
            } onCancel: {
                Task { @MainActor [weak self, weak controller] in
                    guard let self, let controller, controller === self.controller else { return }
                    self.finish(.failure(AccountAccessError.cancelled))
                    controller.cancel()
                }
            }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              credential.state == expectedState, let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8), let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8) else {
            finish(.failure(AccountAccessError.invalidResponse)); return
        }
        let assertion = AccountIdentityAssertion(idToken: token, authorizationCode: code,
                                                appleUserID: credential.user, nonce: rawNonce)
        do { try assertion.validate(for: .apple); finish(.success(assertion)) }
        catch { finish(.failure(AccountAccessError.invalidResponse)) }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard controller === self.controller else { return }
        finish(.failure((error as? ASAuthorizationError)?.code == .canceled ? AccountAccessError.cancelled : error))
    }

    private func finish(_ result: Result<AccountIdentityAssertion, Error>) {
        let pending = continuation
        continuation = nil
        controller = nil
        expectedState = nil
        rawNonce = nil
        pending?.resume(with: result)
    }

    private func configured(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
