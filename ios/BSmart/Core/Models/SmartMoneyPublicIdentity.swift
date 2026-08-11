import CryptoKit
import Foundation

struct SmartMoneyPublicIdentity: Hashable {
    let displayName: String
    let avatarVariant: Int

    static func resolve(
        identityKey: String,
        displayName: String?,
        avatarVariant: Int?
    ) -> SmartMoneyPublicIdentity {
        let digest = Array(SHA256.hash(data: Data(identityKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)))
        let firstName = firstNames[Int(digest[0]) % firstNames.count]
        let lastInitial = Character(UnicodeScalar(65 + Int(digest[1]) % 26)!)
        let fallbackName = "\(firstName) \(lastInitial)."
        let fallbackVariant = Int(digest[2]) % 6 + 1
        let resolvedVariant = avatarVariant ?? fallbackVariant
        return SmartMoneyPublicIdentity(
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackName,
            avatarVariant: (1...6).contains(resolvedVariant) ? resolvedVariant : fallbackVariant
        )
    }

    private static let firstNames = [
        "Alex", "Avery", "Blake", "Casey", "Charlie", "Drew", "Elliot", "Emery",
        "Finley", "Harper", "Jamie", "Jordan", "Kai", "Logan", "Morgan", "Noah",
        "Parker", "Quinn", "Reese", "Riley", "Robin", "Rowan", "Sam", "Sawyer",
        "Skyler", "Taylor",
    ]
}

extension SmartMoneySignal {
    var publicIdentity: SmartMoneyPublicIdentity {
        SmartMoneyPublicIdentity.resolve(
            identityKey: resolvedAddress,
            displayName: displayName,
            avatarVariant: avatarVariant
        )
    }
}

extension SmartMoneyMovement {
    var publicIdentity: SmartMoneyPublicIdentity {
        SmartMoneyPublicIdentity.resolve(
            identityKey: accountId,
            displayName: accountDisplayName,
            avatarVariant: avatarVariant
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
