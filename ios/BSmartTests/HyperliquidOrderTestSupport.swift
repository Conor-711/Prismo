import XCTest
@testable import BSmart

enum HyperliquidOrderTestSupport {
    static let wallet = DeviceWalletSummary(accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf", recoveryVerified: true)
    static let dexs = Data(#"[null,{"name":"xyz"}]"#.utf8)

    static func market(asset: UInt32 = 110002, decimals: Int = 3) throws -> HyperliquidExecutionMarket {
        let builder = asset >= 110000
        let index = builder ? Int(asset - 110000) : Int(asset)
        let rows: [[String: Any]] = (0...index).map {
            ["name": (builder ? "xyz:" : "") + "ASSET\($0)", "szDecimals": decimals, "maxLeverage": 20]
        }
        let meta = try JSONSerialization.data(withJSONObject: ["collateralToken": 0, "universe": rows])
        return try .resolve(perpDexs: dexs, meta: meta, dex: builder ? "xyz" : "",
                            coin: (builder ? "xyz:" : "") + "ASSET\(index)")
    }

    static func order(side: HyperliquidOrderIntent.Side = .buy, size: String = "3.125",
                      price: String = "230.9", reduceOnly: Bool = false,
                      cloid: String = "0x00000000000000000000000000000002", nonce: UInt64 = 1_789_084_800_001,
                      expiresAfter: UInt64 = 1_789_084_830_001) throws -> HyperliquidOrderIntent {
        try .init(wallet: wallet, market: market(), side: side, size: size, limitPrice: price,
                  reduceOnly: reduceOnly, cloid: cloid, nonce: nonce, expiresAfter: expiresAfter)
    }
}
