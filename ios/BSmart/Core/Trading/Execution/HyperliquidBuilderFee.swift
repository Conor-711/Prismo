import Foundation

// Frontend fee recipient, not a HIP-3 market deployer. No production default.
struct HyperliquidBuilderFee: Equatable, Sendable {
    let address: String
    let tenthsOfBasisPoint: UInt16

    init(address: String, tenthsOfBasisPoint: UInt16) throws {
        let canonical = address.lowercased()
        guard TradingWalletChallenge.validAddress(canonical), (1...100).contains(tenthsOfBasisPoint) else {
            throw HyperliquidQuoteError.invalidFees
        }
        self.address = canonical
        self.tenthsOfBasisPoint = tenthsOfBasisPoint
    }

    var rate: HyperliquidExactValue {
        get throws { try HyperliquidExactValue(UInt64(tenthsOfBasisPoint)).divided(by: .init(100_000)) }
    }
}

struct HyperliquidBuilderApproval: Equatable, Sendable {
    let owner: String
    let builder: String
    let maximumTenthsOfBasisPoint: UInt16

    static func decode(_ data: Data, owner: String, fee: HyperliquidBuilderFee) throws -> Self {
        do {
            guard TradingWalletChallenge.validAddress(owner), data.count <= 64 else { throw HyperliquidQuoteError.invalidFees }
            let maximum = try JSONDecoder().decode(UInt16.self, from: data)
            // A shared approval can cover spot's higher limit; perps orders remain <= 100.
            guard maximum <= 1_000 else { throw HyperliquidQuoteError.invalidFees }
            let result = Self(owner: owner, builder: fee.address, maximumTenthsOfBasisPoint: maximum)
            try result.validate(owner: owner, fee: fee)
            return result
        } catch let error as HyperliquidQuoteError { throw error }
        catch { throw HyperliquidQuoteError.invalidFees }
    }

    func validate(owner: String, fee: HyperliquidBuilderFee) throws {
        guard self.owner == owner, builder == fee.address,
              maximumTenthsOfBasisPoint >= fee.tenthsOfBasisPoint else { throw HyperliquidQuoteError.builderApprovalRequired }
    }
}
