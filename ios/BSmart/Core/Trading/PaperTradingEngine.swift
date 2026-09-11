import Foundation

enum PaperTradeSide: String, Codable, CaseIterable, Identifiable {
    case long
    case short

    var id: Self { self }
    var sign: Double { self == .long ? 1 : -1 }

    var title: String {
        switch self {
        case .long: "Buy / Long".bSmartLocalized
        case .short: "Sell / Short".bSmartLocalized
        }
    }
}

enum PaperTradeExecutionKind: String, Codable {
    case opened
    case increased
    case reduced
    case closed
    case flipped
    case liquidated

    var title: String {
        switch self {
        case .opened: "OPENED".bSmartLocalized
        case .increased: "INCREASED".bSmartLocalized
        case .reduced: "REDUCED".bSmartLocalized
        case .closed: "CLOSED".bSmartLocalized
        case .flipped: "FLIPPED".bSmartLocalized
        case .liquidated: "LIQUIDATED".bSmartLocalized
        }
    }
}

struct PaperTradingPosition: Identifiable, Codable, Hashable {
    let id: UUID
    let coin: String
    let symbol: String
    let dexDisplayName: String
    var side: PaperTradeSide
    var size: Double
    var entryPrice: Double
    var lastMarkPrice: Double
    var leverage: Int
    var maxLeverage: Int
    var isolatedMargin: Double
    var fundingPnL: Double
    var lastFundingAt: Date
    let openedAt: Date
    var updatedAt: Date

    var signedSize: Double { size * side.sign }
    var notional: Double { size * lastMarkPrice }
    var unrealizedPnL: Double { side.sign * size * (lastMarkPrice - entryPrice) }
    var positionEquity: Double { isolatedMargin + unrealizedPnL }
    var maintenanceMarginRate: Double { 1 / (2 * Double(max(1, maxLeverage))) }
    var maintenanceMargin: Double { notional * maintenanceMarginRate }

    var liquidationPrice: Double? {
        guard size > 0 else { return nil }
        let marginPerUnit = isolatedMargin / size
        let price: Double
        switch side {
        case .long:
            price = (entryPrice - marginPerUnit) / (1 - maintenanceMarginRate)
        case .short:
            price = (entryPrice + marginPerUnit) / (1 + maintenanceMarginRate)
        }
        guard price.isFinite, price > 0 else { return nil }
        return price
    }

    var returnOnMargin: Double {
        guard isolatedMargin > 0 else { return 0 }
        return unrealizedPnL / isolatedMargin
    }
}

struct PaperTradeExecution: Identifiable, Codable, Hashable {
    let id: UUID
    let coin: String
    let symbol: String
    let side: PaperTradeSide
    let kind: PaperTradeExecutionKind
    let size: Double
    let price: Double
    let notional: Double
    let leverage: Int
    let fee: Double
    let realizedPnL: Double
    let executedAt: Date
}

struct PaperTradingAccount: Codable, Hashable {
    static let schemaVersion = 1
    static let startingBalance = 10_000.0

    var version: Int
    var initialBalance: Double
    var availableBalance: Double
    var realizedPnL: Double
    var feesPaid: Double
    var positions: [PaperTradingPosition]
    var executions: [PaperTradeExecution]
    var createdAt: Date
    var updatedAt: Date

    static func fresh(now: Date = Date()) -> PaperTradingAccount {
        PaperTradingAccount(
            version: schemaVersion,
            initialBalance: startingBalance,
            availableBalance: startingBalance,
            realizedPnL: 0,
            feesPaid: 0,
            positions: [],
            executions: [],
            createdAt: now,
            updatedAt: now,
            valuationHistory: [PortfolioValuePoint(timestamp: now, value: startingBalance)]
        )
    }

    var marginUsed: Double { positions.reduce(0) { $0 + $1.isolatedMargin } }
    var unrealizedPnL: Double { positions.reduce(0) { $0 + $1.unrealizedPnL } }
    var equity: Double { availableBalance + marginUsed + unrealizedPnL }
    var totalPnL: Double { equity - initialBalance }
    var totalReturn: Double { initialBalance > 0 ? totalPnL / initialBalance : 0 }
    var valuationHistory: [PortfolioValuePoint]?
}

struct PaperOrderPreview: Equatable {
    let side: PaperTradeSide
    let fillPrice: Double
    let margin: Double
    let notional: Double
    let size: Double
    let leverage: Int
    let fee: Double
    let estimatedLiquidationPrice: Double?
}

enum PaperTradingError: LocalizedError, Equatable {
    case invalidAmount
    case invalidPrice
    case orderTooSmall
    case insufficientBalance(required: Double, available: Double)
    case positionNotFound
    case invalidLeverage

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter a valid margin amount.".bSmartLocalized
        case .invalidPrice: "A live Hyperliquid price is required.".bSmartLocalized
        case .orderTooSmall: "The order is below this market's size precision.".bSmartLocalized
        case let .insufficientBalance(required, available):
            "This order requires %@ but only %@ is available.".bSmartLocalized(
                required.formatted(.bSmartDollars),
                available.formatted(.bSmartDollars)
            )
        case .positionNotFound: "No open position was found.".bSmartLocalized
        case .invalidLeverage: "Choose leverage within this market's allowed range.".bSmartLocalized
        }
    }
}

protocol PaperTradingPersisting {
    func load() -> PaperTradingAccount?
    func save(_ account: PaperTradingAccount)
    func clear()
}

final class UserDefaultsPaperTradingStore: PaperTradingPersisting {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "bsmart.paper-trading.v1") {
        self.defaults = defaults
        self.key = key
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PaperTradingAccount? {
        guard let data = defaults.data(forKey: key),
              let value = try? decoder.decode(PaperTradingAccount.self, from: data),
              value.version == PaperTradingAccount.schemaVersion
        else { return nil }
        return value
    }

    func save(_ account: PaperTradingAccount) {
        guard let data = try? encoder.encode(account) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class PaperTradingEngine: ObservableObject {
    static let simulatedTakerFeeRate = 0.00045

    @Published private(set) var account: PaperTradingAccount
    @Published private(set) var latestLiquidation: PaperTradeExecution?

    private let storage: PaperTradingPersisting

    init(storage: PaperTradingPersisting = UserDefaultsPaperTradingStore()) {
        self.storage = storage
        self.account = storage.load() ?? .fresh()
    }

    func preview(
        side: PaperTradeSide,
        margin: Double,
        leverage: Int,
        market: HyperliquidPerpMarket
    ) throws -> PaperOrderPreview {
        guard margin.isFinite, margin > 0 else { throw PaperTradingError.invalidAmount }
        guard (1...market.maxLeverage).contains(leverage) else {
            throw PaperTradingError.invalidLeverage
        }
        let fillPrice = side == .long ? market.bestAvailableBuyPrice : market.bestAvailableSellPrice
        guard fillPrice.isFinite, fillPrice > 0 else { throw PaperTradingError.invalidPrice }
        let requestedNotional = margin * Double(leverage)
        let size = market.roundedSize(requestedNotional / fillPrice)
        guard size > 0 else { throw PaperTradingError.orderTooSmall }
        let notional = size * fillPrice
        let actualMargin = notional / Double(leverage)
        let fee = notional * Self.simulatedTakerFeeRate
        return PaperOrderPreview(
            side: side,
            fillPrice: fillPrice,
            margin: actualMargin,
            notional: notional,
            size: size,
            leverage: leverage,
            fee: fee,
            estimatedLiquidationPrice: Self.estimatedLiquidationPrice(
                side: side,
                entryPrice: fillPrice,
                size: size,
                isolatedMargin: actualMargin,
                maxLeverage: market.maxLeverage
            )
        )
    }

    @discardableResult
    func placeMarketOrder(
        side: PaperTradeSide,
        margin: Double,
        leverage: Int,
        market: HyperliquidPerpMarket,
        now: Date = Date()
    ) throws -> PaperTradeExecution {
        let preview = try preview(side: side, margin: margin, leverage: leverage, market: market)
        var working = account
        let existingIndex = working.positions.firstIndex(where: { $0.coin == market.coin })
        let existing = existingIndex.map { working.positions[$0] }

        let execution: PaperTradeExecution
        if let existing, existing.side != side {
            execution = try reduceOrFlip(
                existing: existing,
                existingIndex: existingIndex!,
                desiredSide: side,
                desiredSize: preview.size,
                leverage: leverage,
                fillPrice: preview.fillPrice,
                market: market,
                now: now,
                account: &working
            )
        } else {
            execution = try openOrIncrease(
                existing: existing,
                existingIndex: existingIndex,
                side: side,
                size: preview.size,
                leverage: existing?.leverage ?? leverage,
                fillPrice: preview.fillPrice,
                market: market,
                now: now,
                account: &working
            )
        }

        working.executions.insert(execution, at: 0)
        working.executions = Array(working.executions.prefix(250))
        working.updatedAt = now
        commit(working)
        return execution
    }

    @discardableResult
    func closePosition(
        coin: String,
        market: HyperliquidPerpMarket,
        now: Date = Date()
    ) throws -> PaperTradeExecution {
        guard let index = account.positions.firstIndex(where: { $0.coin == coin }) else {
            throw PaperTradingError.positionNotFound
        }
        var working = account
        let position = working.positions[index]
        let fillPrice = position.side == .long
            ? market.bestAvailableSellPrice
            : market.bestAvailableBuyPrice
        let execution = closeQuantity(
            position: position,
            index: index,
            size: position.size,
            fillPrice: fillPrice,
            kind: .closed,
            now: now,
            account: &working
        )
        working.executions.insert(execution, at: 0)
        working.updatedAt = now
        commit(working)
        return execution
    }

    func updateLeverage(
        coin: String,
        leverage: Int,
        markPrice: Double,
        now: Date = Date()
    ) throws {
        guard let index = account.positions.firstIndex(where: { $0.coin == coin }) else {
            throw PaperTradingError.positionNotFound
        }
        var working = account
        var position = working.positions[index]
        guard (1...position.maxLeverage).contains(leverage) else {
            throw PaperTradingError.invalidLeverage
        }
        let targetInitialMargin = position.size * markPrice / Double(leverage)
        let targetMargin = max(0, targetInitialMargin + position.fundingPnL)
        let difference = targetMargin - position.isolatedMargin
        if difference > working.availableBalance {
            throw PaperTradingError.insufficientBalance(
                required: difference,
                available: working.availableBalance
            )
        }
        working.availableBalance -= difference
        position.isolatedMargin = targetMargin
        position.leverage = leverage
        position.updatedAt = now
        working.positions[index] = position
        working.updatedAt = now
        commit(working)
    }

    func markToMarket(_ market: HyperliquidPerpMarket, now: Date = Date()) {
        guard let index = account.positions.firstIndex(where: { $0.coin == market.coin }) else { return }
        var working = account
        var position = working.positions[index]
        position.lastMarkPrice = market.markPrice
        position.updatedAt = now
        let completedFundingHours = max(0, Int(now.timeIntervalSince(position.lastFundingAt) / 3_600))
        var requiresPersistence = false
        if completedFundingHours > 0 {
            let funding = -position.side.sign
                * position.size
                * market.oraclePrice
                * market.fundingRate
                * Double(completedFundingHours)
            position.isolatedMargin += funding
            position.fundingPnL += funding
            position.lastFundingAt = position.lastFundingAt.addingTimeInterval(
                Double(completedFundingHours) * 3_600
            )
            requiresPersistence = true
        }
        working.positions[index] = position

        if position.positionEquity <= position.maintenanceMargin {
            let execution = liquidate(
                position: position,
                index: index,
                market: market,
                now: now,
                account: &working
            )
            working.executions.insert(execution, at: 0)
            latestLiquidation = execution
            requiresPersistence = true
        }

        working.updatedAt = now
        working.valuationHistory = PortfolioValuationHistory.recording(
            working.equity, at: now, in: working.valuationHistory ?? [])
        let historyChanged = working.valuationHistory != account.valuationHistory
        account = working
        if requiresPersistence || historyChanged {
            storage.save(working)
        }
    }

    func resetAccount(now: Date = Date()) {
        storage.clear()
        latestLiquidation = nil
        let fresh = PaperTradingAccount.fresh(now: now)
        account = fresh
        storage.save(fresh)
    }

    private func openOrIncrease(
        existing: PaperTradingPosition?,
        existingIndex: Int?,
        side: PaperTradeSide,
        size: Double,
        leverage: Int,
        fillPrice: Double,
        market: HyperliquidPerpMarket,
        now: Date,
        account: inout PaperTradingAccount
    ) throws -> PaperTradeExecution {
        let notional = size * fillPrice
        let margin = notional / Double(leverage)
        let fee = notional * Self.simulatedTakerFeeRate
        let required = margin + fee
        guard account.availableBalance >= required else {
            throw PaperTradingError.insufficientBalance(
                required: required,
                available: account.availableBalance
            )
        }
        account.availableBalance -= required
        account.feesPaid += fee

        let kind: PaperTradeExecutionKind
        if var existing, let existingIndex {
            let totalSize = existing.size + size
            existing.entryPrice = (existing.entryPrice * existing.size + fillPrice * size) / totalSize
            existing.size = totalSize
            existing.lastMarkPrice = fillPrice
            existing.isolatedMargin += margin
            existing.updatedAt = now
            account.positions[existingIndex] = existing
            kind = .increased
        } else {
            account.positions.append(PaperTradingPosition(
                id: UUID(),
                coin: market.coin,
                symbol: market.symbol,
                dexDisplayName: market.dexDisplayName,
                side: side,
                size: size,
                entryPrice: fillPrice,
                lastMarkPrice: fillPrice,
                leverage: leverage,
                maxLeverage: market.maxLeverage,
                isolatedMargin: margin,
                fundingPnL: 0,
                lastFundingAt: now,
                openedAt: now,
                updatedAt: now
            ))
            kind = .opened
        }

        return PaperTradeExecution(
            id: UUID(),
            coin: market.coin,
            symbol: market.symbol,
            side: side,
            kind: kind,
            size: size,
            price: fillPrice,
            notional: notional,
            leverage: leverage,
            fee: fee,
            realizedPnL: 0,
            executedAt: now
        )
    }

    private func reduceOrFlip(
        existing: PaperTradingPosition,
        existingIndex: Int,
        desiredSide: PaperTradeSide,
        desiredSize: Double,
        leverage: Int,
        fillPrice: Double,
        market: HyperliquidPerpMarket,
        now: Date,
        account: inout PaperTradingAccount
    ) throws -> PaperTradeExecution {
        let closeSize = min(existing.size, desiredSize)
        let isFlip = desiredSize > existing.size
        let closing = closeQuantity(
            position: existing,
            index: existingIndex,
            size: closeSize,
            fillPrice: fillPrice,
            kind: isFlip ? .flipped : (closeSize == existing.size ? .closed : .reduced),
            now: now,
            account: &account
        )

        guard isFlip else { return closing }
        let remainingSize = desiredSize - existing.size
        let opening = try openOrIncrease(
            existing: nil,
            existingIndex: nil,
            side: desiredSide,
            size: remainingSize,
            leverage: leverage,
            fillPrice: fillPrice,
            market: market,
            now: now,
            account: &account
        )
        return PaperTradeExecution(
            id: UUID(),
            coin: market.coin,
            symbol: market.symbol,
            side: desiredSide,
            kind: .flipped,
            size: desiredSize,
            price: fillPrice,
            notional: desiredSize * fillPrice,
            leverage: leverage,
            fee: closing.fee + opening.fee,
            realizedPnL: closing.realizedPnL,
            executedAt: now
        )
    }

    private func closeQuantity(
        position: PaperTradingPosition,
        index: Int,
        size: Double,
        fillPrice: Double,
        kind: PaperTradeExecutionKind,
        now: Date,
        account: inout PaperTradingAccount
    ) -> PaperTradeExecution {
        let fraction = min(1, size / position.size)
        let releasedMargin = position.isolatedMargin * fraction
        let fundingShare = position.fundingPnL * fraction
        let pricePnL = position.side.sign * size * (fillPrice - position.entryPrice)
        let notional = size * fillPrice
        let fee = notional * Self.simulatedTakerFeeRate
        let returnedCollateral = max(0, releasedMargin + pricePnL - fee)
        account.availableBalance += returnedCollateral
        account.realizedPnL += pricePnL + fundingShare
        account.feesPaid += fee

        if fraction >= 1 - 1e-10 {
            account.positions.remove(at: index)
        } else {
            var remaining = position
            remaining.size -= size
            remaining.isolatedMargin -= releasedMargin
            remaining.fundingPnL -= fundingShare
            remaining.lastMarkPrice = fillPrice
            remaining.updatedAt = now
            account.positions[index] = remaining
        }

        return PaperTradeExecution(
            id: UUID(),
            coin: position.coin,
            symbol: position.symbol,
            side: position.side,
            kind: kind,
            size: size,
            price: fillPrice,
            notional: notional,
            leverage: position.leverage,
            fee: fee,
            realizedPnL: pricePnL + fundingShare,
            executedAt: now
        )
    }

    private func liquidate(
        position: PaperTradingPosition,
        index: Int,
        market: HyperliquidPerpMarket,
        now: Date,
        account: inout PaperTradingAccount
    ) -> PaperTradeExecution {
        let fillPrice = position.side == .long
            ? market.bestAvailableSellPrice
            : market.bestAvailableBuyPrice
        let pricePnL = position.side.sign * position.size * (fillPrice - position.entryPrice)
        let notional = position.size * fillPrice
        let fee = notional * Self.simulatedTakerFeeRate
        let residualEquity = max(0, position.isolatedMargin + pricePnL - fee)
        account.availableBalance += residualEquity
        account.realizedPnL += pricePnL + position.fundingPnL
        account.feesPaid += fee
        account.positions.remove(at: index)
        return PaperTradeExecution(
            id: UUID(),
            coin: position.coin,
            symbol: position.symbol,
            side: position.side,
            kind: .liquidated,
            size: position.size,
            price: fillPrice,
            notional: notional,
            leverage: position.leverage,
            fee: fee,
            realizedPnL: pricePnL + position.fundingPnL,
            executedAt: now
        )
    }

    private func commit(_ value: PaperTradingAccount) {
        var recorded = value
        recorded.valuationHistory = PortfolioValuationHistory.recording(
            value.equity, at: value.updatedAt, in: value.valuationHistory ?? [])
        account = recorded
        storage.save(recorded)
    }

    private static func estimatedLiquidationPrice(
        side: PaperTradeSide,
        entryPrice: Double,
        size: Double,
        isolatedMargin: Double,
        maxLeverage: Int
    ) -> Double? {
        guard size > 0 else { return nil }
        let maintenanceRate = 1 / (2 * Double(max(1, maxLeverage)))
        let marginPerUnit = isolatedMargin / size
        let value: Double
        switch side {
        case .long:
            value = (entryPrice - marginPerUnit) / (1 - maintenanceRate)
        case .short:
            value = (entryPrice + marginPerUnit) / (1 + maintenanceRate)
        }
        return value.isFinite && value > 0 ? value : nil
    }
}
