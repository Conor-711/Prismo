import Foundation

// Order-only preflight. Two independent observations bracket signing in the store;
// the venue enforces actual capacity at execution. This is not an atomic snapshot.
struct HyperliquidOrderAccountObservation: Sendable {
    let reader: any HyperliquidExecutionReading
    let clock: @Sendable () -> Date
    let continuousClock: @Sendable () -> ContinuousClock.Instant

    func snapshot(wallet: DeviceWalletSummary, dex: String, coin: String) async throws -> HyperliquidTradingSnapshot {
        try await withThrowingTaskGroup(of: HyperliquidTradingSnapshot.self) { group in
            group.addTask { try await observe(wallet: wallet, dex: dex, coin: coin) }
            group.addTask {
                try await Task.sleep(for: .seconds(11))
                throw HyperliquidTradingCheckError.stale
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw HyperliquidTradingCheckError.unavailable }
            return first
        }
    }

    private func observe(wallet: DeviceWalletSummary, dex: String, coin: String) async throws -> HyperliquidTradingSnapshot {
        guard wallet.canAuthorizeTransactions, TradingWalletChallenge.validAddress(wallet.address) else {
            throw HyperliquidTradingCheckError.accountChanged
        }
        let started = clock(), instant = continuousClock()
        @Sendable func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
            try Task.checkCancellation()
            let data = try await reader.read(query)
            try Task.checkCancellation()
            let age = clock().timeIntervalSince(started), elapsed = instant.duration(to: continuousClock())
            guard age.isFinite, age >= 0, age < 11, elapsed >= .zero, elapsed < .seconds(11) else {
                throw HyperliquidTradingCheckError.stale
            }
            return data
        }
        async let dexs = read(.dexs)
        async let meta = read(.metadata(dex: dex))
        async let modeData = read(.mode(owner: wallet.address))
        async let activeData = read(.active(owner: wallet.address, coin: coin))
        async let positionsData = read(.positions(owner: wallet.address, dex: dex))
        let (rawDexs, rawMeta, rawMode, rawActive, rawPositions) = try await (dexs, meta, modeData, activeData, positionsData)
        let market = try HyperliquidExecutionMarket.resolve(perpDexs: rawDexs, meta: rawMeta, dex: dex, coin: coin)
        guard market.collateralToken == 0 else { throw HyperliquidTradingCheckError.unsupportedCollateral }
        guard rawMode.count <= 1024, let value = try? JSONDecoder().decode(String.self, from: rawMode),
              let mode = HyperCoreAccountMode(rawValue: value) else { throw HyperliquidTradingCheckError.invalidResponse }
        let active = try HyperliquidActiveTradingData.decode(rawActive, owner: wallet.address, market: market)
        let positions = try HyperliquidTradingPositionState.decode(rawPositions, market: market, now: clock())
        guard positions.position == nil || positions.position?.leverage == active.leverage else {
            throw HyperliquidTradingCheckError.leverageChanged
        }
        let snapshot = HyperliquidTradingSnapshot(accountID: wallet.accountID, owner: wallet.address,
            market: market, mode: mode, active: active, positions: positions, requestedAt: started,
            checkedAt: clock(), requestedContinuousAt: instant, checkedContinuousAt: continuousClock())
        try snapshot.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
        return snapshot
    }
}
