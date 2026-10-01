import Foundation

// Internal, offline signing boundary. No endpoint or UI currently consumes it.
struct EquityCowSigningPayload: Decodable {
    let schema: String
    let state: String
    let signingStartedAt: String
    let preparationHash: String
    let prepared: Prepared
    let executionEnabled: Bool

    struct Prepared: Decodable {
        let schema: String
        let intentId: UUID
        let intentVersion: Int
        let account: UUID
        let fingerprint: String
        let owner: String
        let instrument: Instrument
        let side: String
        let order: Order
        let domain: Domain
        let orderUid: String
        let orderDigest: String
        let expiresAt: String
    }
    struct Instrument: Decodable {
        let assetId: UUID
        let symbol: String
        let network: String
        let chainId: Int
        let token: String
        let usdc: String
        let tokenVariant: String
        let maxLeverage: Int
    }
    struct Order: Decodable {
        let sellToken: String
        let buyToken: String
        let receiver: String
        let sellAmount: String
        let buyAmount: String
        let validTo: UInt32
        let appData: String
        let feeAmount: String
        let kind: String
        let partiallyFillable: Bool
        let sellTokenBalance: String
        let buyTokenBalance: String
    }
    struct Domain: Decodable {
        let name: String
        let version: String
        let chainId: Int
        let verifyingContract: String
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 16_384,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EquityCowCodecError.invalidPayload
        }
        // Codable normally ignores unknown keys. Reject extensions rather than
        // silently dropping hook/funding/signing-scheme fields before signing.
        try exact(root, "schema state signingStartedAt preparationHash prepared executionEnabled")
        let p = try child(root, "prepared")
        try exact(p, "schema intentId intentVersion account fingerprint owner instrument side order domain orderUid orderDigest expiresAt")
        try exact(child(p, "instrument"), "assetId symbol network chainId token usdc tokenVariant maxLeverage")
        try exact(child(p, "domain"), "name version chainId verifyingContract")
        try exact(child(p, "order"), "sellToken buyToken receiver sellAmount buyAmount validTo appData feeAmount kind partiallyFillable sellTokenBalance buyTokenBalance")
        return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private static func exact(_ value: [String: Any], _ fields: String) throws {
        guard Set(value.keys) == Set(fields.split(separator: " ").map(String.init)) else {
            throw EquityCowCodecError.invalidPayload
        }
    }
    private static func child(_ value: [String: Any], _ key: String) throws -> [String: Any] {
        guard let child = value[key] as? [String: Any] else { throw EquityCowCodecError.invalidPayload }
        return child
    }
}

// Values captured from the reviewed quote, not reconstructed from signing data.
struct EquityCowConsent {
    let intentID: UUID
    let version: Int
    let accountID: UUID
    let owner: String
    let assetID: UUID
    let symbol: String
    let network: String
    let token: String
    let inputAmountRaw: String
    let minimumOutputAmountRaw: String
    let fingerprint: String
    let preparationHash: String
    let orderUID: String
    let expiresAt: String
}

enum EquityCowCodecError: Error {
    case invalidPayload, invalidBinding, expired, invalidSignature
}
