import Foundation

struct HyperliquidTradingSnapshotProvider: Sendable {
    let reader: any HyperliquidExecutionReading
    let clock: @Sendable () -> Date
    let continuousClock: @Sendable () -> ContinuousClock.Instant

    init(reader: any HyperliquidExecutionReading = HyperliquidExecutionReader(),
         clock: @escaping @Sendable () -> Date = { Date() },
         continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.reader = reader
        self.clock = clock
        self.continuousClock = continuousClock
    }

    func snapshot(wallet: DeviceWalletSummary, dex: String, coin: String) async throws -> HyperliquidTradingSnapshot {
        guard wallet.canAuthorizeTransactions, TradingWalletChallenge.validAddress(wallet.address) else {
            throw HyperliquidTradingCheckError.accountChanged
        }
        let started = clock(), continuousStart = continuousClock()
        @Sendable func checkTime() throws {
            try Task.checkCancellation()
            let age = clock().timeIntervalSince(started)
            let elapsed = continuousStart.duration(to: continuousClock())
            guard age.isFinite, age >= 0, age < 15, elapsed >= .zero, elapsed < .seconds(15) else {
                throw HyperliquidTradingCheckError.stale
            }
        }
        @Sendable func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
            try checkTime()
            let data = try await reader.read(query)
            try checkTime()
            return data
        }
        async let dexRequest = read(.dexs)
        async let metaRequest = read(.metadata(dex: dex))
        let (dexs, meta) = try await (dexRequest, metaRequest)
        let market = try HyperliquidExecutionMarket.resolve(perpDexs: dexs, meta: meta, dex: dex, coin: coin)
        guard market.collateralToken == 0 else { throw HyperliquidTradingCheckError.unsupportedCollateral }
        let firstMode = try mode(await read(.mode(owner: wallet.address)))
        // Keep two ordered observation rounds bracketed by account mode reads.
        // Only independent requests within each round overlap.
        func observation() async throws -> (HyperliquidActiveTradingData, HyperliquidTradingPositionState) {
            async let active = read(.active(owner: wallet.address, coin: coin))
            async let positions = read(.positions(owner: wallet.address, dex: dex))
            let data = try await (active, positions)
            return try (.decode(data.0, owner: wallet.address, market: market),
                        .decode(data.1, market: market, now: clock()))
        }
        let (first, firstPositions) = try await observation()
        let (last, lastPositions) = try await observation()
        let lastMode = try mode(await read(.mode(owner: wallet.address)))
        guard firstMode == lastMode else { throw HyperliquidTradingCheckError.stale }
        guard first.leverage == last.leverage,
              firstPositions.position == nil || firstPositions.position?.leverage == first.leverage,
              lastPositions.position == nil || lastPositions.position?.leverage == last.leverage else {
            throw HyperliquidTradingCheckError.leverageChanged
        }
        guard firstPositions.position == lastPositions.position,
              firstPositions.updatedAt <= lastPositions.updatedAt else { throw HyperliquidTradingCheckError.stale }
        try checkTime()
        let result = HyperliquidTradingSnapshot(accountID: wallet.accountID, owner: wallet.address,
            market: market, mode: firstMode, active: last, positions: lastPositions, requestedAt: started,
            checkedAt: clock(), requestedContinuousAt: continuousStart, checkedContinuousAt: continuousClock())
        try result.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
        return result
    }

    private func mode(_ data: Data) throws -> HyperCoreAccountMode {
        guard data.count <= 1024, let raw = try? JSONDecoder().decode(String.self, from: data),
              let mode = HyperCoreAccountMode(rawValue: raw) else { throw HyperliquidTradingCheckError.invalidResponse }
        return mode
    }
}
