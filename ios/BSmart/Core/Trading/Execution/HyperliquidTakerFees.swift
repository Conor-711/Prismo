import Foundation

struct HyperliquidMarketFeeContext: Equatable, Codable, Sendable {
    enum GrowthMode: String, Decodable, Sendable { case enabled, disabled }
    let deployerScale: HyperliquidOrderDecimal
    let growthMode: Bool

    init(scale: String, growthMode: Bool) throws {
        let scale = try HyperliquidOrderDecimal(scale)
        let upperBound = try HyperliquidOrderDecimal(growthMode ? "10" : "3")
        guard growthMode ? scale < upperBound : scale <= upperBound else {
            throw HyperliquidQuoteError.invalidFees
        }
        deployerScale = scale
        self.growthMode = growthMode
    }

    func multiplier() throws -> HyperliquidExactValue {
        let scale = HyperliquidExactValue(deployerScale)
        let base = try scale < HyperliquidExactValue(1) ? scale.adding(.init(1)) : scale.multiplied(by: .init(2))
        return try growthMode ? base.divided(by: .init(10)) : base
    }
}

struct HyperliquidTakerFees: Equatable, Sendable {
    let owner: String
    let userRate: HyperliquidOrderDecimal
    let referralDiscount: HyperliquidOrderDecimal

    static func decode(_ data: Data, owner: String) throws -> Self {
        do {
            guard TradingWalletChallenge.validAddress(owner), data.count <= 262_144 else { throw HyperliquidQuoteError.invalidFees }
            let response = try JSONDecoder().decode(Response.self, from: data)
            let rate = try HyperliquidOrderDecimal(response.userCrossRate)
            let discount = try HyperliquidOrderDecimal(response.activeReferralDiscount)
            let one = try HyperliquidOrderDecimal("1")
            guard rate < one, discount <= one else { throw HyperliquidQuoteError.invalidFees }
            return .init(owner: owner, userRate: rate, referralDiscount: discount)
        } catch { throw HyperliquidQuoteError.invalidFees }
    }

    func rate(market: HyperliquidExecutionMarket) throws -> HyperliquidExactValue {
        guard market.collateralToken == 0, let context = market.feeContext else { throw HyperliquidQuoteError.feesUnavailable }
        let discountMultiplier = try HyperliquidExactValue(1).subtracting(.init(referralDiscount))
        return try HyperliquidExactValue(userRate).multiplied(by: context.multiplier()).multiplied(by: discountMultiplier)
    }

    private struct Response: Decodable { let userCrossRate, activeReferralDiscount: String }
}
