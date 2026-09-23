import Foundation

struct AccountProfile: Codable, Equatable {
    let id: UUID
    var username: String
    var handle: String
    var bio: String
    let avatarURL: URL?
    let revision: Int

    // Signup creates revision zero; only a successful profile PUT advances it.
    var needsSetup: Bool { revision == 0 }

    static func validHandle(_ value: String) -> Bool {
        value.range(of: #"^[a-z][a-z0-9_]{2,23}$"#, options: .regularExpression) == value.startIndex..<value.endIndex
    }

    static func normalizedHandle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    }

    var isValid: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && username.unicodeScalars.count <= 28 && bio.unicodeScalars.count <= 120
            && username.rangeOfCharacter(from: .controlCharacters) == nil
            && Self.validHandle(handle) && revision >= 0 && revision < Int(Int32.max)
            && (avatarURL == nil || avatarURL?.scheme == "https")
    }
}

enum AccountProfileError: String, Error, LocalizedError {
    case handleTaken = "handle_taken"
    case conflict = "profile_conflict"
    case invalid = "invalid_profile"
    case providerAvatarUnavailable = "provider_avatar_unavailable"

    var errorDescription: String? {
        switch self {
        case .handleTaken: "This handle is already taken. Please choose another.".bSmartLocalized
        case .conflict: "Your profile changed on another device. Reload before saving.".bSmartLocalized
        case .invalid: "Check your username, handle, bio and photo.".bSmartLocalized
        case .providerAvatarUnavailable: "Your sign-in provider has no available photo.".bSmartLocalized
        }
    }
}

struct AccountProfileAvatarInput: Encodable {
    let action: String
    var jpegBase64: String? = nil

    static let keep = Self(action: "keep")
    static let remove = Self(action: "remove")
    static let provider = Self(action: "provider")
    static func upload(_ data: Data) -> Self { Self(action: "upload", jpegBase64: data.base64EncodedString()) }
}
