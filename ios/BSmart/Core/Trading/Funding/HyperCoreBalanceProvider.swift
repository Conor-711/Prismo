import Foundation

protocol HyperCoreBalanceProviding: Sendable {
    func snapshot(wallet: DeviceWalletSummary) async throws -> HyperCoreBalanceSnapshot
}

struct HyperCoreBalanceProvider: HyperCoreBalanceProviding {
    let reader: HyperCoreBalanceReading
    let clock: @Sendable () -> Date

    init(reader: HyperCoreBalanceReading = HyperCoreBalanceClient(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.reader = reader; self.clock = clock
    }

    func snapshot(wallet: DeviceWalletSummary) async throws -> HyperCoreBalanceSnapshot {
        guard TradingWalletChallenge.validAddress(wallet.address) else { throw HyperCoreBalanceError.invalidResponse }
        let started = clock()
        try Task.checkCancellation()
        let mode = try Self.mode(await reader.read(.mode, owner: wallet.address))
        try checkTime(started)
        let (usdc, held) = try Self.spot(await reader.read(.spot, owner: wallet.address))
        try checkTime(started)
        let perps: HyperCorePerpsBalance?
        if mode.usesSharedBalance { perps = nil }
        else {
            perps = try Self.perps(await reader.read(.perps, owner: wallet.address))
            try checkTime(started)
        }
        guard try Self.mode(await reader.read(.mode, owner: wallet.address)) == mode else { throw HyperCoreBalanceError.stale }
        try checkTime(started)
        let now = clock()
        let result = HyperCoreBalanceSnapshot(accountID: wallet.accountID, owner: wallet.address, mode: mode,
            usdc: usdc, held: held, perps: perps, requestedAt: started, checkedAt: now)
        try result.validate(wallet: wallet, now: now)
        return result
    }

    private func checkTime(_ started: Date) throws {
        try Task.checkCancellation()
        let age = clock().timeIntervalSince(started)
        guard age.isFinite, age >= 0, age < 30 else { throw HyperCoreBalanceError.stale }
    }

    static func mode(_ value: FundingRPCValue) throws -> HyperCoreAccountMode {
        guard case .string(let raw) = value, let mode = HyperCoreAccountMode(rawValue: raw) else {
            throw HyperCoreBalanceError.invalidResponse
        }
        return mode
    }

    static func spot(_ value: FundingRPCValue) throws -> (HyperCoreUSDCAmount, HyperCoreUSDCAmount) {
        guard case .object(let fields) = value, case .array(let rows) = fields["balances"], rows.count <= 2_048 else {
            throw HyperCoreBalanceError.invalidResponse
        }
        var usdc: (HyperCoreUSDCAmount, HyperCoreUSDCAmount)?
        var tokens = Set<Int>()
        for row in rows {
            guard case .object(let fields) = row, case .integer(let token) = fields["token"], token >= 0,
                  tokens.insert(token).inserted, case .string(let coin) = fields["coin"], !coin.isEmpty else {
                throw HyperCoreBalanceError.invalidResponse
            }
            guard (token == 0) == (coin == "USDC") else { throw HyperCoreBalanceError.invalidResponse }
            if token == 0 {
                let total = try amount(fields["total"]), held = try amount(fields["hold"])
                guard held.units <= total.units else { throw HyperCoreBalanceError.invalidResponse }
                usdc = (total, held)
            }
        }
        return try usdc ?? (HyperCoreUSDCAmount("0"), HyperCoreUSDCAmount("0"))
    }

    static func perps(_ value: FundingRPCValue) throws -> HyperCorePerpsBalance {
        guard case .object(let fields) = value, case .object(let margin) = fields["marginSummary"],
              case .integer(let time) = fields["time"], time > 0, time < 4_102_444_800_000 else {
            throw HyperCoreBalanceError.invalidResponse
        }
        return try .init(equity: amount(margin["accountValue"], signed: true), withdrawable: amount(fields["withdrawable"]),
                         updatedAt: Date(timeIntervalSince1970: Double(time) / 1_000))
    }

    private static func amount(_ value: FundingRPCValue?, signed: Bool = false) throws -> HyperCoreUSDCAmount {
        guard case .string(let text) = value else { throw HyperCoreBalanceError.invalidResponse }
        return try .init(text, signed: signed)
    }
}
