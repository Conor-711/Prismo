import Foundation

struct HyperliquidFlatAccountProof: Sendable {
    let owner: String
    let checkedAt: Date
    let startedAt: Date

    func validate(owner: String, now: Date) throws {
        guard self.owner == owner, checkedAt >= startedAt, now >= checkedAt,
              now.timeIntervalSince(startedAt) < 30 else { throw HyperliquidTradingCheckError.stale }
    }
}

// Used only for the MVP's explicit mode setup and flat-account withdrawals.
// A failed/missing venue must never be interpreted as no positions.
struct HyperliquidFlatAccountCheck: Sendable {
    var reader: any HyperliquidExecutionReading = HyperliquidExecutionReader()

    func check(owner: String) async throws -> HyperliquidFlatAccountProof {
        let started = Date()
        struct Dex: Decodable { let name: String }
        let raw = try JSONDecoder().decode([Dex?].self, from: await reader.read(.dexs))
        guard !raw.isEmpty, raw[0] == nil, raw.count <= 100,
              raw.dropFirst().allSatisfy({ $0 != nil }) else { throw HyperliquidTradingCheckError.invalidResponse }
        let venues = [""] + raw.dropFirst().compactMap { $0?.name }
        guard Set(venues).count == venues.count else { throw HyperliquidTradingCheckError.invalidResponse }
        for offset in stride(from: 0, to: venues.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(venues[offset..<min(offset + 4, venues.count)])
            try await withThrowingTaskGroup(of: Void.self) { group in
                for dex in batch {
                    group.addTask {
                        let positions = try TradingPositionRow.decode(await reader.read(.positions(owner: owner, dex: dex)), dex: dex)
                        let orders = try JSONDecoder().decode([FundingRPCValue].self, from: await reader.read(.openOrders(owner: owner, dex: dex)))
                        guard positions.isEmpty, orders.isEmpty else { throw HyperliquidFlatAccountError.hasExposure }
                    }
                }
                try await group.waitForAll()
            }
        }
        let proof = HyperliquidFlatAccountProof(owner: owner, checkedAt: Date(), startedAt: started)
        try proof.validate(owner: owner, now: Date())
        return proof
    }
}

enum HyperliquidFlatAccountError: Error, LocalizedError {
    case hasExposure
    var errorDescription: String? {
        "Close your perpetual positions and cancel open orders before continuing.".bSmartLocalized
    }
}
