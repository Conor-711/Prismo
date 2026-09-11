import Foundation

enum ArbitrumDepositPolicy {
    static let chainID = 42161
    static let nativeUSDC = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
    static let maximumBurnUnits: UInt64 = 10_000_000_000_000

    enum ValidationError: Error { case invalidAmount, precision, overflow, outsideLimits, unsupportedAsset }

    static func units(_ text: String) throws -> UInt64 {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }) else {
            throw ValidationError.invalidAmount
        }
        let parts = input.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = UInt64(parts[0]), !parts[0].isEmpty else {
            throw ValidationError.invalidAmount
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 6 else { throw ValidationError.precision }
        guard let remainder = UInt64(fraction + String(repeating: "0", count: 6 - fraction.count)) else {
            throw ValidationError.invalidAmount
        }
        let scaled = whole.multipliedReportingOverflow(by: 1_000_000)
        let value = scaled.partialValue.addingReportingOverflow(remainder)
        guard !scaled.overflow, !value.overflow else { throw ValidationError.overflow }
        return value.partialValue
    }

    static func validate(amount: String, chainID: Int, tokenAddress: String) throws -> UInt64 {
        guard chainID == self.chainID, tokenAddress.lowercased() == nativeUSDC.lowercased() else {
            throw ValidationError.unsupportedAsset
        }
        let amount = try units(amount)
        guard amount > 0, amount <= maximumBurnUnits else { throw ValidationError.outsideLimits }
        return amount
    }

    static func formatted(_ units: UInt64) -> String {
        let whole = String(units / 1_000_000)
        let fraction = String(format: "%06llu", units % 1_000_000)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return fraction.isEmpty ? whole : whole + "." + fraction
    }
}
