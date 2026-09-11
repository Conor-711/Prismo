import Foundation
import WalletCore

enum CCTPSourceReadCodec {
    // The fixed source reads use only static ABI words; the burn codec owns dynamic tuples.
    static func call(_ signature: String, words: [String] = []) throws -> String {
        guard words.allSatisfy({ $0.count == 66 && FundingHex.decode($0)?.count == 32 }) else {
            throw FundingPreflightError.invalidResponse
        }
        let selector = Hash.keccak256(data: Data(signature.utf8)).prefix(4)
        return FundingHex.encode(Data(selector)) + words.map { String($0.dropFirst(2)) }.joined()
    }

    static func addressWord(_ address: String) throws -> String {
        let normalized = address.lowercased()
        guard TradingWalletChallenge.validAddress(normalized) else {
            throw FundingPreflightError.unsupportedWallet
        }
        return "0x" + String(repeating: "0", count: 24) + normalized.dropFirst(2)
    }

    static func boolean(_ result: FundingRPCValue) throws -> Bool {
        let word = try FundingQuantity(abi: result.text())
        guard word == FundingQuantity(0) || word == FundingQuantity(1) else { throw FundingPreflightError.invalidResponse }
        return word == FundingQuantity(1)
    }

    static func codeHash(_ result: FundingRPCValue) throws -> String {
        guard let code = FundingHex.decode(try result.text()), !code.isEmpty, code.count <= 24_576 else {
            throw FundingPreflightError.routeChanged
        }
        return FundingHex.encode(Hash.keccak256(data: code))
    }
}
