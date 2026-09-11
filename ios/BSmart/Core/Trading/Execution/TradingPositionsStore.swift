import Foundation
import Combine

struct TradingPositionRow: Identifiable, Sendable {
    let coin: String
    let dex: String
    let quantity: HyperliquidSignedDecimal
    let entryPrice: HyperliquidOrderDecimal?
    let unrealizedPnL: HyperliquidSignedDecimal
    let leverage: Int
    var id: String { coin }
    var symbol: String { String(coin.split(separator: ":").last ?? Substring(coin)) }

    static func decode(_ data: Data, dex: String, now: Date = Date()) throws -> [Self] {
        struct Response: Decodable {
            struct Row: Decodable {
                struct Position: Decodable {
                    struct Leverage: Decodable { let value: Int }
                    let coin, szi, unrealizedPnl: String
                    let entryPx: String?
                    let leverage: Leverage
                }
                let type: String
                let position: Position
            }
            let assetPositions: [Row]
            let time: UInt64
        }
        guard data.count <= 1_048_576 else { throw HyperliquidTradingCheckError.invalidResponse }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let age = now.timeIntervalSince1970 - Double(response.time) / 1000
        guard age >= -15, age < 60, response.assetPositions.count <= 1000 else {
            throw HyperliquidTradingCheckError.stale
        }
        var ids = Set<String>()
        return try response.assetPositions.compactMap { row in
            let p = row.position
            let parts = p.coin.split(separator: ":", omittingEmptySubsequences: false)
            guard row.type == "oneWay", ids.insert(p.coin).inserted,
                  dex.isEmpty ? parts.count == 1 : (parts.count == 2 && parts[0] == dex),
                  parts.allSatisfy({ !$0.isEmpty }), p.leverage.value > 0,
                  !p.coin.hasPrefix("@"), !p.coin.contains("/") else {
                throw HyperliquidTradingCheckError.invalidResponse
            }
            let quantity = try HyperliquidSignedDecimal(p.szi)
            guard quantity.magnitude.isPositive else { return nil }
            return try .init(coin: p.coin, dex: dex, quantity: quantity,
                entryPrice: p.entryPx.map { try HyperliquidOrderDecimal($0) },
                unrealizedPnL: HyperliquidSignedDecimal(p.unrealizedPnl), leverage: p.leverage.value)
        }
    }
}

@MainActor
final class TradingPositionsStore: ObservableObject {
    @Published private(set) var rows: [TradingPositionRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false
    @Published private(set) var errorMessage: String?
    private let reader: any HyperliquidExecutionReading
    private let service: any AccountWalletServicing
    private var revision = UUID()

    init(service: any AccountWalletServicing, reader: any HyperliquidExecutionReading = HyperliquidExecutionReader()) {
        self.service = service; self.reader = reader
    }

    func refresh(wallet: DeviceWalletSummary) async {
        let token = UUID(); revision = token; isLoading = true; errorMessage = nil; rows = []; didLoad = false
        defer { if token == revision { isLoading = false } }
        do {
            let registration = try await service.walletRegistration()
            guard registration.accountId == wallet.accountID, registration.address == wallet.address else {
                throw DeviceWalletError.accountChanged
            }
            struct Dex: Decodable { let name: String }
            let raw = try JSONDecoder().decode([Dex?].self, from: await reader.read(.dexs))
            guard !raw.isEmpty, raw[0] == nil, raw.count <= 100,
                  raw.dropFirst().allSatisfy({ $0 != nil }) else { throw HyperliquidTradingCheckError.invalidResponse }
            let dexs = [""] + raw.dropFirst().compactMap { $0?.name }
            guard Set(dexs).count == dexs.count else { throw HyperliquidTradingCheckError.invalidResponse }
            var result: [TradingPositionRow] = []
            var incomplete = false
            let reader = self.reader
            // Bound concurrency; each venue failure remains visible instead of looking like no positions.
            for offset in stride(from: 0, to: dexs.count, by: 4) {
                try Task.checkCancellation()
                let batch = Array(dexs[offset..<min(offset + 4, dexs.count)])
                await withTaskGroup(of: [TradingPositionRow]?.self) { group in
                    for dex in batch {
                        group.addTask {
                            do { return try TradingPositionRow.decode(await reader.read(.positions(owner: wallet.address, dex: dex)), dex: dex) }
                            catch { return nil }
                        }
                    }
                    for await rows in group {
                        if let rows { result.append(contentsOf: rows) } else { incomplete = true }
                    }
                }
            }
            try Task.checkCancellation()
            guard token == revision, service.walletAccountID == wallet.accountID else { return }
            rows = result.sorted { $0.coin < $1.coin }; didLoad = true
            if incomplete { errorMessage = "Some positions could not be loaded. Refresh before trading.".bSmartLocalized }
        } catch {
            guard token == revision, !Task.isCancelled else { return }
            errorMessage = "Positions could not be loaded. Your positions have not changed.".bSmartLocalized
        }
    }

    func clear() { revision = UUID(); rows = []; isLoading = false; didLoad = false; errorMessage = nil }
}
