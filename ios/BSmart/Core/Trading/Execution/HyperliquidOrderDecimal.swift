import Foundation
import BigInt

enum HyperliquidExecutionError: Error, Equatable {
    case invalidDecimal, invalidPrecision, invalidMarket, marketUnavailable
    case invalidIntent, invalidSignature, invalidAcknowledgement
}

// Exchange wire amounts are decimal strings, not display prices or binary floats.
struct HyperliquidOrderDecimal: Equatable, Comparable, Codable, Sendable {
    let wire: String
    let scale: Int
    let units: BigUInt

    init(_ text: String) throws {
        guard (1...80).contains(text.utf8.count),
              text.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else {
            throw HyperliquidExecutionError.invalidDecimal
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts[0].count == 1 || parts[0].first != "0",
              parts.count == 1 || (!parts[1].isEmpty && parts[1].count <= 18) else {
            throw HyperliquidExecutionError.invalidDecimal
        }
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        while fraction.last == "0" { fraction.removeLast() }
        guard let units = BigUInt(String(parts[0]) + fraction), units.bitWidth <= 256 else {
            throw HyperliquidExecutionError.invalidDecimal
        }
        self.units = units
        scale = fraction.count
        wire = String(parts[0]) + (fraction.isEmpty ? "" : "." + fraction)
    }

    var isPositive: Bool { units > 0 }

    init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }

    func validateSize(decimals: Int) throws {
        guard (0...6).contains(decimals), isPositive, scale <= decimals else {
            throw HyperliquidExecutionError.invalidPrecision
        }
    }

    func validatePrice(sizeDecimals: Int) throws {
        guard (0...6).contains(sizeDecimals), isPositive,
              scale <= 6 - sizeDecimals,
              scale == 0 || String(units).count <= 5 else {
            throw HyperliquidExecutionError.invalidPrecision
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let scale = max(lhs.scale, rhs.scale)
        return lhs.units * BigUInt(10).power(scale - lhs.scale)
            < rhs.units * BigUInt(10).power(scale - rhs.scale)
    }
}
