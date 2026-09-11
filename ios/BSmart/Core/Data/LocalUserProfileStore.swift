import Foundation
import Combine

struct LocalUserProfile: Codable, Equatable {
    var nickname = ""
    var bio = ""
    var avatarData: Data?

    var displayName: String { nickname.isEmpty ? "bSmart Investor".bSmartLocalized : nickname }
}

/// Device-local presentation only; never stores wallet keys or changes account identity.
@MainActor
final class LocalUserProfileStore: ObservableObject {
    @Published private(set) var profile = LocalUserProfile()
    private(set) var scope = "guest"
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UserProfiles", isDirectory: true)
    }

    func load(accountID: UUID?) {
        scope = accountID?.uuidString.lowercased() ?? "guest"
        do { try requireWritableScope() }
        catch { profile = LocalUserProfile(); return }
        profile = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(LocalUserProfile.self, from: $0) }
            ?? LocalUserProfile()
    }

    func save(_ draft: LocalUserProfile, expectedScope: String) throws {
        guard expectedScope == scope else { throw ProfileError.accountChanged }
        try requireWritableScope()
        var value = draft
        value.nickname = String(value.nickname.trimmingCharacters(in: .whitespacesAndNewlines).prefix(28))
        value.bio = String(value.bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard (value.avatarData?.count ?? 0) <= 200_000 else { throw ProfileError.photoTooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        profile = value
    }

    private var fileURL: URL { directory.appendingPathComponent(scope).appendingPathExtension("json") }

    func erase(accountID: UUID) throws {
        let accountScope = accountID.uuidString.lowercased()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent(accountScope).appendingPathExtension("deleted")
        try Data().write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let path = directory.appendingPathComponent(accountScope).appendingPathExtension("json")
        do { try FileManager.default.removeItem(at: path) }
        catch {
            let failure = error as NSError
            guard failure.domain == NSCocoaErrorDomain, failure.code == NSFileNoSuchFileError else { throw error }
        }
        if scope == accountScope { profile = LocalUserProfile() }
    }

    private func requireWritableScope() throws {
        guard scope != "guest" else { return }
        let marker = directory.appendingPathComponent(scope).appendingPathExtension("deleted")
        do { _ = try Data(contentsOf: marker) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain, failure.code == NSFileReadNoSuchFileError { return }
            throw error
        }
        throw ProfileError.accountDeleted
    }

    enum ProfileError: Error { case accountChanged, accountDeleted, photoTooLarge }
}

struct ProfileAddress {
    // Display placeholder only. Never send this value to wallet, funding or trading services.
    static let example = "0x000000000000000000000000000000000000b5a7"
    let value: String
    let isExample: Bool

    init(accountID: UUID?, wallet: DeviceWalletState) {
        if case let .verified(summary) = wallet, summary.accountID == accountID,
           TradingWalletChallenge.validAddress(summary.address) {
            value = summary.address
            isExample = false
        } else {
            value = Self.example
            isExample = true
        }
    }

    var shortValue: String { String(value.prefix(8)) + "..." + String(value.suffix(6)) }
}
