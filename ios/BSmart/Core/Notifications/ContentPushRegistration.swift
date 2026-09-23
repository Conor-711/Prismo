import Foundation

struct ContentPushDevice: Encodable, Equatable {
    let installationId: UUID
    let apnsToken: String
    let environment: String
    let locale: String
    let enabled: Bool

    static func environment(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "BSMART_APNS_ENVIRONMENT") as? String == "development"
            ? "development" : "production"
    }
}

struct ContentPushInterests: Encodable, Equatable {
    let installationId: UUID
    let authors: [String]
    let money: [String]
    let tickers: [String]
    let holdings: [String]
    let notifyAuthors: Bool
    let notifyTickers: Bool
    let notifyHoldings: Bool
}

@MainActor
final class ContentPushRegistration {
    private weak var account: AccountAccessStore?
    private let transport: SupabaseAccountTransport?
    private let installationID: UUID
    private var queue: Task<Void, Never>?
    private var lastRegistered: (UUID, ContentPushDevice, ContentPushInterests, Date)?
    var onResult: ((Bool) -> Void)?
    var installationId: UUID { installationID }

    init(configuration: SupabaseAccountConfiguration? = .resolve(), defaults: UserDefaults = .standard,
         sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        transport = configuration.map { SupabaseAccountTransport(configuration: $0, sessionConfiguration: sessionConfiguration) }
        let key = "bsmart.push.installation." + (configuration?.sessionNamespace ?? "unconfigured")
        installationID = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(installationID.uuidString, forKey: key)
    }

    func bind(account: AccountAccessStore) {
        self.account = account
        account.onSessionEnding = { [weak self] token in await self?.unregister(token: token) }
    }

    func synchronize(token: String?, enabled: Bool, locale: String, interests: ContentPushInterests) {
        guard let account, !account.isTestSession, let id = account.identity?.id, let transport else { return }
        guard token != nil || !enabled else { return }
        let device = ContentPushDevice(installationId: installationID, apnsToken: token ?? "",
            environment: ContentPushDevice.environment(), locale: locale, enabled: enabled)
        let previous = queue
        queue = Task { [weak self, weak account] in
            await previous?.value
            guard let self, let account, account.identity?.id == id, !account.isTestSession else { return }
            if let prior = self.lastRegistered, prior.0 == id, prior.1 == device,
               prior.2 == interests, Date().timeIntervalSince(prior.3) < 3600 { return }
            do {
                let body = try JSONEncoder().encode(device)
                let response = try await account.withFeedSession(expectedAccountID: id) { token in
                    try await transport.request("functions/v1/bsmart-notifications/device", method: device.enabled ? "PUT" : "DELETE", body: body, token: token)
                }
                struct Receipt: Decodable { let registered: Bool }
                guard try JSONDecoder().decode(Receipt.self, from: response).registered == device.enabled else {
                    throw AccountAccessError.invalidResponse
                }
                if device.enabled {
                    let interestsBody = try JSONEncoder().encode(interests)
                    let interestsResponse = try await account.withFeedSession(expectedAccountID: id) { token in
                        try await transport.request("functions/v1/bsmart-notifications/interests", method: "PUT",
                                                    body: interestsBody, token: token)
                    }
                    guard try JSONDecoder().decode(Receipt.self, from: interestsResponse).registered else {
                        throw AccountAccessError.invalidResponse
                    }
                }
                self.lastRegistered = (id, device, interests, Date())
                self.onResult?(true)
            } catch {
                self.lastRegistered = nil
                self.onResult?(false)
            }
        }
    }

    private func unregister(token: String) async {
        await queue?.value
        lastRegistered = nil
        guard let transport else { return }
        struct Removal: Encodable { let installationId: UUID }
        guard let body = try? JSONEncoder().encode(Removal(installationId: installationID)) else { return }
        _ = try? await transport.request("functions/v1/bsmart-notifications/device", method: "DELETE", body: body, token: token)
    }

    func finishPendingRegistration() async { await queue?.value }
}

extension Notification.Name {
    static let bSmartContentPushOpened = Notification.Name("bsmart.content-push-opened")
}
