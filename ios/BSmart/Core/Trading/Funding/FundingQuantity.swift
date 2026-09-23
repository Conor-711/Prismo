import Foundation
import BigInt

// Bound Ethereum values to uint256 while delegating arithmetic to pinned BigInt.
struct FundingQuantity: Equatable, Comparable, Sendable {
    private let value: BigUInt

    init(_ value: UInt64) { self.value = BigUInt(value) }

    init(decimal: String) throws {
        guard (1...78).contains(decimal.count), decimal.utf8.allSatisfy({ (48...57).contains($0) }),
              decimal.count == 1 || decimal.first != "0", let value = BigUInt(decimal), value.bitWidth <= 256 else {
            throw FundingPreflightError.invalidResponse
        }
        self.value = value
    }

    init(rpc: String) throws {
        let digits = rpc.dropFirst(2)
        guard rpc.hasPrefix("0x"), (1...64).contains(digits.count),
              digits.count == 1 || digits.first != "0", Self.validHex(digits),
              let value = BigUInt(digits, radix: 16) else { throw FundingPreflightError.invalidResponse }
        self.value = value
    }

    init(abi: String) throws {
        guard abi.hasPrefix("0x"), abi.count == 66, Self.validHex(abi.dropFirst(2)),
              let value = BigUInt(abi.dropFirst(2), radix: 16) else { throw FundingPreflightError.invalidResponse }
        self.value = value
    }

    private init(checked value: BigUInt) throws {
        guard value.bitWidth <= 256 else { throw FundingPreflightError.invalidResponse }
        self.value = value
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
    var rpc: String { "0x" + String(value, radix: 16) }
    var abi: String {
        let hex = String(value, radix: 16)
        return "0x" + String(repeating: "0", count: 64 - hex.count) + hex
    }
    var uint64: UInt64? { UInt64(exactly: value) }
    var bigEndianBytes: Data { value.serialize() }

    func multiplied(by other: Self) throws -> Self { try .init(checked: value * other.value) }

    func subtracting(_ other: Self) throws -> Self {
        guard value >= other.value else { throw FundingPreflightError.invalidResponse }
        return try .init(checked: value - other.value)
    }

    func ceilingScaled(numerator: UInt64, denominator: UInt64) throws -> Self {
        guard denominator > 0 else { throw FundingPreflightError.invalidResponse }
        let product = value * BigUInt(numerator)
        return try .init(checked: (product + BigUInt(denominator - 1)) / BigUInt(denominator))
    }

    func formatted(decimals: Int) -> String {
        guard (0...18).contains(decimals) else { return "" }
        let digits = String(value)
        guard decimals > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let split = padded.index(padded.endIndex, offsetBy: -decimals)
        var fraction = String(padded[split...])
        while fraction.last == "0" { fraction.removeLast() }
        return String(padded[..<split]) + (fraction.isEmpty ? "" : "." + fraction)
    }

    private static func validHex(_ text: Substring) -> Bool {
        text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

enum FundingPreflightError: Error, LocalizedError, Equatable {
    case unavailable, invalidResponse, wrongChain, staleState, routeChanged, transferRestricted
    case unsupportedWallet, insufficientUSDC, insufficientETH, authorizationUsed, pendingTransaction
    case simulationFailed, excessiveFee, feeQuoteChanged
    case invalidAuthorization, expiredAuthorization
    case rpcRejected(method: String, code: Int)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Arbitrum could not be reached. No transfer was made.".bSmartLocalized
        case .invalidResponse: return "Arbitrum returned data that could not be verified.".bSmartLocalized
        case .wrongChain: return "The network is not Arbitrum One. No transfer was made.".bSmartLocalized
        case .staleState: return "The network check expired or changed. Refresh before continuing.".bSmartLocalized
        case .routeChanged: return "The deposit contract configuration could not be verified.".bSmartLocalized
        case .transferRestricted: return "USDC transfers are currently restricted for this route or wallet.".bSmartLocalized
        case .unsupportedWallet: return "This deposit requires the verified device wallet.".bSmartLocalized
        case .insufficientUSDC: return "There is not enough native USDC in this Arbitrum wallet.".bSmartLocalized
        case .insufficientETH: return "There is not enough Arbitrum ETH for the maximum network fee.".bSmartLocalized
        case .authorizationUsed: return "This deposit authorization has already been used or canceled.".bSmartLocalized
        case .pendingTransaction: return "A wallet transaction is pending or changed. Wait and refresh.".bSmartLocalized
        case .simulationFailed: return "The deposit simulation failed. No transfer was made.".bSmartLocalized
        case .invalidAuthorization: return "The USDC contract rejected the authorization signature. No transfer was made.".bSmartLocalized
        case .expiredAuthorization: return "The USDC authorization expired. Enter the amount again.".bSmartLocalized
        case .rpcRejected(let method, let code):
            return "The network rejected %@ (code %@). No transfer was made.".bSmartLocalized(method, String(code))
        case .excessiveFee: return "The network fee exceeds the deposit safety limit. Try again later.".bSmartLocalized
        case .feeQuoteChanged: return "Network fees changed. Review a new quote and confirm again.".bSmartLocalized
        }
    }
}
