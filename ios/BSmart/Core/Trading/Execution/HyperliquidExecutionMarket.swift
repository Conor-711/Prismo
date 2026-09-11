import Foundation

struct HyperliquidExecutionMarket: Equatable, Codable, Sendable {
    enum MarginRestriction: String, Codable, Sendable { case normal, noCross, strictIsolated }
    let coin: String
    let dex: String
    let asset: UInt32
    let sizeDecimals: Int
    let collateralToken: Int
    let maximumLeverage: Int
    let isolatedOnly: Bool
    let marginRestriction: MarginRestriction?
    let feeContext: HyperliquidMarketFeeContext?

    func validatePerpetual() throws {
        let prefix = dex.isEmpty ? "" : dex + ":"
        guard dex != "spot", dex.isEmpty || Self.validComponent(dex),
              coin.hasPrefix(prefix), Self.validComponent(String(coin.dropFirst(prefix.count))),
              !coin.contains("/"), !coin.hasPrefix("@"), !coin.hasPrefix("+"),
              dex.isEmpty ? asset < 10_000 : (110_000...100_099_999).contains(asset) else {
            throw HyperliquidExecutionError.invalidMarket
        }
    }

    // Only raw exchange metadata can construct execution IDs. Filtering is for UI only.
    static func resolve(perpDexs: Data, meta: Data, dex: String, coin: String) throws -> Self {
        do {
            guard perpDexs.count <= 262_144, meta.count <= 1_048_576 else {
                throw HyperliquidExecutionError.invalidMarket
            }
            let dexs = try JSONDecoder().decode([Dex?].self, from: perpDexs)
            guard !dexs.isEmpty, dexs[0] == nil, dexs.count <= 10_000 else {
                throw HyperliquidExecutionError.invalidMarket
            }
            let names = dexs.dropFirst().compactMap { $0?.name }
            guard names.allSatisfy({ validComponent($0) }), Set(names).count == names.count,
                  dex.isEmpty || validComponent(dex) else { throw HyperliquidExecutionError.invalidMarket }
            let dexIndex: Int
            if dex.isEmpty { dexIndex = 0 }
            else if let index = dexs.firstIndex(where: { $0?.name == dex }) { dexIndex = index }
            else { throw HyperliquidExecutionError.marketUnavailable }

            let metadata = try JSONDecoder().decode(Meta.self, from: meta)
            guard metadata.collateralToken >= 0, metadata.collateralToken <= Int(UInt32.max),
                  !metadata.universe.isEmpty, metadata.universe.count <= 10_000 else {
                throw HyperliquidExecutionError.invalidMarket
            }
            let coins = metadata.universe.map(\.name)
            let prefix = dex.isEmpty ? "" : dex + ":"
            guard Set(coins).count == coins.count, coins.allSatisfy({
                $0.hasPrefix(prefix) && validComponent(String($0.dropFirst(prefix.count)))
            }) else { throw HyperliquidExecutionError.invalidMarket }
            guard let index = coins.firstIndex(of: coin) else { throw HyperliquidExecutionError.marketUnavailable }
            let row = metadata.universe[index]
            guard row.isDelisted != true else { throw HyperliquidExecutionError.marketUnavailable }
            guard (0...6).contains(row.szDecimals), row.maxLeverage > 0 else {
                throw HyperliquidExecutionError.invalidMarket
            }
            if let mode = row.marginMode, let legacy = row.onlyIsolated {
                guard legacy == (mode != .normal) else { throw HyperliquidExecutionError.invalidMarket }
            }
            let isolatedOnly = row.marginMode.map { $0 != .normal } ?? (row.onlyIsolated ?? false)
            let fees: HyperliquidMarketFeeContext?
            if dex.isEmpty {
                let scale = try HyperliquidOrderDecimal(row.deployerFeeScale ?? "0")
                guard row.growthMode != .enabled, !scale.isPositive else {
                    throw HyperliquidExecutionError.invalidMarket
                }
                fees = try .init(scale: "0", growthMode: false)
            } else if let scale = row.deployerFeeScale {
                fees = try .init(scale: scale, growthMode: row.growthMode == .enabled)
            } else { fees = nil }
            let asset = dexIndex == 0 ? index : 100_000 + 10_000 * dexIndex + index
            return Self(coin: coin, dex: dex, asset: UInt32(asset), sizeDecimals: row.szDecimals,
                        collateralToken: metadata.collateralToken, maximumLeverage: row.maxLeverage,
                        isolatedOnly: isolatedOnly, marginRestriction: row.marginMode, feeContext: fees)
        } catch let error as HyperliquidExecutionError { throw error }
        catch { throw HyperliquidExecutionError.invalidMarket }
    }

    private init(coin: String, dex: String, asset: UInt32, sizeDecimals: Int,
                 collateralToken: Int, maximumLeverage: Int, isolatedOnly: Bool, marginRestriction: MarginRestriction?,
                 feeContext: HyperliquidMarketFeeContext?) {
        self.coin = coin
        self.dex = dex
        self.asset = asset
        self.sizeDecimals = sizeDecimals
        self.collateralToken = collateralToken
        self.maximumLeverage = maximumLeverage
        self.isolatedOnly = isolatedOnly
        self.marginRestriction = marginRestriction
        self.feeContext = feeContext
    }

    private static func validComponent(_ text: String) -> Bool {
        (1...64).contains(text.utf8.count) && text.utf8.allSatisfy { (33...126).contains($0) && $0 != 58 }
    }

    private struct Dex: Decodable { let name: String }
    private struct Meta: Decodable {
        let universe: [Asset]
        let collateralToken: Int
    }
    private struct Asset: Decodable {
        let name: String
        let szDecimals: Int
        let maxLeverage: Int
        let isDelisted: Bool?
        let onlyIsolated: Bool?
        let marginMode: MarginRestriction?
        let deployerFeeScale: String?
        let growthMode: HyperliquidMarketFeeContext.GrowthMode?
    }
}
