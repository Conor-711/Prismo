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
        let fallbackVariant = Int(digest[2]) % 54 + 1
        let resolvedVariant = avatarVariant ?? fallbackVariant
        let resolvedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? firstName
        return SmartMoneyPublicIdentity(
            displayName: resolvedName,
            avatarVariant: (1...54).contains(resolvedVariant) ? resolvedVariant : fallbackVariant
        )
    }

    private static let firstNames = [
        "Aiden", "Amara", "Anya", "Aria", "Atlas", "Audrey", "Beau", "Billie",
        "Briar", "Caleb", "Cameron", "Celeste", "Chloe", "Cole", "Dakota", "Eden",
        "Ellis", "Esme", "Eva", "Felix", "Freya", "Gideon", "Hazel", "Hudson",
        "Indigo", "Iris", "Jade", "Jasper", "Juno", "Kieran", "Leila", "Leo",
        "Luna", "Maeve", "Mateo", "Maya", "Micah", "Milo", "Naomi", "Nico",
        "Nova", "Olive", "Orion", "Otis", "Phoebe", "Remy", "River", "Rory",
        "Sage", "Sasha", "Sienna", "Silas", "Skye", "Stella", "Talia", "Theo",
        "Tessa", "Tristan", "Vera", "Wren", "Xander", "Yara", "Zane", "Zoe",
        "Aaron", "Ada", "Adrian", "Aisha", "Alina", "Andre", "Aspen", "Ayla",
        "Bella", "Ben", "Bodhi", "Brynn", "Caden", "Celine", "Clara", "Cody",
        "Cyrus", "Daisy", "Daria", "Declan", "Delilah", "Devin", "Eliana", "Elio",
        "Elsie", "Ethan", "Ezra", "Faye", "Finn", "Flora", "Gemma", "George",
        "Gia", "Hana", "Hugo", "Isla", "Ivan", "Ivy", "Jesse", "Jonah",
        "Josie", "Julian", "Kaia", "Kenji", "Lana", "Lara", "Layla", "Luca",
        "Mabel", "Mara", "Mira", "Nia", "Nolan", "Opal", "Owen", "Piper",
        "Rhea", "Ronan", "Rose", "Rowan", "Sora", "Tyler", "Vivian", "Wyatt",
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

    var shortAccountAddress: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.count > 12 else { return value }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }
}
