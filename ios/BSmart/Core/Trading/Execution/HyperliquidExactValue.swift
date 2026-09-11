import Foundation
import BigInt

// Intermediate quote values may be non-terminating fractions. Only explicit outputs round.
struct HyperliquidExactValue: Equatable, Comparable, Sendable {
    private let numerator: BigUInt
    private let denominator: BigUInt

    init(_ value: HyperliquidOrderDecimal) {
        numerator = value.units
        denominator = BigUInt(10).power(value.scale)
    }
    init(_ value: UInt64) { numerator = BigUInt(value); denominator = 1 }

    private init(_ numerator: BigUInt, _ denominator: BigUInt) throws {
        guard denominator > 0, numerator.bitWidth <= 2048, denominator.bitWidth <= 2048 else {
            throw HyperliquidQuoteError.arithmetic
        }
        let divisor = numerator.greatestCommonDivisor(with: denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    var isPositive: Bool { numerator > 0 }
    func adding(_ other: Self) throws -> Self {
        try Self(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator)
    }
    func subtracting(_ other: Self) throws -> Self {
        let left = numerator * other.denominator, right = other.numerator * denominator
        guard left >= right else { throw HyperliquidQuoteError.arithmetic }
        return try Self(left - right, denominator * other.denominator)
    }
    func multiplied(by other: Self) throws -> Self { try Self(numerator * other.numerator, denominator * other.denominator) }
    func divided(by other: Self) throws -> Self { try Self(numerator * other.denominator, denominator * other.numerator) }

    func rounded(decimalPlaces: Int, up: Bool) throws -> HyperliquidOrderDecimal {
        guard (0...18).contains(decimalPlaces) else { throw HyperliquidQuoteError.arithmetic }
        let result = (numerator * BigUInt(10).power(decimalPlaces)).quotientAndRemainder(dividingBy: denominator)
        let units = result.quotient + (up && result.remainder > 0 ? 1 : 0)
        guard units.bitWidth <= 256 else { throw HyperliquidQuoteError.arithmetic }
        var text = String(units)
        if decimalPlaces > 0 {
            text = String(repeating: "0", count: max(0, decimalPlaces + 1 - text.count)) + text
            text.insert(".", at: text.index(text.endIndex, offsetBy: -decimalPlaces))
        }
        return try .init(text)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.numerator * rhs.denominator == rhs.numerator * lhs.denominator }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator }
}

enum HyperliquidQuoteError: Error, Equatable {
    case arithmetic, invalidBook, invalidFees, feesUnavailable, noLiquidity, stale, builderApprovalRequired
}
