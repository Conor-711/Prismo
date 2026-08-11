import Foundation
import Security

struct InstallationRegistration: Codable, Equatable {
    let installationId: UUID
    let platform: String
    let appVersion: String
    let locale: String
    let timeZone: String
}

struct InstallationSession: Codable, Equatable {
    let installationId: UUID
    let accessToken: String
    let expiresAt: Date

    func isUsable(at date: Date, minimumLifetime: TimeInterval = 300) -> Bool {
        !accessToken.isEmpty && expiresAt.timeIntervalSince(date) > minimumLifetime
    }
}

protocol InstallationSessionPersisting: Sendable {
    func load() throws -> InstallationSession?
    func save(_ session: InstallationSession) throws
    func clear() throws
}

protocol BSmartAuthorizationProviding: Sendable {
    func accessToken() async throws -> String
    func invalidate() async
}

enum InstallationIdentity {
    private static let key = "bsmart.installation-id.v1"

    static func resolve(defaults: UserDefaults = .standard) -> UUID {
        if let value = defaults.string(forKey: key), let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: key)
        return identifier
    }
}

final class KeychainInstallationSessionStore: InstallationSessionPersisting, @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func load() throws -> InstallationSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw BSmartAPIError.secureStorage(Int32(status))
        }
        return try Self.makeDecoder().decode(InstallationSession.self, from: data)
    }

    func save(_ session: InstallationSession) throws {
        let data = try BSmartJSONCoding.makeEncoder().encode(session)
        let query = baseQuery
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw BSmartAPIError.secureStorage(Int32(updateStatus))
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw BSmartAPIError.secureStorage(Int32(insertStatus))
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BSmartAPIError.secureStorage(Int32(status))
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func makeDecoder() -> JSONDecoder {
        BSmartJSONCoding.makeDecoder()
    }
}

actor AnonymousInstallationSessionProvider: BSmartAuthorizationProviding {
    private let baseURL: URL
    private let urlSession: URLSession
    private let store: InstallationSessionPersisting
    private let registration: InstallationRegistration
    private let now: @Sendable () -> Date
    private var cachedSession: InstallationSession?
    private var registrationTask: Task<InstallationSession, Error>?

    init(
        baseURL: URL,
        urlSession: URLSession = .shared,
        store: InstallationSessionPersisting,
        registration: InstallationRegistration,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.store = store
        self.registration = registration
        self.now = now
    }

    func accessToken() async throws -> String {
        if let cachedSession, cachedSession.isUsable(at: now()) {
            return cachedSession.accessToken
        }
        if let persisted = try store.load(), persisted.isUsable(at: now()) {
            cachedSession = persisted
            return persisted.accessToken
        }

        if let registrationTask {
            return try await finishRegistration(registrationTask).accessToken
        }

        let task = Task {
            try await Self.registerInstallation(
                baseURL: baseURL,
                urlSession: urlSession,
                registration: registration
            )
        }
        registrationTask = task
        return try await finishRegistration(task).accessToken
    }

    func invalidate() async {
        cachedSession = nil
        registrationTask?.cancel()
        registrationTask = nil
        try? store.clear()
    }

    private func finishRegistration(_ task: Task<InstallationSession, Error>) async throws -> InstallationSession {
        do {
            let session = try await task.value
            if cachedSession != session {
                try store.save(session)
                cachedSession = session
            }
            registrationTask = nil
            return session
        } catch {
            registrationTask = nil
            throw error
        }
    }

    private static func registerInstallation(
        baseURL: URL,
        urlSession: URLSession,
        registration: InstallationRegistration
    ) async throws -> InstallationSession {
        var request = URLRequest(url: baseURL.appending(path: "v1/installations"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(registration)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BSmartAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BSmartAPIError.httpStatus(httpResponse.statusCode)
        }

        let session = try BSmartJSONCoding.makeDecoder().decode(InstallationSession.self, from: data)
        guard session.installationId == registration.installationId else {
            throw BSmartAPIError.invalidResponse
        }
        return session
    }
}
