import Foundation

struct CCTPSourceGasBudget: Equatable, Sendable {
    let gasLimit: FundingQuantity
    let maximumFeePerGas: FundingQuantity
    let maximumNetworkFee: FundingQuantity

    init(estimatedGas: FundingQuantity, gasPrice: FundingQuantity, baseFee: FundingQuantity) throws {
        guard estimatedGas >= FundingQuantity(21_000) else {
            throw FundingPreflightError.invalidResponse
        }
        gasLimit = try estimatedGas.ceilingScaled(numerator: 120, denominator: 100)
        maximumFeePerGas = try Self.feePerGas(gasPrice: gasPrice, baseFee: baseFee)
        maximumNetworkFee = try gasLimit.multiplied(by: maximumFeePerGas)
        guard gasLimit <= FundingQuantity(5_000_000), maximumNetworkFee <= FundingQuantity(10_000_000_000_000_000) else {
            throw FundingPreflightError.excessiveFee
        }
    }

    static func feePerGas(gasPrice: FundingQuantity, baseFee: FundingQuantity) throws -> FundingQuantity {
        guard gasPrice > FundingQuantity(0), baseFee > FundingQuantity(0) else { throw FundingPreflightError.invalidResponse }
        return try max(gasPrice, baseFee).ceilingScaled(numerator: 2, denominator: 1)
    }
}
